# The autoload singleton (`HaivenDemo`) that owns the Haiven connection: one
# session, the chat outbox, the inventory, and sign-in, driven from _process
# because Godot's WebSocketPeer only moves when polled.
#
# Settings come from environment variables, so no URL, id or token is written
# into the project. The socket and REST request are injectable for the
# headless test; a game would use the defaults.
extends Node

const Session := preload("res://addons/haiven/haiven_session.gd")
const RestApi := preload("res://addons/haiven/haiven_rest_api.gd")
const Identity := preload("res://addons/haiven/haiven_identity.gd")
const Protocol := preload("res://addons/haiven/haiven_protocol.gd")
const RestError := preload("res://addons/haiven/haiven_rest_error.gd")
const DemoChat := preload("demo_chat.gd")
const Inventory := preload("inventory_manager.gd")
const SignIn := preload("demo_sign_in.gd")
const HttpTransport := preload("res://addons/haiven/haiven_http_transport.gd")

const VARIABLES := [
	"HAIVEN_DEMO_BASE_URL", "HAIVEN_DEMO_REALTIME_URL", "HAIVEN_DEMO_APP_ID", "HAIVEN_DEMO_CHANNEL_ID"
]
const TOKEN_VARIABLE := "HAIVEN_DEMO_ACCESS_TOKEN"
const SIGN_IN_URL_VARIABLE := "HAIVEN_DEMO_SIGN_IN_URL"
const INTEGRATION_ID_VARIABLE := "HAIVEN_DEMO_INTEGRATION_ID"
const REDIRECT_URI_VARIABLE := "HAIVEN_DEMO_REDIRECT_URI"
## Registered browser callback. The game does not listen here. An ephemeral
## loopback is sent separately as delivery_uri.
const CALLBACK_PATH := "/connect/game/callback"

## A chat line was added or replaced; key is a client message id, or "" for a note.
signal line_changed(key: String, text: String)

var inventory: RefCounted = Inventory.new()
var chat: RefCounted
var identity: RefCounted
## "Sign in with Haiven"; null while the demo is off.
var sign_in: Node
var _session: RefCounted
var _rest: RefCounted
var _realtime_url := ""
var _channel_id := ""
var _request := Callable()
# Captured by an entitlements read before it awaits. Ending the credential
# bumps it, so a late response cannot grant or sign the next account out.
var _credential_generation := 0


func _ready() -> void:
	var settings := read_settings(OS.get_environment)
	if settings.has("missing"):
		_note.call_deferred("Haiven demo is off: set %s." % settings["missing"])
		return
	sign_in = SignIn.new(sign_in_options(settings, OS.get_environment), OS.get_environment(TOKEN_VARIABLE))
	add_child(sign_in)
	var transport := HttpTransport.new(settings["HAIVEN_DEMO_BASE_URL"], settings["HAIVEN_DEMO_APP_ID"], sign_in.tokens.read)
	add_child(transport)
	# Begin the public read before sign-in so signed-out players see the same
	# launch notice as signed-in players. GET /motd takes the game's public
	# launch integration id, which is not the app id, so with no integration id
	# there is nothing correct to send.
	var integration_id := motd_integration_id(OS.get_environment)
	if integration_id == "":
		_note.call_deferred("Message of the Day is off: set %s." % INTEGRATION_ID_VARIABLE)
	else:
		start_public_motd(transport.request, integration_id)
	_realtime_url = settings["HAIVEN_DEMO_REALTIME_URL"]
	_channel_id = settings["HAIVEN_DEMO_CHANNEL_ID"]
	_request = transport.request
	sign_in.changed.connect(func(presentation: Dictionary) -> void: _note(presentation["message"]))
	sign_in.signed_in.connect(connect_realtime)
	sign_in.credential_ended.connect(_on_credential_ended)
	if sign_in.is_signed_in():
		connect_realtime()
	else:
		_note.call_deferred(sign_in.current["message"])


## The sign-in options for [DemoSignIn]: the frontend sign-in page is never
## inferred from the API URL, and the exchange is under the REST base URL.
## The registered redirect defaults to that page's origin plus [constant CALLBACK_PATH]
## (SBX `https://sbx.haiven.gg/connect/game/callback`, local
## `http://127.0.0.1:3000/connect/game/callback`). [constant REDIRECT_URI_VARIABLE]
## replaces it. The demo does not listen on that address.
static func sign_in_options(settings: Dictionary, read: Callable) -> Dictionary:
	var sign_in_url: String = read.call(SIGN_IN_URL_VARIABLE)
	var redirect: String = read.call(REDIRECT_URI_VARIABLE)
	if redirect == "":
		redirect = frontend_callback(sign_in_url)
	return {
		"sign_in_url": sign_in_url,
		"exchange_url": String(settings["HAIVEN_DEMO_BASE_URL"]).trim_suffix("/") + "/auth/handoff/exchange",
		"integration_id": read.call(INTEGRATION_ID_VARIABLE),
		"redirect_url": redirect,
	}


