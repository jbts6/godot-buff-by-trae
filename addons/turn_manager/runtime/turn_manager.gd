class_name TurnManager
extends Node

signal battle_started(units: Array[Node])
signal round_started(round_index: int, queue: Array[Node])
signal turn_started(actor: Node, turn_index: int)
signal action_requested(actor: Node, valid_skill_ids: Array[String])
signal action_committed(actor: Node, command: TurnCommand)
signal action_resolving(actor: Node, command: TurnCommand)
signal turn_ended(actor: Node, turn_index: int)
signal battle_ended(result: Dictionary)

enum State {
	IDLE,
	ROUND_START,
	TURN_START,
	REQUEST_ACTION,
	RESOLVE_ACTION,
	TURN_END,
	CHECK_END,
	BATTLE_END
}

@export var ally_camp_name: String = "ally"
@export var enemy_camp_name: String = "enemy"
@export var hp_stat_id: String = "HP"
@export_enum("spawn_index", "cell") var stable_order_mode: String = "spawn_index"

var _state: int = State.IDLE
var _context: BattleContext
var _units: Array[Node] = []
var _turn_queue: Array[Node] = []
var _round_index: int = 0
var _turn_index: int = 1
var _current_actor: Node = null
var _current_command: TurnCommand = null
var _victory_condition: VictoryCondition
var resource_snapshot_by_entity: Dictionary = {}
var cooldown_by_entity: Dictionary = {} # eid -> {skill_id:String : turns_remaining:int}

func setup(context: BattleContext, units: Array[Node]) -> void:
	_context = context
	_units = units
	
	if not _context.validate():
		push_error("[TurnManager] Setup failed due to invalid context")
		return
		
	if _context.runtime_dict.is_empty() or not _context.runtime_dict.has("stats_by_entity"):
		_context.runtime_dict["stats_by_entity"] = {}
		_context.runtime_dict["buff_by_entity"] = {}
		
	var spawn_index = 0
	for u in _units:
		if not u.has_method("get_speed"):
			push_error("[TurnManager] Unit %s is missing get_speed() method" % u.name)
			
		var eid = u.get("entity_id")
		if eid != null:
			if u.get("stats"):
				_context.runtime_dict["stats_by_entity"][eid] = u.get("stats")
			if u.get("buffs"):
				_context.runtime_dict["buff_by_entity"][eid] = u.get("buffs")
				
		u.set_meta("spawn_index", spawn_index)
		spawn_index += 1
		
	_context.grid.set_units(_units)
	_victory_condition = VictoryCondition.new(ally_camp_name, enemy_camp_name)

func start_battle() -> void:
	if _state != State.IDLE:
		return
	_round_index = 1
	_turn_index = 1
	if _context != null and _context.event_bus != null:
		_context.event_bus.emit_event(EventNames.BATTLE_STARTED, {
			"round_index": _round_index,
			"turn_index": _turn_index,
		})
	emit_signal("battle_started", _units)
	_transition_to(State.ROUND_START)

func stop_battle() -> void:
	_state = State.IDLE
	_turn_queue.clear()
	_current_actor = null
	_current_command = null


func _set_skill_cooldown(entity_id: int, skill_id: String, turns: int) -> void:
	if entity_id <= 0:
		return
	if skill_id == "":
		return
	if turns <= 0:
		if cooldown_by_entity.has(entity_id):
			var d_any = cooldown_by_entity.get(entity_id, {})
			if typeof(d_any) == TYPE_DICTIONARY:
				var d: Dictionary = d_any
				d.erase(skill_id)
		return
	if not cooldown_by_entity.has(entity_id):
		cooldown_by_entity[entity_id] = {}
	var any_d = cooldown_by_entity.get(entity_id, {})
	if typeof(any_d) != TYPE_DICTIONARY:
		any_d = {}
		cooldown_by_entity[entity_id] = any_d
	var cd: Dictionary = any_d
	cd[skill_id] = int(turns)


func _get_skill_cooldown(entity_id: int, skill_id: String) -> int:
	if entity_id <= 0 or skill_id == "":
		return 0
	if not cooldown_by_entity.has(entity_id):
		return 0
	var any_d = cooldown_by_entity.get(entity_id, {})
	if typeof(any_d) != TYPE_DICTIONARY:
		return 0
	var cd: Dictionary = any_d
	return int(cd.get(skill_id, 0))


