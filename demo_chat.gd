# The demo's chat on one channel: the addon's HaivenChat turned into log lines.
#
# HaivenChat tracks what the player sent, by client message id, through its
# moderation outcome and across reconnects. This only decides how each state
# reads and shows other players' messages on the configured channel.
extends RefCounted

const Chat := preload("res://addons/haiven/haiven_chat.gd")

## A line was added or replaced; key is a client message id, or "" for a note.
signal line_changed(key: String, text: String)

var channel_id: String
var chat: RefCounted = Chat.new()


func _init(channel: String) -> void:
	channel_id = channel
	chat.outgoing_changed.connect(_on_outgoing_changed)
	chat.message_received.connect(_on_message_received)


static func describe(message: RefCounted) -> String:
	match message.state:
		Chat.OutgoingState.SENDING:
			return "you (sending): %s" % message.content
		Chat.OutgoingState.UNCONFIRMED:
			return "you (not confirmed yet, resent on reconnect): %s" % message.content
		Chat.OutgoingState.ACCEPTED:
			return "you: %s" % message.content
		Chat.OutgoingState.HELD:
			return "you (held for review): %s" % message.content
		Chat.OutgoingState.REMOVED:
			return "you (not shown: %s): %s" % [message.moderation_state, message.content]
		_:
			return "you (refused: %s): %s" % [message.error, message.content]


## Uses this session; call again with each new session after a reconnect.
func attach(session: RefCounted) -> void:
	chat.attach(session)


func send(content: String) -> void:
	chat.send(channel_id, content)


## Drops every tracked send so the next account's session cannot resend them.
func forget_outbox() -> void:
	for message in chat.outbox():
		chat.forget(message)


func _on_outgoing_changed(message: RefCounted) -> void:
	if message.channel_id == channel_id:
		line_changed.emit(message.client_message_id, describe(message))


func _on_message_received(message: Dictionary) -> void:
	if message.get("channelId", "") != channel_id or str(message.get("content", "")) == "":
		return
	if chat.find(str(message.get("clientMessageId", ""))) != null:
		return  # Our own message, already shown by its client id.
	var author: Dictionary = message.get("author", {}) if message.get("author") is Dictionary else {}
	var author_name := str(author.get("displayName", ""))
	if author_name == "":
		author_name = str(author.get("username", "someone"))
	line_changed.emit("", "%s: %s" % [author_name, message["content"]])
