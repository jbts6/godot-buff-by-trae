extends Node

const OmniBuff = preload("res://addons/omnibuff/runtime/omnibuff_singleton.gd")
const BattleLogger = preload("res://addons/turn_manager/runtime/battle_logger.gd")
const BattleNarrator = preload("res://addons/turn_manager/runtime/battle_narrator.gd")

@onready var battle_log_panel: BattleLogPanel = %BattleLogPanel

class DemoBattleUnit extends Node:
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var stats: RefCounted
	var buffs: RefCounted
	var _hp_stat_id: int = -1
	var _speed_stat_id: int = -1
	
	func _init(p_id: int, p_camp: String, p_cell: Vector2i) -> void:
		entity_id = p_id
		camp = p_camp
		cell = p_cell
		
	func get_speed() -> float:
		if stats == null:
			return 0.0
		if _speed_stat_id < 0:
			return 0.0
		if not stats.has_method("get_final"):
			return 0.0
		return float(stats.call("get_final", _speed_stat_id))
		
	func is_dead() -> bool:
		# 供 TurnSkillSystem.Grid.get_first_enemy 判定存活目标使用。
		# TurnManager 本身也有基于 stats 的默认判死，但 Grid 无法访问 dataset，因此这里必须提供。
		if stats == null:
			return false
		if _hp_stat_id < 0:
			return false
		if not stats.has_method("get_final"):
			return false
		return float(stats.call("get_final", _hp_stat_id)) <= 0.0

var turn_manager: TurnManager
var _max_turns: int = 50
var _turns_elapsed: int = 0
var _hp_id: int = -1
var _max_hp_id: int = -1
var _mp_id: int = -1
var _max_mp_id: int = -1
var _rage_id: int = -1
var _max_rage_id: int = -1
var _speed_id: int = -1
var _logger: BattleLogger
var _narrator: BattleNarrator
var _auto_step_delay_sec: float = 1.0