func _tick_skill_cooldowns(entity_id: int) -> void:
	if entity_id <= 0:
		return
	if not cooldown_by_entity.has(entity_id):
		return
	var any_d = cooldown_by_entity.get(entity_id, {})
	if typeof(any_d) != TYPE_DICTIONARY:
		return
	var cd: Dictionary = any_d
	var keys: Array = cd.keys()
	for k_any in keys:
		var k = String(k_any)
		var v = int(cd.get(k, 0))
		if v <= 1:
			cd.erase(k)
		else:
			cd[k] = v - 1


func _choose_skill_with_cooldown(entity_id: int, preferred_skill_ids: Array, basic_skill_id: String) -> String:
	for sid_any in preferred_skill_ids:
		var sid = String(sid_any)
		if sid == "":
			continue
		if _get_skill_cooldown(entity_id, sid) <= 0:
			return sid
	return basic_skill_id


func _get_skill_cooldown_turns(skill_id: String) -> int:
	# 从 TurnSkillRuntime.SkillDB 读取 skill.cooldown_turns（扩展字段，默认为 0）
	if skill_id == "":
		return 0
	var root = Engine.get_main_loop().root
	if root == null:
		return 0
	if not root.has_node("TurnSkillRuntime"):
		return 0
	var rt = root.get_node("TurnSkillRuntime")
	if rt == null:
		return 0
	var db = rt.get("db")
	if db == null:
		return 0
	if not db.has_method("get_skill"):
		return 0
	var sr: Dictionary = db.call("get_skill", skill_id, true)
	if not bool(sr.get("ok", false)):
		return 0
	var skill: Dictionary = sr.get("skill", {})
	return int(skill.get("cooldown_turns", 0))

func get_state() -> int:
	return _state
	
func get_current_actor() -> Node:
	return _current_actor

func submit_player_command(command: TurnCommand) -> void:
	if _state != State.REQUEST_ACTION:
		push_warning("[TurnManager] Ignoring submit_player_command, not in REQUEST_ACTION state")
		return
	if not command:
		return
	_current_command = command
	emit_signal("action_committed", _current_actor, command)
	_transition_to(State.RESOLVE_ACTION)

func sync_resources_keep_ratio(actor: Node) -> void:
	if actor == null:
		return
	if _context == null:
		return
	var ds = _context.dataset
	if ds == null or not ds.has_method("stat_id"):
		return
	var stats = actor.get("stats")
	if stats == null:
		return
	if not stats.has_method("get_final") or not stats.has_method("add_base"):
		return
	var actor_id_var = actor.get("entity_id")
	if actor_id_var == null:
		return
	var actor_id = int(actor_id_var)
	if not resource_snapshot_by_entity.has(actor_id):
		resource_snapshot_by_entity[actor_id] = {}
	var snapshot_any = resource_snapshot_by_entity.get(actor_id, {})
	if typeof(snapshot_any) != TYPE_DICTIONARY:
		snapshot_any = {}
		resource_snapshot_by_entity[actor_id] = snapshot_any
	var snapshot: Dictionary = snapshot_any
	
	_sync_resource_pair_keep_ratio(stats, ds, snapshot, "HP", "MAX_HP")
	_sync_resource_pair_keep_ratio(stats, ds, snapshot, "MP", "MAX_MP")
	_sync_resource_pair_keep_ratio(stats, ds, snapshot, "RAGE", "MAX_RAGE")

func _sync_resource_pair_keep_ratio(stats: Object, ds: Object, snapshot: Dictionary, cur_name: String, max_name: String) -> void:
	var cur_id_int = int(ds.call("stat_id", cur_name))
	var max_id_int = int(ds.call("stat_id", max_name))
	if cur_id_int < 0 or max_id_int < 0:
		return
	
	var old_cur = float(stats.call("get_final", cur_id_int))
	var new_max_raw = float(stats.call("get_final", max_id_int))
	var new_max = new_max_raw
	if new_max < 0.0:
		new_max = 0.0
	
	var old_max = 0.0
	if snapshot.has(max_id_int):
		old_max = float(snapshot.get(max_id_int, 0.0))
	else:
		old_max = float(new_max)
		snapshot[max_id_int] = old_max
	
	var ratio = 0.0
	if old_max > 0.0:
		ratio = clamp(old_cur / old_max, 0.0, 1.0)
	else:
		ratio = 0.0
	
	var new_cur = floor(ratio * new_max)
	new_cur = clamp(new_cur, 0.0, new_max)
	
	var delta = new_cur - old_cur
	if delta != 0.0:
		stats.call("add_base", cur_id_int, delta)
	
	# 更新快照：记录“上一次同步时的 MAX”
	snapshot[max_id_int] = float(new_max)

