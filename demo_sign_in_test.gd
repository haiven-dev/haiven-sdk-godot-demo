# Headless test of the demo's "Sign in with Haiven": the loopback listener over
# a real 127.0.0.1 socket, and the sign-in states around HaivenHandoff with the
# browser and the code exchange injected. No network beyond loopback and no
# real credential: the bearer here is a placeholder string.
extends SceneTree

const Demo := preload("res://haiven_demo.gd")
const SignIn := preload("res://demo_sign_in.gd")
const Loopback := preload("res://loopback_callback.gd")
const RestError := preload("res://addons/haiven/haiven_rest_error.gd")
const Chat := preload("res://addons/haiven/haiven_chat.gd")

const SIGN_IN_URL := "https://sbx.example.test/connect/game"
const EXCHANGE_URL := "https://api.example.test/v0/auth/handoff/exchange"
const REGISTERED_REDIRECT := "https://sbx.example.test/connect/game/callback"
const NOW := 1_789_646_400_000


# start_ephemeral fails, so sign-in stops before opening the browser.
class BindFailure:
	extends RefCounted
	signal received(callback_url: String)

	func start_ephemeral() -> String:
		return ""

	func stop() -> void:
		pass

	func poll() -> void:
		pass

	func is_listening() -> bool:
		return false


class FakeSocket:
	extends RefCounted
	var sent: Array[Dictionary] = []
	var rejected := 0
	var _inbox: Array[String] = []
	var _state := WebSocketPeer.STATE_OPEN
	var _close_code := -1
	var _close_reason := ""

	func poll() -> void:
		pass

	func get_ready_state() -> int:
		return _state

	func get_available_packet_count() -> int:
		return _inbox.size()

	func get_packet() -> PackedByteArray:
		return _inbox.pop_front().to_utf8_buffer()

	func send_text(text: String) -> int:
		# Godot 4.5.1 rejects a send once close() has left STATE_OPEN.
		if _state != WebSocketPeer.STATE_OPEN:
			rejected += 1
			return ERR_UNAVAILABLE
		sent.append(JSON.parse_string(text))
		return OK

	func close(code: int = 1000, reason: String = "") -> void:
		_close_code = code
		_close_reason = reason
		_state = WebSocketPeer.STATE_CLOSED

	func get_close_code() -> int:
		return _close_code

	func get_close_reason() -> String:
		return _close_reason

	func deliver(frame: Dictionary) -> void:
		_inbox.append(JSON.stringify(frame))


# Completes request() when resume() is called, so an entitlements read can stay
# suspended across end_credential and then finish with a chosen body.
class SuspendedReply:
	extends RefCounted

	signal _opened

	var started := 0
	var settled := false
	var _value: Variant = null

	func request(_method: String, _path: String, _body: Variant, _content_type: String) -> Variant:
		started += 1
		while not settled:
			await _opened
		return _value

	func resume(value: Variant) -> void:
		_value = value
		settled = true
		_opened.emit()


