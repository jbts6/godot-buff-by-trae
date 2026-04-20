extends CanvasLayer
class_name BattleHUD

const TurnCommand = preload("res://addons/turn_manager/runtime/turn_command.gd")

signal command_ready(cmd: TurnCommand)

@onready var action_panel: BattleActionPanel = %ActionPanel
@onready var log_panel: BattleLogPanel = %BattleLogPanel
@onready var overlay_host: Control = %OverlayHost

var _overlay: BattleTargetingOverlay

var _grid = null
var _skill_db = null
var _item_db: Dictionary = {}
var _inventory = null

var _actor: Node = null
var _selected_kind: String = ""
var _selected_id: String = ""


func _ready() -> void:
	_overlay = BattleTargetingOverlay.new()
	overlay_host.add_child(_overlay)
	_overlay.visible = false
	_overlay.cell_clicked.connect(_on_cell_clicked)

	action_panel.action_selected.connect(_on_action_selected)
	action_panel.cancel_requested.connect(_on_cancel)


func bind_runtime(grid, skill_db, inventory, item_db: Dictionary, narrator: BattleNarrator = null) -> void:
	_grid = grid
	_skill_db = skill_db
	_inventory = inventory
	_item_db = item_db
	if narrator != null:
		log_panel.set_narrator(narrator)
		narrator.line_emitted.connect(func(bb: String, meta: Dictionary):
			log_panel.append_line(bb, meta)
		)


func open_for_actor(actor: Node, skill_ids: Array, items: Array) -> void:
	_actor = actor
	_selected_kind = ""
	_selected_id = ""
	action_panel.set_skills(skill_ids)
	action_panel.set_items(items)
	action_panel.clear_selection()
	_overlay.clear_valid_cells()
	_overlay.visible = false
	visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_cancel()


func _on_action_selected(kind: String, id: String) -> void:
	_selected_kind = kind
	_selected_id = id
	# 进入选目标模式：计算可选格子并高亮
	var cells = _compute_valid_cells(kind, id)
	_overlay.set_valid_cells(cells)
	_overlay.visible = true


func _on_cancel() -> void:
	_selected_kind = ""
	_selected_id = ""
	action_panel.clear_selection()
	_overlay.clear_valid_cells()
	_overlay.visible = false


func _on_cell_clicked(cell: Vector2i) -> void:
	if _actor == null:
		return
	if _selected_kind == "" or _selected_id == "":
		return
	var cmd: TurnCommand
	if _selected_kind == "item":
		cmd = TurnCommand.new_item(_selected_id, cell)
	else:
		cmd = TurnCommand.new_skill(_selected_id, cell)
	command_ready.emit(cmd)
	_on_cancel()


func _compute_valid_cells(kind: String, id: String) -> Array:
	# 最小实现：只支持 single_cell；camp 规则：
	# - item：读取 item_db[id].targeting.camp
	# - skill：若 skill.targeting 是 Dictionary 且含 camp，则用；否则默认 enemy
	var camp = "enemy"
	if kind == "item":
		var it: Dictionary = _item_db.get(id, {})
		var t: Dictionary = it.get("targeting", {})
		camp = String(t.get("camp", "ally"))
	else:
		if _skill_db != null and _skill_db.has_method("get_skill"):
			var r: Dictionary = _skill_db.call("get_skill", id, true)
			if bool(r.get("ok", false)):
				var sk: Dictionary = r.get("skill", {})
				var tgt_any: Variant = sk.get("targeting", null)
				if typeof(tgt_any) == TYPE_DICTIONARY:
					camp = String((tgt_any as Dictionary).get("camp", camp))

	var cells: Array = []
	if _grid == null or not ("_units" in _grid):
		return cells
	var units_any: Variant = _grid.get("_units")
	if typeof(units_any) != TYPE_ARRAY:
		return cells

	for u in units_any:
		if u == null:
			continue
		if String(u.get("camp")) != camp:
			continue
		if u.has_method("is_dead") and bool(u.call("is_dead")):
			continue
		cells.append(Vector2i(u.get("cell")))
	return cells

