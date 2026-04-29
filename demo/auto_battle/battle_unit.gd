extends Node2D

signal died(unit)

var entity_id: int
var camp: String
var cell: Vector2i
var stats
var buffs
var _hp_stat_id: int = -1
var _speed_stat_id: int = -1
var _max_hp_stat_id: int = -1
var _is_dead_flag: bool = false

var _home_pos: Vector2
var _body: ColorRect
var _icon: TextureRect
var _hp_bar: ProgressBar
var _name_label: Label
var _dmg_label: Label
var _camp_indicator: ColorRect
var _animating: bool = false

func setup(eid: int, c: String, grid_cell: Vector2i, dataset, enums_runtime, world_pos: Vector2) -> void:
	entity_id = eid
	camp = c
	cell = grid_cell
	_home_pos = world_pos
	position = world_pos

	stats = OmniStatsComponent.new(eid, dataset)
	buffs = OmniBuffCore.new(dataset, enums_runtime)
	_hp_stat_id = int(dataset.stat_id("HP"))
	_max_hp_stat_id = int(dataset.stat_id("MAX_HP"))
	_speed_stat_id = int(dataset.stat_id("SPEED"))
	_build_visuals()

func get_speed() -> float:
	if stats == null or _speed_stat_id < 0:
		return 0.0
	return float(stats.get_final(_speed_stat_id))

func is_dead() -> bool:
	if stats == null or _hp_stat_id < 0:
		return _is_dead_flag
	return float(stats.get_final(_hp_stat_id)) <= 0.0

func _build_visuals() -> void:
	_camp_indicator = ColorRect.new()
	_camp_indicator.size = Vector2(36, 36)
	_camp_indicator.position = Vector2(-18, -18)
	if camp == "ally":
		_camp_indicator.color = Color(0.15, 0.45, 0.85, 0.6)
	else:
		_camp_indicator.color = Color(0.85, 0.2, 0.15, 0.6)
	add_child(_camp_indicator)

	_body = ColorRect.new()
	_body.size = Vector2(32, 32)
	_body.position = Vector2(-16, -16)
	_body.color = Color(0.9, 0.9, 0.9)
	add_child(_body)

	_icon = TextureRect.new()
	_icon.texture = load("res://icon.svg")
	_icon.size = Vector2(24, 24)
	_icon.position = Vector2(-12, -12)
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_icon)

	_hp_bar = ProgressBar.new()
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 100.0
	_hp_bar.value = 100.0
	_hp_bar.custom_minimum_size = Vector2(40, 6)
	_hp_bar.position = Vector2(-20, -30)
	_hp_bar.show_percentage = false
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.15, 0.15, 0.15)
	_hp_bar.add_theme_stylebox_override("background", style_bg)
	var style_fill = StyleBoxFlat.new()
	if camp == "ally":
		style_fill.bg_color = Color(0.2, 0.8, 0.3)
	else:
		style_fill.bg_color = Color(0.85, 0.2, 0.15)
	_hp_bar.add_theme_stylebox_override("fill", style_fill)
	add_child(_hp_bar)

	_name_label = Label.new()
	if camp == "ally":
		_name_label.text = "Ally-%d" % entity_id
	else:
		_name_label.text = "Enemy-%d" % entity_id
	_name_label.position = Vector2(-20, -46)
	_name_label.add_theme_font_size_override("font_size", 10)
	add_child(_name_label)

	_dmg_label = Label.new()
	_dmg_label.text = ""
	_dmg_label.position = Vector2(-10, -60)
	_dmg_label.add_theme_font_size_override("font_size", 16)
	_dmg_label.visible = false
	add_child(_dmg_label)

func refresh_hp_bar() -> void:
	if stats == null or _hp_stat_id < 0 or _hp_bar == null:
		return
	var cur_hp = float(stats.get_final(_hp_stat_id))
	var max_hp = float(stats.get_final(_max_hp_stat_id)) if _max_hp_stat_id >= 0 else cur_hp
	if max_hp <= 0.0:
		max_hp = 1.0
	_hp_bar.max_value = max_hp
	_hp_bar.value = max(0.0, cur_hp)
	if cur_hp <= 0.0 and not _is_dead_flag:
		_is_dead_flag = true
		_body.color = Color(0.3, 0.3, 0.3)
		_body.modulate.a = 0.4
		_icon.modulate.a = 0.4
		_camp_indicator.modulate.a = 0.2
		_hp_bar.visible = false
		_name_label.text += " [X]"
		died.emit(self)

func show_damage_number(dmg: float) -> void:
	var dmg_int = int(ceil(abs(dmg)))
	if dmg_int <= 0:
		return
	_dmg_label.text = "-%d" % dmg_int
	_dmg_label.visible = true
	_dmg_label.modulate = Color(1.0, 0.15, 0.15)
	_dmg_label.position = Vector2(-10, -60)
	var tween = create_tween()
	tween.tween_property(_dmg_label, "position:y", -95.0, 0.7).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_dmg_label, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tween.tween_callback(func(): _dmg_label.visible = false)

func show_heal_number(amount: float) -> void:
	var val = int(ceil(amount))
	if val <= 0:
		return
	_dmg_label.text = "+%d" % val
	_dmg_label.visible = true
	_dmg_label.modulate = Color(0.1, 1.0, 0.3)
	_dmg_label.position = Vector2(-10, -60)
	var tween = create_tween()
	tween.tween_property(_dmg_label, "position:y", -95.0, 0.7).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_dmg_label, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tween.tween_callback(func(): _dmg_label.visible = false)

func flash_hit() -> void:
	_body.color = Color(1.0, 1.0, 1.0)
	var tween = create_tween()
	tween.tween_property(_body, "color", Color(0.9, 0.9, 0.9), 0.15)

func play_attack_animation(target_unit) -> void:
	if _animating or target_unit == null:
		return
	_animating = true
	var target_pos = target_unit.position
	var direction = (target_pos - position).normalized()
	var lunge_pos = target_pos - direction * 28.0

	var tween = create_tween()
	tween.tween_property(self, "position", lunge_pos, 0.2).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		target_unit.flash_hit()
	)
	tween.tween_property(self, "position", _home_pos, 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): _animating = false)

func set_home_pos(pos: Vector2) -> void:
	_home_pos = pos
