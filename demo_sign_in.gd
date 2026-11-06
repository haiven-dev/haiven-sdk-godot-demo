# "Sign in with Haiven" for the desktop demo: the addon's PKCE game-login
# handoff (HaivenHandoff). The registered redirect is the frontend callback.
# An ephemeral loopback (loopback_callback.gd) receives the code, and that
# address is sent only as delivery_uri. It is the Godot counterpart of the
# Unity Boss Room demo's DemoSignIn.
#
# The access token lives only in the in-memory HaivenTokenStore that REST and
# the socket read, and is never logged, shown, or written to disk. A non-empty
# HAIVEN_DEMO_ACCESS_TOKEN is the shortcut: the demo starts signed in and never
# opens a browser.
extends Node

const Handoff := preload("res://addons/haiven/haiven_handoff.gd")
const TokenStore := preload("res://addons/haiven/haiven_token_store.gd")
const Loopback := preload("loopback_callback.gd")

enum State { NOT_CONFIGURED, SIGNED_OUT, SIGNING_IN, SIGNED_IN, FAILED, EXPIRED }

# Match the web handoff window, so first-time profile or age setup does not
# strand the player after the game has stopped listening.
const WAIT_TIMEOUT_MSEC := 30 * 60 * 1000

# The product copy from docs/game-auth-handoff.md: what the player reads, and
# the sign-in control's caption ("" hides it). Never a token, code, or error text.
const SIGNED_OUT := {"state": State.SIGNED_OUT, "message": "Continue with Haiven to join chat.", "action": "Continue with Haiven"}
const WAITING := {"state": State.SIGNING_IN, "message": "Waiting for Haiven… Finish signing in in your browser, then return to the game.", "action": "Try again"}
const SIGNED_IN := {"state": State.SIGNED_IN, "message": "Signed in with Haiven.", "action": ""}
const SIGNED_IN_WITH_TOKEN := {"state": State.SIGNED_IN, "message": "Using the access token from HAIVEN_DEMO_ACCESS_TOKEN.", "action": ""}
const NOT_CONFIGURED := {"state": State.NOT_CONFIGURED, "message": "Sign-in is off: set HAIVEN_DEMO_SIGN_IN_URL and HAIVEN_DEMO_INTEGRATION_ID, or HAIVEN_DEMO_ACCESS_TOKEN.", "action": ""}
const CANCELLED := {"state": State.FAILED, "message": "Sign-in was cancelled. No account was connected.", "action": "Try again"}
const PORT_BUSY := {"state": State.FAILED, "message": "The sign-in callback port is in use. Close the other copy of the game and try again.", "action": "Try again"}
const UNAVAILABLE := {"state": State.FAILED, "message": "Haiven sign-in is not available on this server yet.", "action": "Try again"}
const FAILED := {"state": State.FAILED, "message": "Haiven sign-in failed. Try again.", "action": "Try again"}
const LINK_EXPIRED := {"state": State.EXPIRED, "message": "This sign-in link expired. Start again to continue.", "action": "Start again"}
const SESSION_EXPIRED := {"state": State.EXPIRED, "message": "Your Haiven session expired. Sign in again to continue.", "action": "Sign in again"}

## The presentation changed; read [member current].
signal changed(presentation: Dictionary)
## A handoff finished and [member tokens] holds the new bearer.
signal signed_in()
## The signed-in credential ended (expiry, or the server refused it).
signal credential_ended()

## Read by REST and the socket at use time. Never log it.
var tokens: RefCounted = TokenStore.new()
var current: Dictionary
var _configured: bool
var _redirect_url: String
var _delivery_uri := ""
var _handoff: Node
var _listener: RefCounted = Loopback.new()
var _now: Callable
var _open_browser: Callable
var _pending_state := ""
var _waiting_since := -1
var _completing := false


## `options` holds `sign_in_url`, `exchange_url`, `integration_id`, and
## `redirect_url`. `launch_url`, `exchange` and `now` are HaivenHandoff's seams,
## injected by the headless test; the demo uses the defaults.
func _init(
	options: Dictionary,
	environment_token: String = "",
	launch_url: Callable = Callable(),
	exchange: Callable = Callable(),
	now: Callable = Callable(),
) -> void:
	name = "DemoSignIn"
	_now = now if now.is_valid() else func() -> int: return int(Time.get_unix_time_from_system() * 1000.0)
	_open_browser = launch_url
	_redirect_url = String(options.get("redirect_url", ""))
	_configured = (
		String(options.get("sign_in_url", "")) != ""
		and String(options.get("integration_id", "")) != ""
		and _usable_redirect(_redirect_url)
	)
	_handoff = Handoff.new(
		{
			"entry_url": options.get("sign_in_url", ""),
			"exchange_url": options.get("exchange_url", ""),
			"integration_id": options.get("integration_id", ""),
			"redirect_url": _redirect_url,
			"transaction_lifetime_msec": WAIT_TIMEOUT_MSEC,
		},
		tokens,
		_open_authorization,
		exchange,
		_now,
	)
	add_child(_handoff)  # Its default exchange is an HTTPRequest child.
	_listener.received.connect(_on_callback)
	if environment_token != "":
		tokens.write(environment_token, -1)
		current = SIGNED_IN_WITH_TOKEN
	else:
		current = SIGNED_OUT if _configured else NOT_CONFIGURED


