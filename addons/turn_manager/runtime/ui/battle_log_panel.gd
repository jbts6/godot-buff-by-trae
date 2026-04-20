extends Control
class_name BattleLogPanel

const Log = preload("res://addons/log/log.gd")

@onready var log_box: RichTextLabel = %LogBox
@onready var detail_select: OptionButton = %DetailSelect
@onready var btn_clear: Button = %BtnClear

var _narrator = null
var _entries: Array[Dictionary] = []


func _ready() -> void:
	# 默认：简洁
	detail_select.clear()
	detail_select.add_item("简洁", 0)
	detail_select.add_item("详细", 1)
	detail_select.select(0)
	detail_select.item_selected.connect(func(_idx: int):
		_apply_detail_level()
	)
	btn_clear.pressed.connect(clear_log)


func set_narrator(narrator) -> void:
	_narrator = narrator
	_apply_detail_level()


func append_line(bbcode_line: String, meta: Dictionary = {}) -> void:
	# 记录条目，支持“切换简洁/详细后重渲染”
	var entry: Dictionary = {
		"bbcode": bbcode_line,
		"text_concise": String(meta.get("text_concise", "")),
		"text_verbose": String(meta.get("text_verbose", "")),
		"bb_concise": String(meta.get("bb_concise", "")),
		"bb_verbose": String(meta.get("bb_verbose", "")),
		"meta": meta.duplicate(true),
	}
	_entries.append(entry)
	_append_entry(entry)


func clear_log() -> void:
	log_box.text = ""
	_entries.clear()


func _apply_detail_level() -> void:
	var level = int(detail_select.get_selected_id())
	if _narrator != null and _narrator.has_method("set_detail_level"):
		_narrator.call("set_detail_level", level)
	_rerender()


func _rerender() -> void:
	log_box.text = ""
	for e in _entries:
		_append_entry(e, true)


func _append_entry(entry: Dictionary, _is_rerender: bool = false) -> void:
	var level = int(detail_select.get_selected_id())
	var concise = String(entry.get("text_concise", ""))
	var verbose = String(entry.get("text_verbose", ""))
	var bb_concise = String(entry.get("bb_concise", ""))
	var bb_verbose = String(entry.get("bb_verbose", ""))
	var bbcode = ""

	# 优先使用“原始文本”再交给 Log.to_printable 生成 BBCode，保证切换后可重渲染。
	if level == 1 and bb_verbose != "":
		bbcode = bb_verbose
	elif level == 0 and bb_concise != "":
		bbcode = bb_concise
	else:
		var chosen_text = verbose if level == 1 else concise
		if chosen_text != "":
			bbcode = Log.to_printable([chosen_text], {"pretty": true})

	if bbcode == "":
		return
	log_box.append_text(bbcode + "\n")
	log_box.scroll_to_line(maxi(0, log_box.get_line_count() - 1))