var failures: Array[String] = []
var checks := 0
var _now := NOW
var _opened: Array[String] = []
var _exchanges: Array[Dictionary] = []
var _exchange_reply := {"status": 200, "body": JSON.stringify({"access_token": "placeholder-bearer", "token_type": "Bearer", "expires_in": 300})}


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)
		print("FAIL ", what)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	check("a 127.0.0.1 redirect with a port is served",
		Loopback.parse_redirect("http://127.0.0.1:40123/haiven/callback")
		== {"address": "127.0.0.1", "port": 40123, "origin": "http://127.0.0.1:40123", "path": "/haiven/callback"})
	check("an IPv6 loopback redirect is served",
		Loopback.parse_redirect("http://[::1]:40123/cb").get("address") == "::1")
	check("a host name, https, a missing port, or a fragment is refused",
		Loopback.parse_redirect("http://localhost:40123/cb").is_empty()
		and Loopback.parse_redirect("https://127.0.0.1:40123/cb").is_empty()
		and Loopback.parse_redirect("http://127.0.0.1/cb").is_empty()
		and Loopback.parse_redirect("http://127.0.0.1:40123/cb#x").is_empty())

	var port := _free_port()
	var redirect := "http://127.0.0.1:%d/haiven/callback" % port
	var listener: RefCounted = Loopback.new()
	var received: Array[String] = []
	listener.received.connect(func(url: String) -> void: received.append(url))
	check("the listener binds the redirect's port", listener.start(redirect) == OK)
	var second: RefCounted = Loopback.new()
	check("a second listener on the same port fails to bind", second.start(redirect) != OK)
	var probe: String = await _http_get(port, "/favicon.ico", listener)
	check("another path gets a 404 and does not end the wait",
		probe.begins_with("HTTP/1.1 404") and received.is_empty() and listener.is_listening())
	var page: String = await _http_get(port, "/haiven/callback?code=one%20use&state=s1", listener)
	check("the redirect path is answered with a no-store page that echoes nothing",
		page.begins_with("HTTP/1.1 200") and page.contains("Cache-Control: no-store")
		and page.contains("return to the game") and not page.contains("one%20use"))
	check("the full callback URL is handed on unparsed",
		received == ["http://127.0.0.1:%d/haiven/callback?code=one%%20use&state=s1" % port])
	check("and the listener stops", not listener.is_listening())

	var settings := {"HAIVEN_DEMO_BASE_URL": "https://api.example.test/v0/"}
	var empty: Dictionary = Demo.sign_in_options(settings, _env({}))
	var sbx: Dictionary = Demo.sign_in_options(settings, _env({
		Demo.SIGN_IN_URL_VARIABLE: "https://sbx.haiven.gg/connect/game",
	}))
	var local: Dictionary = Demo.sign_in_options(settings, _env({
		Demo.SIGN_IN_URL_VARIABLE: "http://127.0.0.1:3000/connect/game",
	}))
	var chosen: Dictionary = Demo.sign_in_options(settings, _env({
		Demo.SIGN_IN_URL_VARIABLE: "http://127.0.0.1:3000/connect/game",
		Demo.REDIRECT_URI_VARIABLE: "https://sbx.haiven.gg/connect/game/callback",
	}))
	check("the registered redirect is the frontend callback for SBX or a local page",
		empty["redirect_url"] == ""
		and sbx["redirect_url"] == "https://sbx.haiven.gg/connect/game/callback"
		and local["redirect_url"] == "http://127.0.0.1:3000/connect/game/callback"
		and chosen["redirect_url"] == "https://sbx.haiven.gg/connect/game/callback")
	check("the exchange is under the REST base URL and the sign-in page is never inferred",
		empty["exchange_url"] == EXCHANGE_URL and empty["sign_in_url"] == "")

	var unconfigured := _sign_in({"sign_in_url": "", "integration_id": "game", "redirect_url": redirect})
	check("without a sign-in URL sign-in is off and offers no control",
		unconfigured.current["state"] == SignIn.State.NOT_CONFIGURED and unconfigured.current["action"] == "")

	var shortcut := _sign_in(_options(REGISTERED_REDIRECT), "placeholder-env-token")
	shortcut.sign_in()
	check("an environment token starts signed in and never opens the browser",
		shortcut.is_signed_in() and shortcut.tokens.read() == "placeholder-env-token" and _opened.is_empty())

	var flow := _sign_in(_options(REGISTERED_REDIRECT))
	var signed_in: Array[bool] = []
	flow.signed_in.connect(func() -> void: signed_in.append(true))
	check("configured, it starts signed out with the product copy",
		flow.current == SignIn.SIGNED_OUT and flow.current["action"] == "Continue with Haiven")
	flow.sign_in()
	var authorization := _query(_opened.back() if not _opened.is_empty() else "")
	var delivery := String(authorization.get("delivery_uri", ""))
	var delivery_port := int(Loopback.parse_redirect(delivery).get("port", 0))
	check("sign-in opens the browser with the registered redirect and an ephemeral delivery address",
		_opened.size() == 1 and _opened[0].begins_with(SIGN_IN_URL + "?")
		and authorization.get("redirect_uri") == REGISTERED_REDIRECT
		and authorization.get("integration_id") == "game"
		and authorization.get("code_challenge_method") == "S256"
		and delivery == "http://127.0.0.1:%d/haiven/callback" % delivery_port
		and delivery_port > 0 and delivery_port != Loopback.REFUSED_PORT)
	check("and waits for Haiven", flow.current == SignIn.WAITING)
	await _http_get(delivery_port, "/haiven/callback?code=code-1&state=%s" % authorization.get("state", "").uri_encode(), flow._listener)
	await _frames(func() -> bool: return flow.is_signed_in())
	check("the browser's redirect exchanges the code at the exchange URL",
		_exchanges.size() == 1 and _exchanges[0]["url"] == EXCHANGE_URL
		and _exchanges[0]["body"].contains("code=code-1")
		and _exchanges[0]["body"].contains("redirect_uri=" + REGISTERED_REDIRECT.uri_encode())
		and not _exchanges[0]["body"].contains("127.0.0.1"))
	check("and signs in with the bearer held in the shared store",
		flow.current == SignIn.SIGNED_IN and flow.tokens.read() == "placeholder-bearer" and signed_in == [true])
	var ended: Array[bool] = []
	flow.credential_ended.connect(func() -> void: ended.append(true))
	_now += 300_000
	await process_frame
	check("the credential's expiry ends it with the session-expired copy",
		flow.current == SignIn.SESSION_EXPIRED and flow.tokens.read() == "" and ended == [true])

	var listening: RefCounted = flow._listener
	flow._listener = BindFailure.new()
	var opens_before := _opened.size()
	flow.sign_in()
	check("a failed loopback bind stops sign-in before the browser opens",
		flow.current == SignIn.PORT_BUSY and _opened.size() == opens_before)
	flow._listener = listening

	flow.sign_in()
	var cancelled_state: String = _query(_opened.back()).get("state", "")
	var cancel_port := int(Loopback.parse_redirect(String(_query(_opened.back()).get("delivery_uri", ""))).get("port", 0))
	await _http_get(cancel_port, "/haiven/callback?error=access_denied&state=%s" % cancelled_state.uri_encode(), flow._listener)
	await _frames(func() -> bool: return flow.current != SignIn.WAITING)
	check("a cancelled sign-in says so and offers a retry",
		flow.current == SignIn.CANCELLED and _exchanges.size() == 1)

	flow.sign_in()
	_now += SignIn.WAIT_TIMEOUT_MSEC + 1
	await process_frame
	check("no redirect within the wait window expires the link",
		flow.current == SignIn.LINK_EXPIRED and not flow._listener.is_listening())
	check("an unavailable server and a refused code read as finite states",
		SignIn.classify("exchange_http_503") == SignIn.UNAVAILABLE
		and SignIn.classify("exchange_http_400") == SignIn.LINK_EXPIRED)

	# The autoload ends the credential on proof it is invalid, not on a 403.
	var demo: Node = Demo.new()
	demo.sign_in = _sign_in(_options(redirect), "placeholder-env-token")
	var socket := FakeSocket.new()
	demo.start(socket, demo.sign_in.tokens, func(_m: String, _p: String, _b: Variant, _c: String) -> Variant: return RestError.new(403), "general")
	await demo.refresh_entitlements()
	check("a REST 403 keeps the credential", demo.sign_in.is_signed_in())
	demo._rest = null
	demo.start(socket, demo.sign_in.tokens, func(_m: String, _p: String, _b: Variant, _c: String) -> Variant: return RestError.new(401), "general")
	await demo.refresh_entitlements()
	check("a REST 401 ends it", demo.sign_in.current["state"] == SignIn.State.EXPIRED and demo.sign_in.tokens.read() == "")
	demo.sign_in = _sign_in(_options(redirect), "placeholder-env-token")
	var revoked := FakeSocket.new()
	demo.start(revoked, demo.sign_in.tokens, func(_m: String, _p: String, _b: Variant, _c: String) -> Variant: return null, "general")
	demo._process(0.0)
	revoked.close(1008, "credential_revoked")
	demo._process(0.0)
	check("a credential_revoked close ends it", demo.sign_in.current == SignIn.SESSION_EXPIRED)
	demo.free()

	# auth.expired re-auths on this socket before the credential is cleared.
	var lapsed: Node = Demo.new()
	lapsed.sign_in = _sign_in(_options(redirect), "placeholder-env-token")
	# _ready connects this. The headless test has no environment, so it does too.
	lapsed.sign_in.credential_ended.connect(lapsed._on_credential_ended)
	var live := FakeSocket.new()
	lapsed.start(live, lapsed.sign_in.tokens, func(_m: String, _p: String, _b: Variant, _c: String) -> Variant: return {"entitlements": []}, "general")
	lapsed._process(0.0)
	live.deliver({"type": "auth.success", "requestId": live.sent[0]["requestId"], "success": true})
	lapsed._process(0.0)
	var sent_before_expiry := live.sent.size()
	live.deliver({"type": "auth.expired", "requestId": "", "success": false})
	lapsed._process(0.0)
	var reauth: Dictionary = live.sent.back() if live.sent.size() == sent_before_expiry + 1 else {}
	check("auth.expired re-auths on the open socket with the current bearer",
		live.rejected == 0 and reauth.get("type") == "auth" and reauth.get("payload") == "placeholder-env-token")
	await process_frame
	check("the lapsed credential ends after that re-auth",
		lapsed.sign_in.current == SignIn.SESSION_EXPIRED and lapsed.sign_in.tokens.read() == "")
	lapsed.free()

	# An unconfirmed outbox belongs to the account that ended, not the next one.
	var switched: Node = Demo.new()
	switched.sign_in = _sign_in(_options(redirect), "placeholder-env-token")
	switched.sign_in.credential_ended.connect(switched._on_credential_ended)
	var holder := {"body": {"entitlements": [{"code": "tag/hero", "kind": "item", "state": "active"}]}}
	var ask := func(_m: String, _p: String, _b: Variant, _c: String) -> Variant: return holder["body"]
	var first := FakeSocket.new()
	switched.start(first, switched.sign_in.tokens, ask, "general")
	switched._process(0.0)
	first.deliver({"type": "auth.success", "requestId": first.sent[0]["requestId"], "success": true})
	switched._process(0.0)
	await process_frame
	switched.send_chat("from the last account")
	var previous_id: String = first.sent.back()["payload"]["clientMessageId"]
	first.close(1006, "")
	switched._process(0.0)
	var unconfirmed: Array = switched.chat.chat.outbox()
	check("an unanswered send is unconfirmed while that account's items are held",
		unconfirmed.size() == 1
		and unconfirmed[0].content == "from the last account"
		and unconfirmed[0].state == Chat.OutgoingState.UNCONFIRMED
		and switched.inventory.codes() == PackedStringArray(["tag/hero"]))
	switched.sign_in.end_credential()
	holder["body"] = {"entitlements": [{"code": "skin/gold", "kind": "item", "state": "active"}]}
	switched.sign_in.tokens.write("next-account-token", -1)
	var next := FakeSocket.new()
	switched.start(next, switched.sign_in.tokens, ask, "general")
	switched._process(0.0)
	next.deliver({"type": "auth.success", "requestId": next.sent[0]["requestId"], "success": true})
	switched._process(0.0)
	await process_frame
	var resent := false
	for frame in next.sent:
		var payload: Variant = frame.get("payload")
		if frame.get("type") != "chat.send" or not payload is Dictionary:
			continue
		if payload.get("content") == "from the last account" or payload.get("clientMessageId") == previous_id:
			resent = true
	var handshake: Dictionary = next.sent[0] if not next.sent.is_empty() else {}
	check("a later sign-in does not resend the previous account's unconfirmed chat",
		not resent and handshake.get("type") == "auth" and handshake.get("payload") == "next-account-token")
	check("and lists only the new account's items",
		switched.inventory.codes() == PackedStringArray(["skin/gold"]))
	switched.free()

	# The read above returns before end_credential. This one is still awaiting
	# when that account's credential ends, then resumes with its entitlements.
	var late: Node = Demo.new()
	var late_lines: Array[String] = []
	late.line_changed.connect(func(_key: String, text: String) -> void: late_lines.append(text))
	late.sign_in = _sign_in(_options(redirect), "placeholder-env-token")
	late.sign_in.credential_ended.connect(late._on_credential_ended)
	var late_gate := SuspendedReply.new()
	var late_socket := FakeSocket.new()
	late.start(late_socket, late.sign_in.tokens, late_gate.request, "general")
	late._process(0.0)
	late_socket.deliver({"type": "auth.success", "requestId": late_socket.sent[0]["requestId"], "success": true})
	late._process(0.0)
	var late_suspended: bool = late_gate.started == 1 and not late_gate.settled and late.inventory.codes().is_empty()
	late.sign_in.end_credential()
	check("an entitlements read stays suspended across the credential end",
		late_suspended and late_gate.started == 1 and not late_gate.settled
		and not late.sign_in.is_signed_in() and late.inventory.codes().is_empty())
	late_gate.resume({"entitlements": [{"code": "tag/hero", "kind": "item", "state": "active"}]})
	check("a late entitlements body from the previous account does not refill inventory",
		late_gate.settled and late.inventory.codes().is_empty() and not late_lines.has("unlocked: tag/hero"))
	late.free()

	# The same suspended read, resumed with the 401 the transport returns once
	# that bearer is refused. The next account has already finished signing in.
	var stale: Node = Demo.new()
	stale.sign_in = _sign_in(_options(redirect), "placeholder-env-token")
	var stale_endings: Array[int] = [0]
	stale.sign_in.credential_ended.connect(func() -> void: stale_endings[0] += 1)
	stale.sign_in.credential_ended.connect(stale._on_credential_ended)
	var stale_gate := SuspendedReply.new()
	var stale_socket := FakeSocket.new()
	stale.start(stale_socket, stale.sign_in.tokens, stale_gate.request, "general")
	stale._process(0.0)
	stale_socket.deliver({"type": "auth.success", "requestId": stale_socket.sent[0]["requestId"], "success": true})
	stale._process(0.0)
	var stale_suspended := stale_gate.started == 1 and not stale_gate.settled
	stale.sign_in.end_credential()
	var opens_before_next := _opened.size()
	stale.sign_in.sign_in()
	var next_authorization := _query(_opened.back() if _opened.size() == opens_before_next + 1 else "")
	var next_port := int(Loopback.parse_redirect(String(next_authorization.get("delivery_uri", ""))).get("port", 0))
	await _http_get(next_port, "/haiven/callback?code=code-next&state=%s" % next_authorization.get("state", "").uri_encode(), stale.sign_in._listener)
	await _frames(func() -> bool: return stale.sign_in.is_signed_in())
	var next_token: String = stale.sign_in.tokens.read()
	check("the next account is signed in while the previous entitlements read is still suspended",
		stale_suspended and stale.sign_in.is_signed_in() and next_token == "placeholder-bearer"
		and stale_gate.started == 1 and not stale_gate.settled and stale_endings[0] == 1)
	stale_gate.resume(RestError.new(401))
	check("a stale 401 from that read does not sign the next account out",
		stale.sign_in.is_signed_in() and stale.sign_in.tokens.read() == next_token
		and stale_endings[0] == 1 and stale.inventory.codes().is_empty())
	stale.free()

	var scene: Control = load("res://demo.tscn").instantiate()
	root.add_child(scene)
	var button: Button = scene.get_node("Row/Chat/SignIn")
	scene.show_sign_in(SignIn.SIGNED_OUT)
	var shown := button.visible and button.text == "Continue with Haiven"
	scene.show_sign_in(SignIn.SIGNED_IN)
	check("the scene shows the sign-in control only when there is an action",
		shown and not button.visible and button.theme_type_variation == &"HaivenDemoSignIn")
	scene.free()

	if failures.is_empty():
		print("HAIVEN_TEST_PASS demo_sign_in %d" % checks)
		quit(0)
	else:
		print("HAIVEN_TEST_FAIL demo_sign_in %d/%d" % [failures.size(), checks])
		quit(1)


