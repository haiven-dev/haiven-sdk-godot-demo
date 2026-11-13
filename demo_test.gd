# Headless test of the Godot demo over a fake socket and REST request: chat
# sends and their moderation outcomes, other players' messages, entitlements
# becoming inventory on connect and on push, and the socket closing.
extends SceneTree

const Demo := preload("res://haiven_demo.gd")
const Session := preload("res://addons/haiven/haiven_session.gd")
const RestError := preload("res://addons/haiven/haiven_rest_error.gd")


class FakeSocket:
	extends RefCounted
	var sent: Array[Dictionary] = []
	var _inbox: Array[String] = []
	var _state := WebSocketPeer.STATE_OPEN
	var _close_code := -1

	func poll() -> void:
		pass

	func get_ready_state() -> int:
		return _state

	func get_available_packet_count() -> int:
		return _inbox.size()

	func get_packet() -> PackedByteArray:
		return _inbox.pop_front().to_utf8_buffer()

	func send_text(text: String) -> int:
		sent.append(JSON.parse_string(text))
		return OK

	func close(code: int = 1000, _reason: String = "") -> void:
		_close_code = code
		_state = WebSocketPeer.STATE_CLOSED

	func get_close_code() -> int:
		return _close_code

	func get_close_reason() -> String:
		return ""

	func deliver(frame: Dictionary) -> void:
		_inbox.append(JSON.stringify(frame))


var failures: Array[String] = []
var checks := 0
var requests: Array[String] = []
var response: Variant = null
var lines: Array[String] = []
var keyed: Dictionary = {}