func _ready() -> void:
	_logger = BattleLogger.new()
	_logger.log_banner("TurnManager Demo Start")
	
	# 1. Compile ds/enums_rt
	var manifest_path = "res://data/rpg_tests/manifest.json"
	var result = OmniBuff.ManifestLoader.load_dataset_full(manifest_path, true)
	if result == null:
		push_error("[Demo] Failed to load dataset: result is null")
		return
	if result.manifest.is_empty() or result.enums.is_empty():
		push_error("[Demo] Failed to load dataset manifest/enums. Check issues in result.issues")
		return
	
	var enums_rt = OmniBuff.EnumsRuntime.from_enums_json(result.enums)
	var ds = OmniBuff.DatasetCompiler.compile(result.manifest, enums_rt, result.sources)
	if ds == null:
		push_error("[Demo] DatasetCompiler.compile failed")
		return

	# 1.1 资源型属性 id（当前/最大）
	_hp_id = int(ds.stat_id("HP"))
	_max_hp_id = int(ds.stat_id("MAX_HP"))
	_mp_id = int(ds.stat_id("MP"))
	_max_mp_id = int(ds.stat_id("MAX_MP"))
	_rage_id = int(ds.stat_id("RAGE"))
	_max_rage_id = int(ds.stat_id("MAX_RAGE"))
	_speed_id = int(ds.stat_id("SPEED"))
	
	# 2. Initialize components
	turn_manager = TurnManager.new()
	add_child(turn_manager)
	
	# 3. Create 2v2 units（主角/队友 vs Boss/随从）
	# 站位仅用于日志定位；光环定义为“作用于全体友军”，不依赖站位。
	var hero = DemoBattleUnit.new(1, "ally", Vector2i(0, 1))
	var ally = DemoBattleUnit.new(2, "ally", Vector2i(0, 2))
	var boss = DemoBattleUnit.new(3, "enemy", Vector2i(2, 1))
	var minion = DemoBattleUnit.new(4, "enemy", Vector2i(2, 0))
	
	var units: Array[Node] = []
	units.assign([hero, ally, boss, minion])
	for u in units:
		add_child(u)
		u.stats = OmniBuff.StatsComponent.new(u.entity_id, ds)
		u.buffs = OmniBuff.BuffCore.new(ds, enums_rt)
		u._hp_stat_id = _hp_id
		u._speed_stat_id = _speed_id
		_init_unit_stats(u, ds)
		
	# 4. Build runtime_dict
	var runtime_dict = {
		"stats_by_entity": {},
		"buff_by_entity": {}
	}
	for u in units:
		runtime_dict["stats_by_entity"][u.entity_id] = u.stats
		runtime_dict["buff_by_entity"][u.entity_id] = u.buffs
		
	# 5. Bind to TurnSkillRuntime
	if not has_node("/root/TurnSkillRuntime"):
		push_error("[Demo] Missing /root/TurnSkillRuntime. Enable Turn Skill System plugin first.")
		return
	var skill_rt = get_node("/root/TurnSkillRuntime")
	if skill_rt.has_method("ensure_ready"):
		skill_rt.ensure_ready()
	skill_rt.grid.set_units(units)
	skill_rt.omnibuff.setup(ds, enums_rt, runtime_dict)
	# 注册被动与光环
	var hero_passives: Array[String] = ["pas_hero_battle_haste"]
	skill_rt.passive_manager.register_unit_passives(hero, hero_passives)
	skill_rt.aura_manager.register_aura(ally, "aur_ally_guard")
	skill_rt.aura_manager.refresh_all()
	
	# 6. Build BattleContext
	var context = BattleContext.new()
	context.build_from_autoload()
	context.dataset = ds
	context.enums_rt = enums_rt
	context.runtime_dict = runtime_dict

	# 6.1 语义化播报（输出到面板；默认简洁，可切换详细）
	_narrator = BattleNarrator.new()
	_narrator.bind(context.event_bus, skill_rt.grid, ds, skill_rt.db, runtime_dict, {
		1: "主角",
		2: "队友",
		3: "Boss",
		4: "随从",
	}, {"detail_level": BattleNarrator.DETAIL_CONCISE})
	if battle_log_panel != null:
		battle_log_panel.set_narrator(_narrator)
		_narrator.line_emitted.connect(func(bb: String, meta: Dictionary):
			battle_log_panel.append_line(bb, meta)
		)
	
	# 7. Connect signals
	turn_manager.action_requested.connect(_on_action_requested)
	turn_manager.turn_started.connect(func(actor, index):
		_logger.log_turn_started(actor, index)
	)
	turn_manager.turn_ended.connect(func(actor, index):
		_logger.log_turn_ended(actor, index)
		_turns_elapsed += 1
		_logger.log_units_status("after_turn_%d" % index, units, _get_stat_ids_dict())
		if _turns_elapsed >= _max_turns:
			push_warning("[Demo] Reached max turns=%d, stopping battle to avoid infinite loop." % _max_turns)
			turn_manager.stop_battle()
	)
	turn_manager.battle_ended.connect(func(res): _logger.log_event("battle_ended", res))
	
	# Subscribe to event bus to see actions
	context.event_bus.event_emitted.connect(func(event_name, data):
		if event_name in ["battle_started", "action_started", "action_finished", "unit_died"]:
			_logger.log_event(event_name, data)
		if event_name == "battle_started":
			_logger.log_units_status("battle_started", units, _get_stat_ids_dict())
	)
	
	# 8. Start battle
	print("[Demo] Setting up TurnManager...")
	turn_manager.setup(context, units)
	turn_manager.start_battle()
	