func _options(redirect: String) -> Dictionary:
	return {"sign_in_url": SIGN_IN_URL, "exchange_url": EXCHANGE_URL, "integration_id": "game", "redirect_url": redirect}


func _env(values: Dictionary) -> Callable:
	return func(name: String) -> String: return String(values.get(name, ""))


func _sign_in(options: Dictionary, environment_token: String = "") -> Node:
	var sign_in: Node = SignIn.new(options, environment_token, _launch, _exchange, func() -> int: return _now)
	root.add_child(sign_in)
	return sign_in


func _launch(url: String) -> int:
	_opened.append(url)
	return OK


func _exchange(url: String, _headers: PackedStringArray, body: String) -> Dictionary:
	_exchanges.append({"url": url, "body": body})
	return _exchange_reply


func _free_port() -> int:
	for _attempt in 4:
		var server := TCPServer.new()
		server.listen(0, "127.0.0.1")
		var port := server.get_local_port()
		server.stop()
		if port != Loopback.REFUSED_PORT:
			return port
	return 0


# Waits up to ~2 s of frames for `done`.
func _frames(done: Callable) -> void:
	for _i in 240:
		if done.call():
			return
		await process_frame


# A browser's GET over a real loopback socket. `listener` is polled here when it
# is not inside a node that polls it each frame.
func _http_get(port: int, target: String, listener: RefCounted = null) -> String:
	var client := StreamPeerTCP.new()
	client.connect_to_host("127.0.0.1", port)
	var sent := false
	var response := PackedByteArray()
	for _i in 240:
		if listener != null:
			listener.poll()
		client.poll()
		var status := client.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				client.put_data(("GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n" % [target, port]).to_ascii_buffer())
				sent = true
			var available := client.get_available_bytes()
			if available > 0:
				response.append_array(client.get_partial_data(available)[1])
		elif sent or status == StreamPeerTCP.STATUS_ERROR:
			break
		await process_frame
	client.disconnect_from_host()
	return response.get_string_from_utf8()


func _query(url: String) -> Dictionary:
	var result := {}
	var question := url.find("?")
	if question < 0:
		return result
	for field in url.substr(question + 1).split("&", false):
		var text := String(field)
		var equals := text.find("=")
		var name := text if equals < 0 else text.substr(0, equals)
		var value := "" if equals < 0 else text.substr(equals + 1)
		result[name.uri_decode()] = value.uri_decode()
	return result