func is_dead(actor: Node) -> bool:
	if actor == null:
		return true
	if actor.has_method("is_dead"):
		return bool(actor.call("is_dead"))
		
	var stats = actor.get("stats")
	if stats == null:
		push_error("[TurnManager] Unit %s missing stats component for death check" % actor.name)
		return true
		
	if _context == null or _context.dataset == null:
		push_error("[TurnManager] Missing BattleContext.dataset for death check (hp_stat_id=%s)" % hp_stat_id)
		return false
		
	var ds = _context.dataset
	if not ds.has_method("stat_id"):
		push_error("[TurnManager] dataset missing stat_id() for death check (hp_stat_id=%s)" % hp_stat_id)
		return false
	var hp_id_int = int(ds.call("stat_id", hp_stat_id))
	if hp_id_int < 0:
		push_error("[TurnManager] hp_stat_id '%s' not found in dataset" % hp_stat_id)
		return false
		
	if not stats.has_method("get_final"):
		push_error("[TurnManager] stats missing get_final() for death check (unit=%s)" % actor.name)
		return false
	var hp = float(stats.call("get_final", hp_id_int))
	return hp <= 0.0

func _transition_to(new_state: int) -> void:
	_state = new_state
	call_deferred("_advance")

func _advance() -> void:
	match _state:
		State.ROUND_START:
			_handle_round_start()
		State.TURN_START:
			_handle_turn_start()
		State.REQUEST_ACTION:
			_handle_request_action()
		State.RESOLVE_ACTION:
			_handle_resolve_action()
		State.TURN_END:
			_handle_turn_end()
		State.CHECK_END:
			_handle_check_end()
		State.BATTLE_END:
			_handle_battle_end()

func _handle_round_start() -> void:
	_build_turn_queue()
	emit_signal("round_started", _round_index, _turn_queue.duplicate())
	if _turn_queue.is_empty():
		_transition_to(State.CHECK_END)
	else:
		_current_actor = _turn_queue.pop_front()
		_transition_to(State.TURN_START)

func _handle_turn_start() -> void:
	if not is_instance_valid(_current_actor) or is_dead(_current_actor):
		_transition_to(State.CHECK_END)
		return
		
	var actor_id = int(_current_actor.get("entity_id"))
	_tick_skill_cooldowns(actor_id)
	emit_signal("turn_started", _current_actor, _turn_index)
	_context.event_bus.emit_event(EventNames.TURN_STARTED, {"turn_index": _turn_index, "actor_id": actor_id})
	
	var entity_ids_sorted = PackedInt32Array([actor_id])
	var pipeline = _context.get("pipeline")
	var ds = _context.dataset
	var replay = _context.get("replay")
	_context.turn_component.on_turn_start(
		entity_ids_sorted,
		_context.runtime_dict["buff_by_entity"],
		_context.runtime_dict["stats_by_entity"],
		pipeline,
		ds,
		replay
	)
	
	if _context.aura_manager:
		_context.aura_manager.refresh_all()
	
	sync_resources_keep_ratio(_current_actor)
		
	if is_dead(_current_actor):
		_clean_up_dead()
		_transition_to(State.CHECK_END)
	else:
		_transition_to(State.REQUEST_ACTION)

func _handle_request_action() -> void:
	emit_signal("action_requested", _current_actor, [])

