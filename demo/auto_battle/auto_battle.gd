extends Node2D

const BattleUnit = preload("res://demo/auto_battle/battle_unit.gd")

var ds = null
var enums_rt = null
var _units: Array = []
var _battle_active: bool = false
var _battle_over: bool = false
var _turn_index: int = 0

var _btn_start: Button
var _btn_reset: Button
var _status_label: Label
var _battle_log: RichTextLabel
var _arena_bg: ColorRect
var _log_lines: Array = []

func _ready() -> void:
	_load_dataset()
	_build_ui()
	_spawn_units()

func _load_dataset() -> void:
	var result = OmniManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", false)
	enums_rt = OmniEnumsRuntime.from_enums_json(result.enums)
	ds = OmniDatasetCompiler.compile(result.manifest, enums_rt, result.sources)

func _build_ui() -> void:
	_arena_bg = ColorRect.new()
	_arena_bg.color = Color(0.12, 0.12, 0.18)
	_arena_bg.size = Vector2(960, 540)
	_arena_bg.position = Vector2(0, 0)
	add_child(_arena_bg)

	var border = ColorRect.new()
	border.color = Color(0.4, 0.4, 0.5)
	border.size = Vector2(964, 544)
	border.position = Vector2(-2, -2)
	border.z_index = -1
	add_child(border)

	var canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var top_bar = HBoxContainer.new()
	top_bar.anchors_preset = Control.PRESET_TOP_WIDE
	top_bar.offset_top = 8
	top_bar.offset_left = 12
	top_bar.offset_right = -12
	canvas.add_child(top_bar)

	_btn_start = Button.new()
	_btn_start.text = "Start Battle"
	_btn_start.custom_minimum_size = Vector2(120, 36)
	_btn_start.pressed.connect(_on_start_pressed)
	top_bar.add_child(_btn_start)

	_btn_reset = Button.new()
	_btn_reset.text = "Reset"
	_btn_reset.custom_minimum_size = Vector2(80, 36)
	_btn_reset.pressed.connect(_on_reset_pressed)
	top_bar.add_child(_btn_reset)

	_status_label = Label.new()
	_status_label.text = "Ready — Press Start"
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.custom_minimum_size = Vector2(300, 36)
	top_bar.add_child(_status_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	var team_label = Label.new()
	team_label.text = "[Blue=Ally  Red=Enemy]"
	team_label.add_theme_font_size_override("font_size", 12)
	top_bar.add_child(team_label)

	var bottom_bar = VBoxContainer.new()
	bottom_bar.anchors_preset = Control.PRESET_BOTTOM_WIDE
	bottom_bar.offset_bottom = -8
	bottom_bar.offset_left = 12
	bottom_bar.offset_right = -12
	bottom_bar.offset_top = -140
	canvas.add_child(bottom_bar)

	var log_label = Label.new()
	log_label.text = "Battle Log:"
	log_label.add_theme_font_size_override("font_size", 12)
	bottom_bar.add_child(log_label)

	_battle_log = RichTextLabel.new()
	_battle_log.bbcode_enabled = true
	_battle_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_battle_log.add_theme_font_size_override("normal_font_size", 12)
	bottom_bar.add_child(_battle_log)

func _spawn_units() -> void:
	_units.clear()
	var ally_positions = [Vector2(150, 200), Vector2(150, 340)]
	var enemy_positions = [Vector2(780, 200), Vector2(780, 340)]
	var ally_ids = [1001, 1002]
	var enemy_ids = [2001, 2002]

	for i in range(2):
		var u = CharacterBody2D.new()
		var script = load("res://demo/auto_battle/battle_unit.gd")
		u.set_script(script)
		add_child(u)
		u.setup(ally_ids[i], "ally", ds, enums_rt, ally_positions[i])
		u.died.connect(_on_unit_died)
		u.hit_dealt.connect(_on_hit_dealt)
		_units.append(u)

	for i in range(2):
		var u = CharacterBody2D.new()
		var script = load("res://demo/auto_battle/battle_unit.gd")
		u.set_script(script)
		add_child(u)
		u.setup(enemy_ids[i], "enemy", ds, enums_rt, enemy_positions[i])
		u.died.connect(_on_unit_died)
		u.hit_dealt.connect(_on_hit_dealt)
		_units.append(u)

	_log("Units spawned: 2 Ally vs 2 Enemy")

func _process(_delta: float) -> void:
	if not _battle_active or _battle_over:
		return

	var ally_alive = 0
	var enemy_alive = 0
	for u in _units:
		if not u._is_dead:
			if u.camp == "ally":
				ally_alive += 1
			else:
				enemy_alive += 1

	if ally_alive == 0:
		_end_battle("enemy")
	elif enemy_alive == 0:
		_end_battle("ally")

func _on_start_pressed() -> void:
	if _battle_active:
		return
	_battle_active = true
	_battle_over = false
	_btn_start.disabled = true
	_btn_start.text = "Fighting..."
	_status_label.text = "Battle in progress..."
	for u in _units:
		if is_instance_valid(u):
			u.set_battle_active(true)
	_log("[color=yellow]--- Battle Started ---[/color]")

func _on_reset_pressed() -> void:
	_battle_active = false
	_battle_over = false
	_btn_start.disabled = false
	_btn_start.text = "Start Battle"
	_status_label.text = "Ready — Press Start"
	_log_lines.clear()
	_battle_log.clear()
	for u in _units:
		if is_instance_valid(u):
			u.set_battle_active(false)
			u.queue_free()
	_units.clear()
	_spawn_units()

func _on_unit_died(unit) -> void:
	var team = "Ally" if unit.camp == "ally" else "Enemy"
	_log("[color=red]%s %d has fallen![/color]" % [team, unit.entity_id])

func _on_hit_dealt(attacker, target, damage) -> void:
	var a_name = "Ally-%d" % attacker.entity_id if attacker.camp == "ally" else "Enemy-%d" % attacker.entity_id
	var t_name = "Ally-%d" % target.entity_id if target.camp == "ally" else "Enemy-%d" % target.entity_id
	var color = "cyan" if attacker.camp == "ally" else "orange"
	_log("[color=%s]%s[/color] → %s: [b]%d[/b] dmg (HP: %d)" % [color, a_name, t_name, int(ceil(damage)), int(ceil(target._hp))])

func _end_battle(winner: String) -> void:
	_battle_active = false
	_battle_over = true
	for u in _units:
		if is_instance_valid(u):
			u.set_battle_active(false)
	_btn_start.disabled = false
	_btn_start.text = "Start Battle"
	if winner == "ally":
		_status_label.text = "Ally Wins!"
		_log("[color=cyan]=== ALLY VICTORY ===[/color]")
	else:
		_status_label.text = "Enemy Wins!"
		_log("[color=orange]=== ENEMY VICTORY ===[/color]")

func _log(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 100:
		_log_lines.pop_front()
	_battle_log.append_text(text + "\n")
	_battle_log.scroll_to_line(_battle_log.get_line_count())
