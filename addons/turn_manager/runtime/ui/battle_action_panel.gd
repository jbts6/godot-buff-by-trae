extends Control
class_name BattleActionPanel

signal action_selected(kind: String, id: String)
signal cancel_requested()

@onready var tab: TabContainer = %Tab
@onready var skill_list: ItemList = %SkillList
@onready var item_list: ItemList = %ItemList
@onready var btn_cancel: Button = %BtnCancel


func _ready() -> void:
	btn_cancel.pressed.connect(func():
		cancel_requested.emit()
	)
	skill_list.item_selected.connect(func(idx: int):
		var sid = String(skill_list.get_item_metadata(idx))
		action_selected.emit("skill", sid)
	)
	item_list.item_selected.connect(func(idx: int):
		var iid = String(item_list.get_item_metadata(idx))
		action_selected.emit("item", iid)
	)


func set_skills(skill_ids: Array) -> void:
	skill_list.clear()
	for sid in skill_ids:
		var s = String(sid)
		skill_list.add_item(s)
		skill_list.set_item_metadata(skill_list.item_count - 1, s)


func set_items(items: Array) -> void:
	# items: Array[Dictionary] = [{id,name,count}]
	item_list.clear()
	for it_any in items:
		if typeof(it_any) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_any
		var id = String(it.get("id", ""))
		var name = String(it.get("name", id))
		var count = int(it.get("count", 0))
		item_list.add_item("%s x%d" % [name, count])
		item_list.set_item_metadata(item_list.item_count - 1, id)


func clear_selection() -> void:
	skill_list.deselect_all()
	item_list.deselect_all()

