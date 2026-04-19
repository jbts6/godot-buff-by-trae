extends Control
class_name BattleLogPanel

@onready var log_box: RichTextLabel = %LogBox
@onready var detail_select: OptionButton = %DetailSelect
@onready var btn_clear: Button = %BtnClear

var _narrator = null


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


func append_line(bbcode_line: String) -> void:
	if bbcode_line == "":
		return
	log_box.append_text(bbcode_line + "\n")
	log_box.scroll_to_line(maxi(0, log_box.get_line_count() - 1))


func clear_log() -> void:
	log_box.text = ""


func _apply_detail_level() -> void:
	if _narrator == null:
		return
	var level = int(detail_select.get_selected_id())
	if _narrator.has_method("set_detail_level"):
		_narrator.call("set_detail_level", level)
