extends Node2D

const BattleUnit = preload("res://demo/auto_battle/battle_unit.gd")

@onready var _btn_start: Button = %BtnStart
@onready var _btn_reset: Button = %BtnReset
@onready var _status_label: Label = %StatusLabel
@onready var _battle_log: RichTextLabel = %BattleLog

var ds = null
var enums_rt = null
var _units: Array[Node] = []
var _unit_map: Dictionary = {}
var _turn_manager: TurnManager
var _battle_active: bool = false
var _battle_over: bool = false
var _max_turns: int = 50
var _turns_elapsed: int = 0
var _hp_id: int = -1
var _max_hp_id: int = -1
var _speed_id: int = -1
var _auto_step_delay: float = 0.6
var _skill_rt = null
var _log_lines: Array = []
var _unit_nodes: Dictionary = {}

func _ready() -> void:
	_btn_start.pressed.connect(_on_start_pressed)
	_btn_reset.pressed.connect(_on_reset_pressed)
	_load_dataset()
	_spawn_units()

func _load_dataset() -> void:
	var result = OmniManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", false)
	enums_rt = OmniEnumsRuntime.from_enums_json(result.enums)
	ds = OmniDatasetCompiler.compile(result.manifest, enums_rt, result.sources)
	_hp_id = int(ds.stat_id("HP"))
	_max_hp_id = int(ds.stat_id("MAX_HP"))
	_speed_id = int(ds.stat_id("SPEED"))

func _spawn_units() -> void:
	_units.clear()
	_unit_map.clear()
	_unit_nodes.clear()

	var configs = [
		{"id": 1, "camp": "ally", "cell": Vector2i(0, 1), "pos": Vector2(240, 200), "name": "Hero",
		 "hp": 1220.0, "mp": 80.0, "atk": 155.0, "def": 22.0, "spd": 10.0,
		 "skills": ["act_hero_strike", "act_hero_whirlwind"],
		 "passives": ["pas_hero_battle_haste"]},
		{"id": 2, "camp": "ally", "cell": Vector2i(0, 2), "pos": Vector2(240, 340), "name": "Ally",
		 "hp": 160.0, "mp": 120.0, "atk": 25.0, "def": 18.0, "spd": 7.0,
		 "skills": ["act_ally_basic", "act_ally_heal"],
		 "passives": [],
		 "aura": "aur_ally_guard"},
		{"id": 3, "camp": "enemy", "cell": Vector2i(2, 1), "pos": Vector2(720, 200), "name": "Boss",
		 "hp": 420.0, "mp": 100.0, "atk": 80.0, "def": 35.0, "spd": 12.0,
		 "skills": ["act_boss_basic", "act_boss_crush", "act_boss_quake"],
		 "passives": []},
		{"id": 4, "camp": "enemy", "cell": Vector2i(2, 0), "pos": Vector2(720, 80), "name": "Minion",
		 "hp": 240.0, "mp": 40.0, "atk": 40.0, "def": 20.0, "spd": 9.0,
		 "skills": ["act_minion_stab"],
		 "passives": []},
	]

	for cfg in configs:
		var u = Node2D.new()
		var script = load("res://demo/auto_battle/battle_unit.gd")
		u.set_script(script)
		add_child(u)
		u.setup(cfg.id, cfg.camp, cfg.cell, ds, enums_rt, cfg.pos)
		u._name_label.text = cfg.name
		_init_unit_stats(u, cfg)
		u.refresh_hp_bar()
		_units.append(u)
		_unit_map[cfg.id] = u
		_unit_nodes[cfg.id] = u

	_log("Units spawned: Hero + Ally vs Boss + Minion")

func _init_unit_stats(u, cfg: Dictionary) -> void:
	_set_stat_value(u.stats, ds, "MAX_HP", cfg.hp)
	_set_stat_value(u.stats, ds, "HP", cfg.hp)
	_set_stat_value(u.stats, ds, "MAX_MP", cfg.mp)
	_set_stat_value(u.stats, ds, "MP", cfg.mp)
	_set_stat_value(u.stats, ds, "ATK", cfg.atk)
	_set_stat_value(u.stats, ds, "DEF", cfg.def)
	_set_stat_value(u.stats, ds, "SPEED", cfg.spd)

func _set_stat_value(stats, dataset, stat_name: String, desired: float) -> void:
	var sid = int(dataset.stat_id(stat_name))
	if sid < 0:
		return
	var cur = float(stats.get_final(sid))
	stats.add_base(sid, desired - cur)