func _handle_resolve_action() -> void:
	if not _current_command:
		_transition_to(State.TURN_END)
		return
		
	var actor_id = int(_current_actor.get("entity_id"))
	var skill_id = String(_current_command.skill_id)
	if _get_skill_cooldown(actor_id, skill_id) > 0:
		_context.event_bus.emit_event(EventNames.ACTION_FINISHED, {
			"turn_index": _turn_index,
			"actor_id": actor_id,
			"ok": false,
			"errors": ["cooldown_not_ready"]
		})
		sync_resources_keep_ratio(_current_actor)
		_clean_up_dead()
		_current_command = null
		_transition_to(State.TURN_END)
		return
	_context.event_bus.emit_event(EventNames.ACTION_STARTED, {
		"turn_index": _turn_index, 
		"actor_id": actor_id,
		"skill_id": skill_id
	})
	
	emit_signal("action_resolving", _current_actor, _current_command)
	
	var extra = _current_command.extra.duplicate()
	extra["grid"] = _context.grid
	extra["dataset"] = _context.dataset
	extra["enums_rt"] = _context.enums_rt
	extra["runtime_dict"] = _context.runtime_dict
	extra["turn_index"] = _turn_index
	
	var sr_script = load("res://addons/turn_skill_system/runtime/skill_runtime.gd")
	if sr_script:
		var result = sr_script.cast_to_cell(skill_id, _current_actor, _current_command.primary_cell, extra)
		_context.event_bus.emit_event(EventNames.ACTION_FINISHED, {
			"turn_index": _turn_index,
			"actor_id": actor_id,
			"ok": result.get("ok", false),
			"errors": result.get("errors", [])
		})
		if bool(result.get("ok", false)):
			var cd_turns = _get_skill_cooldown_turns(skill_id)
			if cd_turns > 0:
				_set_skill_cooldown(actor_id, skill_id, cd_turns)
	else:
		push_error("[TurnManager] SkillRuntime script not found!")
		_context.event_bus.emit_event(EventNames.ACTION_FINISHED, {
			"turn_index": _turn_index,
			"actor_id": actor_id,
			"ok": false,
			"errors": ["SkillRuntime not found"]
		})
		
	sync_resources_keep_ratio(_current_actor)
	_clean_up_dead()
	_current_command = null
	_transition_to(State.TURN_END)

func _handle_turn_end() -> void:
	if not is_instance_valid(_current_actor):
		_transition_to(State.CHECK_END)
		return
		
	var actor_id = _current_actor.get("entity_id")
	var entity_ids_sorted = PackedInt32Array([actor_id])
	var pipeline = _context.get("pipeline")
	var ds = _context.dataset
	var replay = _context.get("replay")
	
	_context.turn_component.on_turn_end(
		entity_ids_sorted,
		_context.runtime_dict["buff_by_entity"],
		_context.runtime_dict["stats_by_entity"],
		pipeline,
		ds,
		replay
	)
	
	_context.event_bus.emit_event(EventNames.TURN_ENDED, {"turn_index": _turn_index, "actor_id": actor_id})
	emit_signal("turn_ended", _current_actor, _turn_index)
	
	if _context.aura_manager:
		_context.aura_manager.refresh_all()
		
	_clean_up_dead()
	_turn_index += 1
	_transition_to(State.CHECK_END)

func _handle_check_end() -> void:
	var result = _victory_condition.check(_units, self)
	if result.get("ended", false):
		emit_signal("battle_ended", result)
		_transition_to(State.BATTLE_END)
	else:
		if _turn_queue.is_empty():
			_round_index += 1
			_transition_to(State.ROUND_START)
		else:
			_current_actor = _turn_queue.pop_front()
			_transition_to(State.TURN_START)

func _handle_battle_end() -> void:
	pass

func _build_turn_queue() -> void:
	_turn_queue.clear()
	for u in _units:
		if is_instance_valid(u) and not is_dead(u):
			_turn_queue.append(u)
			
	_turn_queue.sort_custom(_sort_units)

func _sort_units(a: Node, b: Node) -> bool:
	var speed_a = a.get_speed() if a.has_method("get_speed") else 0.0
	var speed_b = b.get_speed() if b.has_method("get_speed") else 0.0
	
	if speed_a != speed_b:
		return speed_a > speed_b
		
	var camp_a = 1 if a.get("camp") == ally_camp_name else 0
	var camp_b = 1 if b.get("camp") == ally_camp_name else 0
	if camp_a != camp_b:
		return camp_a > camp_b
		
	var stable_a = 0
	var stable_b = 0
	if stable_order_mode == "spawn_index":
		stable_a = a.get_meta("spawn_index", 0)
		stable_b = b.get_meta("spawn_index", 0)
	elif stable_order_mode == "cell":
		var cell_a = a.get("cell")
		var cell_b = b.get("cell")
		if cell_a != null and cell_b != null:
			stable_a = cell_a.x * 1000 + cell_a.y
			stable_b = cell_b.x * 1000 + cell_b.y
			
	return stable_a < stable_b

func _clean_up_dead() -> void:
	for u in _units:
		if is_instance_valid(u) and is_dead(u):
			if not u.get_meta("is_dead_processed", false):
				u.set_meta("is_dead_processed", true)
				var eid = u.get("entity_id")
				_context.event_bus.emit_event(EventNames.UNIT_DIED, {"actor_id": eid})
				
	var new_q: Array[Node] = []
	for u in _turn_queue:
		if is_instance_valid(u) and not is_dead(u):
			new_q.append(u)
	_turn_queue = new_q