func is_signed_in() -> bool:
	return current["state"] == State.SIGNED_IN


## Binds an ephemeral loopback, then opens Haiven's sign-in page in the browser
## with that address as delivery_uri. Calling it while the browser is pending
## abandons that attempt for a fresh one. The outcome arrives through [signal changed].
func sign_in() -> void:
	if not _configured or is_signed_in() or _completing:
		return
	_abandon()
	tokens.clear()
	# Bound before the browser opens, so a failed bind stops here, not after
	# the player signs in. The registered redirect is not this address.
	var delivery := String(_listener.start_ephemeral())
	if delivery == "":
		_publish(PORT_BUSY)
		return
	_delivery_uri = delivery
	var start: Dictionary = _handoff.begin_login()
	if not start.get("ok", false):
		_listener.stop()
		_delivery_uri = ""
		_publish(classify(String(start.get("error", ""))))
		return
	_pending_state = start["state"]
	_waiting_since = int(_now.call())
	_publish(WAITING)


## Ends a signed-in credential the server refused or lapsed: clears it and asks
## the player to sign in again. Returns false when nothing was signed in.
func end_credential() -> bool:
	if not is_signed_in():
		return false
	tokens.clear()
	_publish(SESSION_EXPIRED if _configured else {"state": State.EXPIRED, "message": SESSION_EXPIRED["message"], "action": ""})
	credential_ended.emit()
	return true


func _process(_delta: float) -> void:
	_listener.poll()
	if _waiting_since >= 0 and int(_now.call()) - _waiting_since > WAIT_TIMEOUT_MSEC:
		_abandon()
		_publish(LINK_EXPIRED)
	elif is_signed_in() and tokens.is_expired(int(_now.call())):
		end_credential()


func _exit_tree() -> void:
	_listener.stop()


## The finite outcome for a HaivenHandoff error code. The code is never shown.
static func classify(error: String) -> Dictionary:
	if error == "callback_error:access_denied":
		return CANCELLED
	if error in ["expired_transaction", "unknown_or_consumed_state", "exchange_http_400", "exchange_http_401"]:
		return LINK_EXPIRED
	if error == "exchange_http_503":
		return UNAVAILABLE
	if error in ["invalid_entry_url", "invalid_exchange_url", "invalid_redirect_url", "missing_integration_id"]:
		return NOT_CONFIGURED
	return FAILED


func _on_callback(callback_url: String) -> void:
	_waiting_since = -1
	_pending_state = ""
	_completing = true
	# The browser hit the ephemeral loopback. The exchange's redirect_uri is the
	# registered frontend callback, which is what the handoff checks.
	var result: Dictionary = await _handoff.complete(_registered_callback(callback_url))
	_completing = false
	if not result.get("ok", false):
		_publish(classify(String(result.get("error", ""))))
		return
	if tokens.is_expired(int(_now.call())):
		tokens.clear()
		_publish(SESSION_EXPIRED)
		return
	_publish(SIGNED_IN)
	signed_in.emit()


func _abandon() -> void:
	_listener.stop()
	_delivery_uri = ""
	if _pending_state != "":
		_handoff.cancel(_pending_state)
	_pending_state = ""
	_waiting_since = -1


## Adds delivery_uri for the page. It is not an API parameter.
func _open_authorization(url: String) -> int:
	var launched := _with_delivery(url, _delivery_uri)
	if _open_browser.is_valid():
		var result: Variant = _open_browser.call(launched)
		return int(result) if result is int else OK
	return OS.shell_open(launched)


static func _usable_redirect(redirect_url: String) -> bool:
	if redirect_url == "" or redirect_url.contains("#") or redirect_url.contains(" "):
		return false
	return redirect_url.begins_with("https://") or redirect_url.begins_with("http://")


static func _with_delivery(url: String, delivery_uri: String) -> String:
	if delivery_uri == "":
		return url
	var encoded := "delivery_uri=" + delivery_uri.uri_encode()
	var hash := url.find("#")
	var before := url if hash < 0 else url.substr(0, hash)
	var fragment := "" if hash < 0 else url.substr(hash)
	if before.contains("?"):
		return before + "&" + encoded + fragment
	return before + "?" + encoded + fragment


## Query from the loopback request, on the registered redirect.
func _registered_callback(delivered_url: String) -> String:
	var query := ""
	var at := delivered_url.find("?")
	if at >= 0:
		query = delivered_url.substr(at)
	if _redirect_url.contains("?"):
		return _redirect_url if query == "" else _redirect_url + "&" + query.substr(1)
	return _redirect_url + query


func _publish(presentation: Dictionary) -> void:
	current = presentation
	changed.emit(presentation)