func _on_start_pressed() -> void:
	if _battle_active:
		return

	if not has_node("/root/TurnSkillRuntime"):
		_log("[color=red]ERROR: TurnSkillRuntime Autoload not found. Enable Turn Skill System plugin.[/color]")
		return

	_skill_rt = get_node("/root/TurnSkillRuntime")
	if _skill_rt.has_method("ensure_ready"):
		_skill_rt.ensure_ready()

	var runtime_dict = {
		"stats_by_entity": {},
		"buff_by_entity": {}
	}
	for u in _units:
		runtime_dict["stats_by_entity"][u.entity_id] = u.stats
		runtime_dict["buff_by_entity"][u.entity_id] = u.buffs

	_skill_rt.grid.set_units(_units)
	_skill_rt.omnibuff.setup(ds, enums_rt, runtime_dict)

	var hero = _unit_map.get(1)
	var ally = _unit_map.get(2)
	if hero != null:
		var hero_passives: Array[String] = ["pas_hero_battle_haste"]
		_skill_rt.passive_manager.register_unit_passives(hero, hero_passives)
	if ally != null:
		_skill_rt.aura_manager.register_aura(ally, "aur_ally_guard")
	_skill_rt.aura_manager.refresh_all()

	var context = BattleContext.new()
	context.build_from_autoload()
	context.dataset = ds
	context.enums_rt = enums_rt
	context.runtime_dict = runtime_dict

	_turn_manager = TurnManager.new()
	add_child(_turn_manager)

	_turn_manager.action_requested.connect(_on_action_requested)
	_turn_manager.battle_ended.connect(_on_battle_ended)
	_turn_manager.turn_started.connect(_on_turn_started)
	_turn_manager.turn_ended.connect(_on_turn_ended)

	_skill_rt.event_bus.event_emitted.connect(_on_event_bus_event)

	_turn_manager.setup(context, _units)

	_battle_active = true
	_battle_over = false
	_btn_start.disabled = true
	_btn_start.text = "Fighting..."
	_status_label.text = "Battle in progress..."
	_log("[color=yellow]--- Battle Started ---[/color]")

	_turn_manager.start_battle()

func _on_reset_pressed() -> void:
	_battle_active = false
	_battle_over = false
	_turns_elapsed = 0
	_btn_start.disabled = false
	_btn_start.text = "Start Battle"
	_status_label.text = "Ready — Press Start"
	_log_lines.clear()
	_battle_log.clear()

	if _turn_manager != null and is_instance_valid(_turn_manager):
		_turn_manager.queue_free()
		_turn_manager = null

	for u in _units:
		if is_instance_valid(u):
			u.queue_free()
	_units.clear()
	_unit_map.clear()
	_unit_nodes.clear()
	_spawn_units()

func _on_action_requested(actor: Node, valid_skills: Array) -> void:
	if not _battle_active or _battle_over:
		return
	if _turns_elapsed >= _max_turns:
		return

	var eid = int(actor.entity_id)
	var camp = String(actor.camp)

	if _auto_step_delay > 0.0:
		await get_tree().create_timer(_auto_step_delay).timeout

	var cmd: TurnCommand = null

	if camp == "ally":
		if eid == 1:
			cmd = TurnCommand.new_skill("act_hero_strike", Vector2i(0, 0))
		elif eid == 2:
			var should_heal = _should_ally_heal()
			if should_heal:
				cmd = TurnCommand.new_skill("act_ally_heal", Vector2i(0, 0))
			else:
				cmd = TurnCommand.new_skill("act_ally_basic", Vector2i(0, 0))
	else:
		if eid == 3:
			var chosen = _choose_boss_skill(eid)
			cmd = TurnCommand.new_skill(chosen, Vector2i(0, 0))
		else:
			cmd = TurnCommand.new_skill("act_minion_stab", Vector2i(0, 0))

	if cmd != null and _turn_manager != null:
		_play_attack_anim_for_skill(actor, cmd.id)
		await get_tree().create_timer(0.45).timeout
		_turn_manager.submit_player_command(cmd)

func _choose_boss_skill(eid: int) -> String:
	if _turn_manager == null:
		return "act_boss_basic"
	var cd_quake = int(_turn_manager._get_skill_cooldown(eid, "act_boss_quake"))
	var cd_crush = int(_turn_manager._get_skill_cooldown(eid, "act_boss_crush"))
	if cd_quake <= 0 and cd_crush <= 0:
		if randi() % 2 == 0:
			return "act_boss_quake"
		else:
			return "act_boss_crush"
	if cd_quake <= 0:
		return "act_boss_quake"
	if cd_crush <= 0:
		return "act_boss_crush"
	return "act_boss_basic"

func _should_ally_heal() -> bool:
	for u in _units:
		if u.camp == "ally" and not u.is_dead():
			var cur_hp = float(u.stats.get_final(_hp_id))
			var max_hp = float(u.stats.get_final(_max_hp_id))
			if max_hp > 0 and cur_hp / max_hp < 0.5:
				return true
	return false

func _play_attack_anim_for_skill(actor, skill_id: String) -> void:
	var target_cell = _pick_target_cell(actor, skill_id)
	var target_unit = _unit_map.get(_find_unit_id_at_cell(target_cell))
	if target_unit != null and not target_unit.is_dead():
		actor.play_attack_animation(target_unit)

