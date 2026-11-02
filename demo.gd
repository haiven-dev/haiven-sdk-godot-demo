# Behavior for the editor-authored demo scene. Layout, presentation, and the
# semantic Theme hooks live in demo.tscn and demo_theme.tres; this script only
# binds those controls to the HaivenDemo autoload.
extends Control

@onready var _log: RichTextLabel = $Row/Chat/Log
@onready var _input: LineEdit = $Row/Chat/Input
@onready var _inventory: ItemList = $Row/Side/Inventory
@onready var _motd: PanelContainer = $Row/Side/HaivenMotdPanel
var _lines: Array[String] = []
var _keyed: Dictionary = {}  # client message id -> index in _lines


func _ready() -> void:
	_input.text_submitted.connect(_on_submitted)
	var demo := _demo()
	if demo != null:
		demo.line_changed.connect(show_line)
		demo.inventory.changed.connect(_on_inventory_changed)
		if demo.identity != null:
			_motd.bind(demo.identity)
	_motd.action_requested.connect(_on_motd_action_requested)
	_input.grab_focus()


func _demo() -> Node:
	return get_node_or_null("/root/HaivenDemo")


## Shows a line; a keyed line replaces the earlier line for the same key.
func show_line(key: String, text: String) -> void:
	if key != "" and _keyed.has(key):
		_lines[_keyed[key]] = text
	else:
		if key != "":
			_keyed[key] = _lines.size()
		_lines.append(text)
	_log.text = "\n".join(_lines)


func line_count() -> int:
	return _lines.size()


func _on_submitted(text: String) -> void:
	var demo := _demo()
	if demo != null:
		demo.send_chat(text)
	_input.clear()


func _on_inventory_changed() -> void:
	show_inventory(_demo().inventory.codes())


func show_inventory(codes: PackedStringArray) -> void:
	_inventory.clear()
	for code: String in codes:
		_inventory.add_item(code)


func _on_motd_action_requested(url: String) -> void:
	# A game owns platform navigation policy; the SDK only supplies a safe URL.
	show_line("", "MOTD action requested: %s" % url)
