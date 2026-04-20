extends Control
class_name BattleTargetingOverlay

signal cell_clicked(cell: Vector2i)

var _w: int = 3
var _h: int = 3
var _valid: Dictionary = {} # "x,y" -> true

var _grid: GridContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_grid = GridContainer.new()
	_grid.columns = _w
	_grid.anchors_preset = Control.PRESET_FULL_RECT
	_grid.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_grid.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_grid)

	for y in range(_h):
		for x in range(_w):
			var b := Button.new()
			b.text = "%d,%d" % [x, y]
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.size_flags_vertical = Control.SIZE_EXPAND_FILL
			var cell = Vector2i(x, y)
			b.pressed.connect(func():
				if _is_valid(cell):
					cell_clicked.emit(cell)
			)
			_grid.add_child(b)

	_refresh()


func set_board_size(w: int, h: int) -> void:
	# 最小实现：demo 固定 3x3；后续可扩展为重建按钮网格
	_w = w
	_h = h


func set_valid_cells(cells: Array) -> void:
	_valid.clear()
	for c in cells:
		var v = Vector2i(c)
		_valid["%d,%d" % [v.x, v.y]] = true
	_refresh()


func clear_valid_cells() -> void:
	_valid.clear()
	_refresh()


func _is_valid(cell: Vector2i) -> bool:
	return _valid.has("%d,%d" % [cell.x, cell.y])


func _refresh() -> void:
	if _grid == null:
		return
	for i in range(_grid.get_child_count()):
		var b = _grid.get_child(i)
		if b == null:
			continue
		var x = i % _w
		var y = i / _w
		var cell = Vector2i(x, y)
		var ok = _is_valid(cell)
		(b as Button).disabled = not ok
		(b as Button).modulate = Color(1, 1, 1, 1) if ok else Color(1, 1, 1, 0.25)