## Origin of `sign_in_url` plus [constant CALLBACK_PATH], or "" when it is not an
## absolute http(s) URL. The host is lowercased so it matches the allowlist.
## The API URL is not consulted.
static func frontend_callback(sign_in_url: String) -> String:
	var without_query := sign_in_url.get_slice("#", 0).get_slice("?", 0)
	var scheme_end := without_query.find("://")
	if scheme_end <= 0:
		return ""
	var scheme := without_query.substr(0, scheme_end).to_lower()
	if scheme != "https" and scheme != "http":
		return ""
	var rest := without_query.substr(scheme_end + 3)
	if rest == "" or rest.begins_with("/") or rest.contains("@") or rest.contains(" "):
		return ""
	var slash := rest.find("/")
	var authority := rest if slash < 0 else rest.substr(0, slash)
	if authority == "" or authority.ends_with(":"):
		return ""
	if authority.begins_with("[") and authority.find("]") < 0:
		return ""
	return scheme + "://" + authority.to_lower() + CALLBACK_PATH


## Opens the realtime socket with the signed-in credential.
func connect_realtime() -> void:
	if _session != null:
		_session.close()
	var socket := WebSocketPeer.new()
	var error := socket.connect_to_url(_realtime_url)
	if error != OK:
		_note("Haiven connect failed: %s" % error_string(error))
		return
	start(socket, sign_in.tokens, _request, _channel_id)


## The id for GET /motd: the game's public launch integration id, never the
## app id, or "" when unset.
static func motd_integration_id(read: Callable) -> String:
	return read.call(INTEGRATION_ID_VARIABLE)


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
## `token` is a Callable or a token store, as [HaivenSession] takes. The chat
## object outlives the socket so a same-token reconnect can resend. Ending the
## credential forgets that outbox first; a new sign-in must not resend it.
func start(socket: Object, token: Variant, request: Callable, channel_id: String) -> void:
	_session = Session.new(socket, token)
	if _rest == null:
		_rest = RestApi.new(request)
	if chat == null:
		chat = DemoChat.new(channel_id)
		chat.line_changed.connect(func(key: String, text: String) -> void: line_changed.emit(key, text))
	chat.attach(_session)
	_session.authenticated.connect(_on_authenticated)
	_session.event_received.connect(_on_event)
	_session.expired.connect(_on_expired)
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
	var generation := _credential_generation
	var response: Variant = await _rest.get_users_me_entitlements()
	# This read went out for that credential. It may have ended while the
	# response was in flight, and someone else may be signed in now.
	if generation != _credential_generation:
		return
	# The packaged transport answers a failed read with a HaivenRestError, not
	# null; anything other than an entitlements object is unavailable.
	if not response is Dictionary:
		_note("entitlements unavailable")
		# A REST 401 is proof the bearer is no longer valid; a 403 is not.
		if sign_in != null and response is RestError and response.status_code == 401:
			sign_in.end_credential()
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


func _on_expired() -> void:
	# Emitted before the session re-sends the store's current token on this
	# socket. Clearing or closing inside the signal makes Godot 4.5.1 reject
	# that send, so the credential ends once this poll returns.
	_end_lapsed_credential.call_deferred()


func _end_lapsed_credential() -> void:
	# The game handoff has no refresh: a lapsed bearer means signing in again.
	if sign_in != null:
		sign_in.end_credential()


func _on_closed(code: int, _reason: String) -> void:
	_note("Haiven chat offline (%d)." % code)
	if sign_in != null and Protocol.close_requires_sign_in(_session.close_kind):
		sign_in.end_credential()


func _on_credential_ended() -> void:
	# Retire reads that started under this credential before clearing, so a
	# response already on the wire cannot refill the inventory or sign the
	# next account out.
	_credential_generation += 1
	# The next sign-in may be a different account. Forget this one's unsent
	# chat and inventory before that start() attaches the outbox again.
	if chat != null:
		chat.forget_outbox()
	inventory.clear()
	if _session != null:
		_session.close()


func _note(text: String) -> void:
	line_changed.emit("", text)