func _on_action_requested(actor: Node, valid_skills: Array) -> void:
	if _turns_elapsed >= _max_turns:
		return
	_logger.log_event("action_requested", {"entity_id": int(actor.get("entity_id"))})
	# 仅 demo：给自动回合一点节奏感
	if _auto_step_delay_sec > 0.0:
		await get_tree().create_timer(_auto_step_delay_sec).timeout

	var eid = int(actor.get("entity_id"))
	var cmd: TurnCommand = null
	if eid == 1:
		# 主角：优先 AOE（CD=2），否则单体
		var sid = "act_hero_strike"
		if turn_manager._get_skill_cooldown(eid, "act_hero_whirlwind") <= 0:
			sid = "act_hero_whirlwind"
		cmd = TurnCommand.new(sid, Vector2i(0, 0))
	elif eid == 2:
		# 队友：血量低于 60% 则治疗；否则普攻
		var target_ally = _pick_lowest_hp_ally()
		if target_ally != null and _get_hp_ratio(target_ally) < 0.6:
			cmd = TurnCommand.new("act_ally_heal", Vector2i(target_ally.get("cell")))
		else:
			var enemy_cell = _pick_first_enemy_cell(actor)
			cmd = TurnCommand.new("act_ally_basic", enemy_cell)
	elif eid == 3:
		# Boss：所有主动技能都在冷却；当全部在冷却时退化普攻
		var cd_quake = int(turn_manager._get_skill_cooldown(eid, "act_boss_quake"))
		var cd_crush = int(turn_manager._get_skill_cooldown(eid, "act_boss_crush"))
		_logger.log_boss_cooldowns("before_choose", {"quake": cd_quake, "crush": cd_crush})
		var chosen = String(turn_manager._choose_skill_with_cooldown(eid, ["act_boss_quake", "act_boss_crush"], "act_boss_basic"))
		cmd = TurnCommand.new(chosen, Vector2i(0, 0))
	else:
		# 随从：固定单体
		cmd = TurnCommand.new("act_minion_stab", Vector2i(0, 0))
		
	if cmd != null:
		_logger.log_event("submit_command", {
			"entity_id": eid,
			"skill_id": String(cmd.skill_id),
			"primary_cell": cmd.primary_cell,
		})
		turn_manager.submit_player_command(cmd)


func _init_unit_stats(u: DemoBattleUnit, ds) -> void:
	var hp = 100.0
	var mp = 50.0
	var atk = 10.0
	var def = 5.0
	var spd = 0.0
	match int(u.entity_id):
		1: # HERO
			hp = 220.0
			mp = 80.0
			atk = 55.0
			def = 22.0
			spd = 10.0
		2: # ALLY
			hp = 160.0
			mp = 120.0
			atk = 25.0
			def = 18.0
			spd = 7.0
		3: # BOSS
			hp = 420.0
			mp = 100.0
			atk = 80.0
			def = 35.0
			spd = 12.0
		4: # MINION
			hp = 240.0
			mp = 40.0
			atk = 40.0
			def = 20.0
			spd = 9.0

	var stats = u.stats
	if stats == null:
		return
	_set_stat_value(stats, ds, "MAX_HP", hp)
	_set_stat_value(stats, ds, "HP", hp)
	_set_stat_value(stats, ds, "MAX_MP", mp)
	_set_stat_value(stats, ds, "MP", mp)
	_set_stat_value(stats, ds, "ATK", atk)
	_set_stat_value(stats, ds, "DEF", def)
	_set_stat_value(stats, ds, "SPEED", spd)


func _set_stat_value(stats, ds, stat_name: String, desired: float) -> void:
	var sid = int(ds.stat_id(stat_name))
	if sid < 0:
		return
	var cur = float(stats.get_final(sid))
	stats.add_base(sid, desired - cur)


func _get_hp_ratio(u: Node) -> float:
	if u == null:
		return 1.0
	var st = u.get("stats")
	if st == null:
		return 1.0
	if _hp_id < 0 or _max_hp_id < 0:
		return 1.0
	var cur_hp = float(st.get_final(_hp_id))
	var max_hp = float(st.get_final(_max_hp_id))
	if max_hp <= 0.0:
		return 0.0
	return clamp(cur_hp / max_hp, 0.0, 1.0)


func _pick_lowest_hp_ally() -> Node:
	var skill_rt = get_node("/root/TurnSkillRuntime")
	var best: Node = null
	var best_ratio = 999.0
	for u in skill_rt.grid._units:
		if u == null:
			continue
		if String(u.get("camp")) != "ally":
			continue
		if u.has_method("is_dead") and bool(u.call("is_dead")):
			continue
		var r = _get_hp_ratio(u)
		if r < best_ratio:
			best_ratio = r
			best = u
	return best


func _pick_first_enemy_cell(actor: Node) -> Vector2i:
	var skill_rt = get_node("/root/TurnSkillRuntime")
	var t = skill_rt.grid.get_first_enemy(actor)
	if t != null:
		return Vector2i(t.get("cell"))
	return Vector2i(0, 0)


func _get_stat_ids_dict() -> Dictionary:
	return {
		"HP": _hp_id,
		"MAX_HP": _max_hp_id,
		"MP": _mp_id,
		"MAX_MP": _max_mp_id,
		"SPEED": _speed_id,
	}
