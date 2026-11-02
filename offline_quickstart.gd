# A credentials-free wiring example for the distributable addon. It uses the
# same injected seams a game uses in tests or an offline development scene; no
# token, app secret, integration key, or live endpoint is required.
extends SceneTree

const Session := preload("res://addons/haiven/haiven_session.gd")
const Chat := preload("res://addons/haiven/haiven_chat.gd")
const RestApi := preload("res://addons/haiven/haiven_rest_api.gd")
const Rewards := preload("res://addons/haiven/haiven_rewards.gd")
const Analytics := preload("res://addons/haiven/haiven_analytics.gd")


class OfflineSocket:
	extends RefCounted
	var sent: Array[Dictionary] = []
	var inbox: Array[String] = []

	func poll() -> void:
		pass

	func get_ready_state() -> int:
		return WebSocketPeer.STATE_OPEN

	func get_available_packet_count() -> int:
		return inbox.size()

	func get_packet() -> PackedByteArray:
		return inbox.pop_front().to_utf8_buffer()

	func send_text(text: String) -> int:
		sent.append(JSON.parse_string(text))
		return OK

	func get_close_code() -> int:
		return -1

	func get_close_reason() -> String:
		return ""

	func deliver(frame: Dictionary) -> void:
		inbox.append(JSON.stringify(frame))


class OfflineTransport:
	extends RefCounted
	var replies: Array[Variant] = []
	var requests: Array[Dictionary] = []

	func request(method: String, path: String, body: Variant, content_type: String) -> Variant:
		requests.append({
			"method": method,
			"path": path,
			"body": body.duplicate(true) if body is Dictionary else body,
			"content_type": content_type,
		})
		return replies.pop_front()


var failures: Array[String] = []
var checks := 0
var _request_ids := 0


func check(name: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(name)
		print("FAIL ", name)


func _initialize() -> void:
	call_deferred("_run")


func next_request_id() -> String:
	_request_ids += 1
	return "offline-request-%d" % _request_ids


func _run() -> void:
	# The placeholder token never leaves this process. Production reads the real
	# player token at runtime; the SDK stores no credential in the addon.
	var socket := OfflineSocket.new()
	var session := Session.new(
		socket, func() -> String: return "example-access-token", next_request_id)
	check("session starts pending", session.state == Session.State.PENDING)

	var chat := Chat.new(func() -> String: return "offline-message-1")
	chat.attach(session)
	var outgoing: RefCounted = chat.send("local-channel", "hello from an offline scene")
	check("offline chat queues until authentication", outgoing.state == Chat.OutgoingState.SENDING)
	check("chat preserves its host-generated id", outgoing.client_message_id == "offline-message-1")

	session.poll()
	check("the open socket authenticates before queued chat",
		socket.sent.size() == 1 and socket.sent[0]["type"] == "auth"
		and socket.sent[0]["payload"] == "example-access-token")
	socket.deliver({"type": "auth.success", "requestId": socket.sent[0]["requestId"], "success": true})
	session.poll()
	check("the fake session reaches authenticated", session.state == Session.State.AUTHENTICATED)
	var chat_frame: Dictionary = socket.sent[1]
	check("authentication flushes the queued chat",
		chat_frame["type"] == "chat.send"
		and chat_frame["payload"]["clientMessageId"] == "offline-message-1")
	socket.deliver({"type": "chat.send", "requestId": chat_frame["requestId"], "success": true,
		"payload": {"message": {"id": "server-message-1"}, "moderationState": "allowed"}})
	session.poll()
	check("a correlated allowed reply accepts the chat message",
		outgoing.state == Chat.OutgoingState.ACCEPTED and outgoing.message_id == "server-message-1")

	var transport := OfflineTransport.new()
	var api := RestApi.new(transport.request)
	var rewards := Rewards.new(api, "public-integration-id", func() -> String: return "claim-1")
	transport.replies.append({"eligible": true, "basis": "subscription"})
	var eligibility: Dictionary = await rewards.eligibility()
	check("rewards use the generated eligibility operation",
		eligibility["eligible"] and transport.requests[-1]["path"] == "/users/me/rewards/eligibility")
	transport.replies.append({
		"claimId": "claim-1",
		"claimedAt": "2026-10-14T00:00:00Z",
		"confirmation": "client_reported",
		"integrationId": "public-integration-id",
		"rewardRef": "sample_reward",
	})
	var claimed: RefCounted = await rewards.claim("sample_reward")
	check("reward claim reaches a finite success", claimed.succeeded())

	var pumps: Array[Callable] = []
	var analytics := Analytics.new(
		api,
		{"integrationId": "public-integration-id", "environment": "offline",
			"platform": "godot", "sdk": {"name": "godot", "version": "0.0.0"}},
		{"flush_interval_seconds": 0.0},
		"offline-analytics-session",
		func() -> String: return "event-1",
		func() -> String: return "2026-10-14T00:00:00Z",
		Callable(),
		func(operation: Callable) -> void: pumps.append(operation),
	)
	transport.replies.append({"accepted": 1, "duplicate": 0, "rejected": []})
	check("analytics enqueue is nonblocking", analytics.enqueue("session.start")
		and transport.requests.size() == 2 and pumps.size() == 1)
	await pumps.pop_front().call()
	check("analytics uses the generated batching operation",
		transport.requests[-1]["path"] == "/sdk/analytics/events")
	check("analytics drains the offline batch", analytics.buffered_event_count() == 0)

	if failures.is_empty():
		print("HAIVEN_TEST_PASS readiness %d" % checks)
		quit(0)
	else:
		quit(1)