func _pick_target_cell(actor, skill_id: String) -> Vector2i:
	if _skill_rt == null:
		return Vector2i(0, 0)
	var first_enemy = _skill_rt.grid.get_first_enemy(actor)
	if first_enemy != null:
		return Vector2i(first_enemy.cell)
	return Vector2i(0, 0)

func _find_unit_id_at_cell(c: Vector2i) -> int:
	for u in _units:
		if u.cell == c and not u.is_dead():
			return int(u.entity_id)
	return -1

func _on_turn_started(actor, index: int) -> void:
	_log("[color=gray]--- Turn %d: %s ---[/color]" % [index, _unit_name(actor)])

func _on_turn_ended(actor, index: int) -> void:
	_turns_elapsed += 1
	_refresh_all_hp_bars()
	if _turns_elapsed >= _max_turns:
		_log("[color=yellow]Max turns reached, battle draw.[/color]")
		_end_battle()

func _on_battle_ended(result) -> void:
	_end_battle()

func _on_event_bus_event(event_name: String, data: Dictionary) -> void:
	match event_name:
		"action_started":
			var eid = int(data.get("actor_id", -1))
			var skill_id = String(data.get("skill_id", ""))
			var u = _unit_map.get(eid)
			if u != null:
				_log("[color=cyan]%s[/color] uses [b]%s[/b]" % [_unit_name(u), skill_id])
		"action_finished":
			_refresh_all_hp_bars()
		"unit_died":
			var eid = int(data.get("actor_id", -1))
			var u = _unit_map.get(eid)
			if u != null:
				_log("[color=red]%s has fallen![/color]" % _unit_name(u))
				u.refresh_hp_bar()
		"buff_applied":
			var target_eid = int(data.get("target_id", data.get("entity_id", -1)))
			var buff_id = String(data.get("buff_id", ""))
			var u = _unit_map.get(target_eid)
			if u != null and buff_id != "":
				_log("  %s gained [color=green]%s[/color]" % [_unit_name(u), buff_id])
		"buff_removed":
			var target_eid = int(data.get("target_id", data.get("entity_id", -1)))
			var buff_id = String(data.get("buff_id", ""))
			var u = _unit_map.get(target_eid)
			if u != null and buff_id != "":
				_log("  %s lost [color=orange]%s[/color]" % [_unit_name(u), buff_id])
		"after_damage":
			var dmg = float(data.get("final_damage", 0.0))
			var target_eid = int(data.get("defender_id", -1))
			var attacker_eid = int(data.get("attacker_id", -1))
			var target_u = _unit_map.get(target_eid)
			var attacker_u = _unit_map.get(attacker_eid)
			if target_u != null and dmg > 0:
				target_u.show_damage_number(dmg)
				target_u.refresh_hp_bar()
				var a_name = _unit_name(attacker_u) if attacker_u != null else "?"
				_log("  [color=orange]%s[/color] → %s: [b]%d[/b] dmg" % [a_name, _unit_name(target_u), int(ceil(dmg))])
		"after_heal":
			var amount = float(data.get("amount", 0.0))
			var target_eid = int(data.get("target_id", -1))
			var u = _unit_map.get(target_eid)
			if u != null and amount > 0:
				u.show_heal_number(amount)
				u.refresh_hp_bar()
				_log("  %s healed [color=green]+%d[/color]" % [_unit_name(u), int(ceil(amount))])

func _refresh_all_hp_bars() -> void:
	for u in _units:
		if is_instance_valid(u):
			u.refresh_hp_bar()

func _end_battle() -> void:
	_battle_active = false
	_battle_over = true
	_btn_start.disabled = false
	_btn_start.text = "Start Battle"

	var ally_alive = 0
	var enemy_alive = 0
	for u in _units:
		if is_instance_valid(u) and not u.is_dead():
			if u.camp == "ally":
				ally_alive += 1
			else:
				enemy_alive += 1

	if ally_alive > 0 and enemy_alive <= 0:
		_status_label.text = "Ally Wins!"
		_log("[color=cyan]=== ALLY VICTORY ===[/color]")
	elif enemy_alive > 0 and ally_alive <= 0:
		_status_label.text = "Enemy Wins!"
		_log("[color=orange]=== ENEMY VICTORY ===[/color]")
	else:
		_status_label.text = "Battle Draw!"
		_log("[color=yellow]=== DRAW ===[/color]")

func _unit_name(u) -> String:
	if u == null:
		return "?"
	if u._name_label != null:
		return String(u._name_label.text)
	return "Unit-%d" % int(u.entity_id)

func _log(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 200:
		_log_lines.pop_front()
	_battle_log.append_text(text + "\n")
	_battle_log.scroll_to_line(_battle_log.get_line_count())
