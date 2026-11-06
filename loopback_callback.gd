# Receives the one-use code on an ephemeral loopback (RFC 8252 section 7.3).
# The registered redirect is the frontend callback, which this process does not
# bind. The page is given the bound address as delivery_uri and sends the
# browser there. This answers one GET on /haiven/callback with a static page
# that echoes nothing from the request, then stops. Any other path (a favicon
# probe, say) gets a 404 and the wait goes on. Nothing about a request is
# logged. The Godot addon has no listener of its own, so this one lives in the
# demo.
#
# TCPServer, like WebSocketPeer, only moves when polled: HaivenDemo calls poll()
# from _process.
extends RefCounted

## The browser reached the delivery path. The URL is this listener's origin plus
## the request target, unparsed. Sign-in maps it onto the registered frontend
## callback before HaivenHandoff.complete checks that redirect and state.
signal received(callback_url: String)

const MAX_REQUEST_BYTES := 8192
const MAX_PEERS := 8
const REQUEST_READ_TIMEOUT_MSEC := 10_000
const DELIVERY_PATH := "/haiven/callback"
## Inside the Linux ephemeral range, so a port-0 bind can return it. The demo
## does not register this port and must not listen on it.
const REFUSED_PORT := 47616
const COMPLETED_PAGE := (
	"<!doctype html><html><head><meta charset=\"utf-8\"><title>Haiven</title></head>"
	+ "<body style=\"font-family:sans-serif;margin:3em\"><h1>Haiven</h1>"
	+ "<p>Sign-in finished. You can close this tab and return to the game.</p></body></html>"
)

var _server: TCPServer
var _origin := ""
var _path := ""
var _peers: Array[Dictionary] = []  # {peer: StreamPeerTCP, data: PackedByteArray, since: int}


## The parts of `redirect_url` this listener serves, as `{address, port, origin,
## path}`, or {} when it is not an absolute http URL on 127.0.0.1 or [::1] with
## an explicit port and no fragment. A host name such as localhost is refused: a
## browser may resolve it to the other address family than the one bound.
static func parse_redirect(redirect_url: String) -> Dictionary:
	if not redirect_url.begins_with("http://") or redirect_url.contains("#"):
		return {}
	var rest := redirect_url.substr(7)
	var authority_end := rest.length()
	for separator: String in ["/", "?"]:
		var at := rest.find(separator)
		if at >= 0 and at < authority_end:
			authority_end = at
	var authority := rest.substr(0, authority_end)
	var address := ""
	var port := ""
	if authority.begins_with("[::1]:"):
		address = "::1"
		port = authority.substr(6)
	elif authority.begins_with("127.0.0.1:"):
		address = "127.0.0.1"
		port = authority.substr(10)
	if address == "" or not port.is_valid_int() or int(port) <= 0 or int(port) > 65535:
		return {}
	var path := rest.substr(authority_end).get_slice("?", 0)
	return {
		"address": address,
		"port": int(port),
		"origin": "http://" + authority,
		"path": path if path != "" else "/",
	}


## Binds the redirect's loopback address and port. Call it before opening the
## browser, so a busy port fails the sign-in instead of stranding it. Returns
## ERR_INVALID_PARAMETER for a redirect this cannot serve, or the bind error.
## Sign-in uses [method start_ephemeral] instead of binding the registered redirect.
func start(redirect_url: String) -> Error:
	stop()
	var redirect := parse_redirect(redirect_url)
	if redirect.is_empty():
		return ERR_INVALID_PARAMETER
	if int(redirect["port"]) == REFUSED_PORT:
		return ERR_CANT_CREATE
	var server := TCPServer.new()
	var error := server.listen(redirect["port"], redirect["address"])
	if error != OK:
		return error
	_server = server
	_origin = redirect["origin"]
	_path = redirect["path"]
	return OK


## Binds 127.0.0.1 on a port the OS chooses and returns
## `http://127.0.0.1:<port>/haiven/callback`, or "" when the bind fails.
## [constant REFUSED_PORT] is closed and tried once more. The registered
## redirect is not this address.
func start_ephemeral() -> String:
	stop()
	for _attempt in 2:
		var server := TCPServer.new()
		var error := server.listen(0, "127.0.0.1")
		if error != OK:
			return ""
		var port := server.get_local_port()
		if port == REFUSED_PORT:
			server.stop()
			continue
		if port <= 0 or port > 65535:
			server.stop()
			return ""
		_server = server
		_origin = "http://127.0.0.1:%d" % port
		_path = DELIVERY_PATH
		return _origin + DELIVERY_PATH
	return ""


func is_listening() -> bool:
	return _server != null and _server.is_listening()


func stop() -> void:
	if _server != null:
		_server.stop()
		_server = null
	for entry: Dictionary in _peers:
		(entry["peer"] as StreamPeerTCP).disconnect_from_host()
	_peers.clear()


## Accepts and serves pending connections; emits [signal received] at most once.
func poll() -> void:
	if not is_listening():
		return
	while _server.is_connection_available() and _peers.size() < MAX_PEERS:
		_peers.append({"peer": _server.take_connection(), "data": PackedByteArray(), "since": Time.get_ticks_msec()})
	for entry: Dictionary in _peers.duplicate():
		var callback := _serve(entry)
		if callback != "":
			stop()
			received.emit(callback)
			return


# Reads one request from a peer. Returns the callback URL once the peer asked
# for the redirect path, otherwise "" (still reading, or answered and dropped).
func _serve(entry: Dictionary) -> String:
	var peer: StreamPeerTCP = entry["peer"]
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_drop(entry)
		return ""
	var available := peer.get_available_bytes()
	if available > 0:
		var chunk: Array = peer.get_partial_data(mini(available, MAX_REQUEST_BYTES))
		if chunk[0] == OK:
			entry["data"].append_array(chunk[1])
	var text: String = (entry["data"] as PackedByteArray).get_string_from_ascii()
	var complete := text.contains("\r\n\r\n")
	if not complete and entry["data"].size() < MAX_REQUEST_BYTES:
		if Time.get_ticks_msec() - int(entry["since"]) > REQUEST_READ_TIMEOUT_MSEC:
			_drop(entry)
		return ""
	var target := _request_target(text)
	if target == "":
		_respond(entry, "400 Bad Request", "text/plain; charset=utf-8", "Bad request")
		return ""
	if target.get_slice("?", 0) != _path:
		_respond(entry, "404 Not Found", "text/plain; charset=utf-8", "Not found")
		return ""
	_respond(entry, "200 OK", "text/html; charset=utf-8", COMPLETED_PAGE)
	return _origin + target


# The target of a `GET <target> HTTP/1.x` request line, or "" for anything else.
static func _request_target(text: String) -> String:
	var line_end := text.find("\r\n")
	if line_end < 0:
		return ""
	var parts := text.substr(0, line_end).split(" ")
	if parts.size() != 3 or parts[0] != "GET" or not parts[2].begins_with("HTTP/1."):
		return ""
	return parts[1] if parts[1].begins_with("/") else ""


func _respond(entry: Dictionary, status: String, content_type: String, body: String) -> void:
	var content := body.to_utf8_buffer()
	var head := (
		"HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n" % [status, content_type, content.size()]
		+ "Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n"
	)
	var peer: StreamPeerTCP = entry["peer"]
	peer.put_data(head.to_ascii_buffer() + content)
	_drop(entry)


func _drop(entry: Dictionary) -> void:
	(entry["peer"] as StreamPeerTCP).disconnect_from_host()
	_peers.erase(entry)