func check(what: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(what)
		print("FAIL ", what)


func request(method: String, path: String, _body: Variant, _content_type: String) -> Variant:
	requests.append("%s %s" % [method, path])
	return response


func record(key: String, text: String) -> void:
	if key != "" and keyed.has(key):
		lines[keyed[key]] = text
		return
	if key != "":
		keyed[key] = lines.size()
	lines.append(text)


func last_sent(socket: FakeSocket, type: String) -> Dictionary:
	for index in range(socket.sent.size() - 1, -1, -1):
		if socket.sent[index].get("type") == type:
			return socket.sent[index]
	return {}


func _initialize() -> void:
	var env := {"HAIVEN_DEMO_BASE_URL": "https://api.example.test/v0", "HAIVEN_DEMO_APP_ID": "app"}
	var read := func(name: String) -> String: return env.get(name, "")
	check("missing settings are named", Demo.read_settings(read).get("missing", "")
		== "HAIVEN_DEMO_REALTIME_URL, HAIVEN_DEMO_CHANNEL_ID")
	var no_integration := Demo.motd_integration_id(read)
	env["HAIVEN_DEMO_INTEGRATION_ID"] = "integration"
	env["HAIVEN_DEMO_REALTIME_URL"] = "wss://api.example.test/v0/ws"
	env["HAIVEN_DEMO_CHANNEL_ID"] = "general"
	check("complete settings load, and the MOTD id is the integration id, never the app id, empty when unset",
		Demo.read_settings(read).get("HAIVEN_DEMO_CHANNEL_ID") == "general"
		and no_integration == "" and Demo.motd_integration_id(read) == "integration")


	var socket := FakeSocket.new()
	var demo: Node = Demo.new()
	demo.line_changed.connect(record)
	response = {
		"id": "00000000-0000-4000-8000-000000000101",
		"title": "Public launch notice",
		"body": "Available before sign-in.",
		"url": "https://news.haiven.gg/launch",
		"startsAt": "2026-10-14T00:00:00Z",
	}
	demo.start_public_motd(request, "public-integration")
	await process_frame
	check("the public MOTD request runs without a token gate",
		requests == ["GET /motd?integration_id=public-integration"])
	check("the public result is retained before session authentication",
		demo.identity.current_motd.get("title") == "Public launch notice")
	requests.clear()
	response = {"entitlements": [
		{"code": "tag/hero", "kind": "item", "state": "active"},
		{"code": "haiven_subscription", "kind": "subscription", "state": "active"},
	]}
	demo.start(socket, func() -> String: return "token", request, "general")
	demo._process(0.0)
	var auth: Dictionary = socket.sent[0]
	check("the session authenticates first", auth.get("type") == "auth" and auth.get("payload") == "token")
	socket.deliver({"type": "auth.success", "requestId": auth["requestId"], "success": true})
	demo._process(0.0)
	await process_frame
	check("connecting reads the account entitlements", requests == ["GET /users/me/entitlements"])
	check("an active item becomes inventory; a subscription does not",
		demo.inventory.codes() == PackedStringArray(["tag/hero"]))
	check("and the panel says so", lines.has("unlocked: tag/hero"))

	demo.send_chat("gg")
	var send := last_sent(socket, "chat.send")
	check("a send goes to the configured channel", send.get("payload", {}).get("channelId") == "general")
	check("and shows as sending", lines.back() == "you (sending): gg")
	socket.deliver({"type": "chat.send", "requestId": send["requestId"], "success": true,
		"payload": {"message": {"id": "m-1", "channelId": "general"}, "moderationState": "pending"}})
	demo._process(0.0)
	check("a held reply updates the same line", lines.count("you (held for review): gg") == 1
		and not lines.has("you (sending): gg"))

	var before := lines.size()
	socket.deliver({"type": "chat.message", "payload": {"id": "m-1", "channelId": "general",
		"clientMessageId": send["payload"]["clientMessageId"], "content": "gg"}})
	socket.deliver({"type": "chat.message", "payload": {"id": "m-2", "channelId": "general", "content": "hi",
		"author": {"id": "u-2", "username": "ana", "displayName": "Ana"}}})
	socket.deliver({"type": "chat.message", "payload": {"id": "m-3", "channelId": "other", "content": "elsewhere"}})
	demo._process(0.0)
	check("our echoed message is not shown twice, other channels are dropped",
		lines.size() == before + 1 and lines.back() == "Ana: hi")

	demo.send_chat("bad")
	var refused := last_sent(socket, "chat.send")
	socket.deliver({"type": "chat.send", "requestId": refused["requestId"], "success": false, "error": "content_too_long"})
	demo._process(0.0)
	check("a refusal keeps its code, found by presence of success", lines.back() == "you (refused: content_too_long): bad")

	response = {"entitlements": [
		{"code": "tag/hero", "kind": "item", "state": "active"},
		{"code": "skin/gold", "kind": "item", "state": "active"},
		{"code": "tag/old", "kind": "item", "state": "revoked"},
	]}
	socket.deliver({"type": "entitlements.updated", "payload": {"projectionVersion": 8}})
	demo._process(0.0)
	await process_frame
	check("an entitlements.updated push re-reads", requests.size() == 2)
	check("and grants only what is new and active",
		demo.inventory.codes() == PackedStringArray(["tag/hero", "skin/gold"]))

	response = RestError.new(500)
	await demo.refresh_entitlements()
	check("a failed read is reported, not thrown", lines.back() == "entitlements unavailable")

	demo.send_chat("lost")
	socket.close(1006)
	demo._process(0.0)
	check("a send unanswered when the socket closes is unconfirmed",
		lines.has("you (not confirmed yet, resent on reconnect): lost"))
	check("and the panel reports the close", lines.back() == "Haiven chat offline (1006).")
	var lost_id: String = last_sent(socket, "chat.send")["payload"]["clientMessageId"]
	var next_socket := FakeSocket.new()
	var next_session: RefCounted = Session.new(next_socket, func() -> String: return "token")
	demo.chat.attach(next_session)
	next_session.poll()
	next_socket.deliver({"type": "auth.success", "requestId": next_socket.sent[0]["requestId"], "success": true})
	next_session.poll()
	check("a new session resends it under the same client message id",
		last_sent(next_socket, "chat.send").get("payload", {}).get("clientMessageId") == lost_id
		and lines.has("you (sending): lost"))

	var scene: Control = load("res://demo.tscn").instantiate()
	root.add_child(scene)
	scene.show_line("a", "you (sending): x")
	scene.show_line("a", "you: x")
	scene.show_line("", "note")
	check("the scene keeps one line per key", scene.line_count() == 2)
	scene.show_inventory(demo.inventory.codes())
	check("the scene lists the inventory", scene.get_node("Row/Side/Inventory").item_count == 2)
	check("the scene owns the editor-visible chat and inventory hierarchy",
		scene.get_node("Row") is HBoxContainer
		and scene.get_node("Row/Chat/Log") is RichTextLabel
		and scene.get_node("Row/Chat/Input") is LineEdit
		and scene.get_node("Row/Side/Inventory") is ItemList)
	var motd_panel: PanelContainer = scene.get_node("Row/Side/HaivenMotdPanel")
	check("the scene owns an editor-authored MOTD hierarchy",
		motd_panel.get_node("Content/Message/Title") is Label
		and motd_panel.get_node("Content/Message/Body") is Label
		and motd_panel.get_node("Content/Message/Actions/Dismiss") is Button)
	motd_panel.bind(demo.identity)
	check("the scene accepts the signed-out public snapshot",
		motd_panel.view_state()["status"] == "present"
		and motd_panel.view_state()["message"]["title"] == "Public launch notice")
	check("the MOTD hierarchy exposes designer Theme seams",
		motd_panel.theme.get_type_variation_base(&"HaivenMotdTitle") == &"Label")
	check("the authored controls keep the behavior contract",
		scene.get_node("Row/Chat/Log").scroll_following
		and scene.get_node("Row/Chat/Input").placeholder_text == "Say something (Enter to send)")
	check("controls expose semantic designer theme hooks",
		scene.get_node("Row/Chat/Log").theme_type_variation == &"HaivenDemoChatLog"
		and scene.get_node("Row/Chat/Input").theme_type_variation == &"HaivenDemoChatInput"
		and scene.get_node("Row/Side/Inventory").theme_type_variation == &"HaivenDemoInventory")
	var demo_theme: Theme = scene.theme
	check("the demo theme maps hooks to stock Godot controls",
		demo_theme.get_type_variation_base(&"HaivenDemoChatLog") == &"RichTextLabel"
		and demo_theme.get_type_variation_base(&"HaivenDemoChatInput") == &"LineEdit"
		and demo_theme.get_type_variation_base(&"HaivenDemoInventory") == &"ItemList")
	var input: LineEdit = scene.get_node("Row/Chat/Input")
	input.text = "designer test"
	input.text_submitted.emit("designer test")
	check("the authored input signal invokes the behavior script",
		input.text.is_empty() and input.text_submitted.get_connections().size() == 1)
	check("the authored input receives initial keyboard focus",
		scene.get_viewport().gui_get_focus_owner() == input)
	demo.free()

	if failures.is_empty():
		print("HAIVEN_TEST_PASS demo %d" % checks)
		quit(0)
	else:
		print("HAIVEN_TEST_FAIL demo %d/%d" % [failures.size(), checks])
		quit(1)
