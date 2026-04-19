extends Node

const OmniBuff = preload("res://addons/omnibuff/runtime/omnibuff_singleton.gd")

class DemoBattleUnit extends Node:
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var speed: float
	var stats: RefCounted
	var buffs: RefCounted
	var _hp_stat_id: int = -1
	
	func _init(p_id: int, p_camp: String, p_cell: Vector2i, p_speed: float) -> void:
		entity_id = p_id
		camp = p_camp
		cell = p_cell
		speed = p_speed
		
	func get_speed() -> float:
		return speed
		
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
var _debug_pending_ratio_sync: bool = false
var _did_cast_max_hp_up: bool = false

func _ready() -> void:
	print("--- TurnManager Demo Start ---")
	
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
	
	# 2. Initialize components
	turn_manager = TurnManager.new()
	add_child(turn_manager)
	
	# 3. Create 2v2 units
	var u1 = DemoBattleUnit.new(1, "ally", Vector2i(0, 0), 10.0)
	var u2 = DemoBattleUnit.new(2, "ally", Vector2i(0, 1), 9.0)
	var u3 = DemoBattleUnit.new(3, "enemy", Vector2i(1, 0), 8.0)
	var u4 = DemoBattleUnit.new(4, "enemy", Vector2i(1, 1), 7.0)
	
	var units: Array[Node] = []
	units.assign([u1, u2, u3, u4])
	for u in units:
		add_child(u)
		u.stats = OmniBuff.StatsComponent.new(u.entity_id, ds)
		u.buffs = OmniBuff.BuffCore.new(ds, enums_rt)
		u._hp_stat_id = _hp_id

		# 使用“读当前 → 加 delta”方式设置初值，避免依赖 default 行为
		var atk_id = int(ds.stat_id("ATK"))
		if atk_id >= 0:
			var cur_atk = float(u.stats.get_final(atk_id))
			u.stats.add_base(atk_id, 50.0 - cur_atk)

		# 初始化资源对（HP/MP/RAGE）
		if _max_hp_id >= 0:
			var cur_max_hp = float(u.stats.get_final(_max_hp_id))
			u.stats.add_base(_max_hp_id, 100.0 - cur_max_hp)
		if _hp_id >= 0:
			var cur_hp = float(u.stats.get_final(_hp_id))
			u.stats.add_base(_hp_id, 100.0 - cur_hp)

		if _max_mp_id >= 0:
			var cur_max_mp = float(u.stats.get_final(_max_mp_id))
			u.stats.add_base(_max_mp_id, 50.0 - cur_max_mp)
		if _mp_id >= 0:
			var cur_mp = float(u.stats.get_final(_mp_id))
			u.stats.add_base(_mp_id, 50.0 - cur_mp)

		if _max_rage_id >= 0:
			var cur_max_rage = float(u.stats.get_final(_max_rage_id))
			u.stats.add_base(_max_rage_id, 100.0 - cur_max_rage)
		if _rage_id >= 0:
			var cur_rage = float(u.stats.get_final(_rage_id))
			u.stats.add_base(_rage_id, 0.0 - cur_rage)

	# 让 ally#1 以 50% 血量开局（用于演示“回合内 MAX_HP 变化时保持百分比 + floor”）
	if _hp_id >= 0 and _max_hp_id >= 0:
		var cur_hp_u1 = float(u1.stats.get_final(_hp_id))
		u1.stats.add_base(_hp_id, 50.0 - cur_hp_u1)
		
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
	
	# 6. Build BattleContext
	var context = BattleContext.new()
	context.build_from_autoload()
	context.dataset = ds
	context.enums_rt = enums_rt
	context.runtime_dict = runtime_dict
	
	# 7. Connect signals
	turn_manager.action_requested.connect(_on_action_requested)
	turn_manager.turn_started.connect(func(actor, index):
		print("[Demo] Turn started for entity %d (turn %d)" % [actor.entity_id, index])
	)
	turn_manager.turn_ended.connect(func(actor, index):
		print("[Demo] Turn ended for entity %d (turn %d)" % [actor.entity_id, index])
		_turns_elapsed += 1
		if _turns_elapsed >= _max_turns:
			push_warning("[Demo] Reached max turns=%d, stopping battle to avoid infinite loop." % _max_turns)
			turn_manager.stop_battle()
		# 演示：entity 1 在回合内 MAX_HP 增加后，TurnManager 应在 ACTION_FINISHED 后同步 HP，使百分比保持不变
		if _debug_pending_ratio_sync and int(actor.get("entity_id")) == 1:
			_debug_pending_ratio_sync = false
			if _hp_id >= 0 and _max_hp_id >= 0:
				var hp_after = float(actor.stats.get_final(_hp_id))
				var max_after = float(actor.stats.get_final(_max_hp_id))
				print("[Demo] After sync (turn_end): entity=1 HP/MAX_HP = %s/%s" % [str(hp_after), str(max_after)])
	)
	turn_manager.battle_ended.connect(func(res): print("[Demo] Battle ended: ", res))
	
	# Subscribe to event bus to see actions
	context.event_bus.event_emitted.connect(func(event_name, data):
		if event_name in ["action_started", "action_finished", "unit_died"]:
			print("[Demo Event] ", event_name, " ", data)
		# 演示：改为“数据驱动”——entity 1 在 turn 1 施放 act_demo_max_hp_up 给自己加 MAX_HP+30%（3回合，可刷新），
		# TurnManager 会在 ACTION_FINISHED 后自动同步 HP，保持百分比不变。
		if event_name == "action_finished":
			var actor_id = int(data.get("actor_id", -1))
			var turn_index = int(data.get("turn_index", -1))
			if actor_id == 1 and turn_index == 1 and _max_hp_id >= 0 and _hp_id >= 0:
				var hp_before = float(u1.stats.get_final(_hp_id))
				var max_before = float(u1.stats.get_final(_max_hp_id))
				print("[Demo] After MAX_HP buff (action_finished): entity=1 HP/MAX_HP = %s/%s" % [str(hp_before), str(max_before)])
				_debug_pending_ratio_sync = true
	)
	
	# 8. Start battle
	print("[Demo] Setting up TurnManager...")
	turn_manager.setup(context, units)
	turn_manager.start_battle()
	
func _on_action_requested(actor: Node, valid_skills: Array) -> void:
	if _turns_elapsed >= _max_turns:
		return
	print("[Demo] Action requested for entity %d, submitting command..." % actor.entity_id)
	
	# entity 1 的第 1 回合：对自己施放 MAX_HP +30%（3回合，可刷新）
	if int(actor.get("entity_id")) == 1 and not _did_cast_max_hp_up:
		_did_cast_max_hp_up = true
		var self_cell = actor.get("cell")
		var cmd0 = TurnCommand.new("act_demo_max_hp_up", Vector2i(self_cell))
		turn_manager.submit_player_command(cmd0)
		return

	# Find an alive enemy
	var target_cell = Vector2i.ZERO
	var skill_rt = get_node("/root/TurnSkillRuntime")
	var target = skill_rt.grid.get_first_enemy(actor)
	if target:
		target_cell = target.get("cell")
	
	# Auto-submit a command
	var cmd = TurnCommand.new("act_demo_single", target_cell)
	turn_manager.submit_player_command(cmd)
