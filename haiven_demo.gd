# The autoload singleton (`HaivenDemo`) that owns the Haiven connection: one
# session, the chat outbox, and the inventory, driven from _process because
# Godot's WebSocketPeer only moves when polled.
#
# Settings come from environment variables, so no URL, id or token is written
# into the project. The socket and REST request are injectable for the
# headless test; a game would use the defaults.
extends Node

const Session := preload("res://addons/haiven/haiven_session.gd")
const RestApi := preload("res://addons/haiven/haiven_rest_api.gd")
const Identity := preload("res://addons/haiven/haiven_identity.gd")
const DemoChat := preload("demo_chat.gd")
const Inventory := preload("inventory_manager.gd")
const HttpTransport := preload("res://addons/haiven/haiven_http_transport.gd")

const VARIABLES := [
	"HAIVEN_DEMO_BASE_URL", "HAIVEN_DEMO_REALTIME_URL", "HAIVEN_DEMO_APP_ID", "HAIVEN_DEMO_CHANNEL_ID"
]
const TOKEN_VARIABLE := "HAIVEN_DEMO_ACCESS_TOKEN"

## A chat line was added or replaced; key is a client message id, or "" for a note.
signal line_changed(key: String, text: String)

var inventory: RefCounted = Inventory.new()
var chat: RefCounted
var identity: RefCounted
var _session: RefCounted
var _rest: RefCounted


func _ready() -> void:
	var settings := read_settings(OS.get_environment)
	var token := OS.get_environment(TOKEN_VARIABLE)
	if settings.has("missing"):
		_note.call_deferred("Haiven demo is off: set %s." % settings["missing"])
		return
	var transport := HttpTransport.new(settings["HAIVEN_DEMO_BASE_URL"], settings["HAIVEN_DEMO_APP_ID"], func() -> String: return token)
	add_child(transport)
	# Begin the public read before the access-token gate so signed-out players see
	# the same launch notice as signed-in players.
	start_public_motd(transport.request, settings["HAIVEN_DEMO_APP_ID"])
	if token == "":
		_note.call_deferred("Set %s to connect." % TOKEN_VARIABLE)
		return
	var socket := WebSocketPeer.new()
	var error := socket.connect_to_url(settings["HAIVEN_DEMO_REALTIME_URL"])
	if error != OK:
		_note.call_deferred("Haiven connect failed: %s" % error_string(error))
		return
	start(socket, func() -> String: return token, transport.request, settings["HAIVEN_DEMO_CHANNEL_ID"])


## The settings, or {"missing": "<names>"} when any is unset.
static func read_settings(read: Callable) -> Dictionary:
	var result := {}
	var missing := PackedStringArray()
	for variable: String in VARIABLES:
		var value: String = read.call(variable)
		if value == "":
			missing.append(variable)
		result[variable] = value
	return {"missing": ", ".join(missing)} if not missing.is_empty() else result


## Wires a session over `socket` (anything shaped like WebSocketPeer) and a REST
## request Callable; the test calls this directly with fakes.
func start(socket: Object, token: Callable, request: Callable, channel_id: String) -> void:
	_session = Session.new(socket, token)
	if _rest == null:
		_rest = RestApi.new(request)
	chat = DemoChat.new(channel_id)
	chat.line_changed.connect(func(key: String, text: String) -> void: line_changed.emit(key, text))
	chat.attach(_session)
	_session.authenticated.connect(_on_authenticated)
	_session.event_received.connect(_on_event)
	_session.closed.connect(_on_closed)
	_session.authentication_failed.connect(func(code: String) -> void: _note("Haiven sign-in failed: %s" % code))


## Starts the public presentation independently of the authenticated session.
func start_public_motd(request: Callable, integration_id: String) -> void:
	_rest = RestApi.new(request)
	identity = Identity.new(_rest, integration_id)
	identity.load_motd()


func _process(_delta: float) -> void:
	if _session != null:
		_session.poll()


func send_chat(content: String) -> void:
	if _session == null or content.strip_edges() == "":
		return
	chat.send(content)


func refresh_entitlements() -> void:
	var response: Variant = await _rest.get_users_me_entitlements()
	# The packaged transport answers a failed read with a HaivenRestError, not
	# null; anything other than an entitlements object is unavailable.
	if not response is Dictionary:
		_note("entitlements unavailable")
		return
	for code: String in inventory.grant_from(response):
		_note("unlocked: %s" % code)


func _on_authenticated() -> void:
	_note("Haiven chat connected. Press Enter to talk.")
	refresh_entitlements()


func _on_event(frame: Dictionary) -> void:
	# The push is a refresh hint: it carries a projection version, not the entitlements.
	if frame.get("type", "") == "entitlements.updated":
		refresh_entitlements()


func _on_closed(code: int, _reason: String) -> void:
	_note("Haiven chat offline (%d)." % code)


func _note(text: String) -> void:
	line_changed.emit("", text)
