# The envelope, as GDScript sees it.
#
# The two outbound shapes are told apart by the PRESENCE of `success`, not its
# value (F10). `protocol_test.gd` measured what that costs here and found the
# trap dynamic typing was predicted to remove: `frame.get("success")` answers
# `null` for an absent key and `null` is falsy, so the natural spelling collapses
# absent and present-and-false — the same collapse a non-nullable `bool` causes
# in C#, in the language that was supposed to be immune.
#
# So classification lives in one place and asks `has()`. A binding that spreads
# this across call sites is one call site away from the collapse, and the trap is
# invisible at the site where it happens because it reads as ordinary GDScript.
class_name HaivenProtocol
extends RefCounted

const AUTH := "auth"
const AUTH_SUCCESS := "auth.success"
const AUTH_EXPIRED := "auth.expired"
const AUTH_FAILURE := "auth.failure"
const AUTH_EXPIRED_DROPPED := "auth.expired.dropped"

## An SDK-local error code: raised by this SDK, never sent by the server, and
## finite. It is not part of the server's error vocabulary.
const INTEGER_PRECISION_EXCEEDED := "integer_precision_exceeded"

# 2^53 - 1. `JSON.parse_string` reads EVERY number as a float, integers
# included -- only Godot .NET's System.Text.Json keeps a 64-bit integer -- so an
# integer literal beyond this arrives as a different integer with no error:
# 2^53 + 1 decodes as 2^53. 2^53 itself is refused too, because it is what
# 2^53 + 1 rounds to, so a decoded 2^53 cannot be trusted to be what was sent.
const _MAX_SAFE_DIGITS := "9007199254740991"

static var _digit_run: RegEx


## Whether a received frame answers something the client sent.
##
## `has()` and only `has()`. See the note above before changing this to
## anything that reads the value.
static func is_reply(frame: Dictionary) -> bool:
	return frame.has("success")


## Whether a reply reports success. Meaningless for an event; ask [method is_reply] first.
static func succeeded(frame: Dictionary) -> bool:
	return frame.get("success") == true


## Parses one text frame, or returns an empty Dictionary if it is not an object.
##
## A non-object is dropped rather than raised. The server does not send one, so
## a binding that raised here would convert a hypothetical into a crash in a
## shipped game, and an empty Dictionary classifies as an event with no type —
## which every caller already has to handle.
static func parse(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


## Builds a client frame. `payload` is omitted when null, matching the wire.
static func frame(type: String, request_id: String, payload: Variant = null) -> Dictionary:
	var built := {"type": type, "requestId": request_id}
	if payload != null:
		built["payload"] = payload
	return built


## The first integer literal in a JSON text whose magnitude exceeds 2^53 - 1, or
## an empty String.
##
## It reads the raw text, because by the time `JSON.parse_string` has returned
## the value is already rounded. Digits inside strings are skipped, escapes
## included; a number with a fraction or an exponent is a float on the wire and
## is not checked. Expects text that parses as JSON. A REST transport calls this
## on a body before decoding it and fails with [constant INTEGER_PRECISION_EXCEEDED].
static func find_unsafe_integer(text: String) -> String:
	# Fast path: no run of 16 digits, no literal large enough to matter.
	if _digit_run == null:
		_digit_run = RegEx.create_from_string("[0-9]{%d}" % _MAX_SAFE_DIGITS.length())
	if _digit_run.search(text) == null:
		return ""

	var length := text.length()
	var index := 0
	while index < length:
		var code := text.unicode_at(index)
		if code == 0x22: # "
			# Skip a string, escapes included: digits inside one are not numbers.
			index += 1
			while index < length:
				var inner := text.unicode_at(index)
				if inner == 0x5c: # \
					index += 2
				elif inner == 0x22:
					break
				else:
					index += 1
			index += 1
		elif code == 0x2d or _is_digit(code): # - or a digit
			var start := index
			if code == 0x2d:
				index += 1
			var digits_start := index
			while index < length and _is_digit(text.unicode_at(index)):
				index += 1
			var digits_end := index
			var integer := true
			while index < length:
				var next := text.unicode_at(index)
				if next == 0x2e or next == 0x65 or next == 0x45: # . e E
					integer = false
				elif not (_is_digit(next) or next == 0x2b or next == 0x2d): # + -
					break
				index += 1
			if integer and _exceeds_safe_integer(text.substr(digits_start, digits_end - digits_start)):
				return text.substr(start, digits_end - start)
		else:
			index += 1
	return ""


static func _is_digit(code: int) -> bool:
	return code >= 0x30 and code <= 0x39


# Whether an unsigned run of decimal digits exceeds 2^53 - 1.
static func _exceeds_safe_integer(digits: String) -> bool:
	if digits.length() != _MAX_SAFE_DIGITS.length():
		return digits.length() > _MAX_SAFE_DIGITS.length()
	return digits > _MAX_SAFE_DIGITS
