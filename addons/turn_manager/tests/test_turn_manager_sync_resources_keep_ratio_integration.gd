extends GutTest

const TurnManager = preload("res://addons/turn_manager/runtime/turn_manager.gd")
const BattleContext = preload("res://addons/turn_manager/runtime/battle_context.gd")
const TurnCommand = preload("res://addons/turn_manager/runtime/turn_command.gd")


class DummyUnit extends Node:
	var entity_id: int = 1
	
	func is_dead() -> bool:
		return false
	
	func get_speed() -> float:
		return 1.0


class DummyEventBus extends RefCounted:
	var sequence: Array = []
	
	func _init(p_sequence: Array) -> void:
		sequence = p_sequence
	
	func emit_event(event_name: String, data: Dictionary) -> void:
		sequence.append(String(event_name))


class DummyAuraManager extends RefCounted:
	var sequence: Array = []
	
	func _init(p_sequence: Array) -> void:
		sequence = p_sequence
	
	func refresh_all() -> void:
		sequence.append("aura_refresh")


class DummyTurnComponent extends RefCounted:
	func on_turn_start(entity_ids_sorted, buff_by_entity, stats_by_entity, pipeline, ds, replay) -> void:
		pass
	
	func on_turn_end(entity_ids_sorted, buff_by_entity, stats_by_entity, pipeline, ds, replay) -> void:
		pass


class TurnManagerSpy extends TurnManager:
	var sequence: Array = []
	var last_sync_actor = null
	
	func sync_resources_keep_ratio(actor: Node) -> void:
		last_sync_actor = actor
		sequence.append("sync")
	
	func _clean_up_dead() -> void:
		sequence.append("cleanup")
	
	func _transition_to(new_state: int) -> void:
		_state = new_state
		if new_state == State.REQUEST_ACTION:
			sequence.append("to_request_action")
		elif new_state == State.TURN_END:
			sequence.append("to_turn_end")


func _index_of(seq: Array, key: String) -> int:
	for i in range(seq.size()):
		if String(seq[i]) == key:
			return i
	return -1


func test_turn_start_calls_sync_after_aura_refresh_before_request_action() -> void:
	var tm = TurnManagerSpy.new()
	
	var ctx = BattleContext.new()
	ctx.event_bus = DummyEventBus.new(tm.sequence)
	ctx.turn_component = DummyTurnComponent.new()
	ctx.aura_manager = DummyAuraManager.new(tm.sequence)
	
	# 只要能跑通 _handle_turn_start 即可；此测试关注调用顺序，不依赖具体 dataset/grid。
	ctx.dataset = RefCounted.new()
	ctx.enums_rt = RefCounted.new()
	ctx.omnibuff_adapter = RefCounted.new()
	
	tm._context = ctx
	tm._current_actor = DummyUnit.new()
	tm._turn_index = 1
	
	tm._handle_turn_start()
	
	var i_aura = _index_of(tm.sequence, "aura_refresh")
	assert_true(i_aura >= 0, "应在 turn_start 中触发 aura_manager.refresh_all()")
	if i_aura < 0:
		tm.free()
		return
	
	var i_sync = _index_of(tm.sequence, "sync")
	assert_true(i_sync > i_aura, "sync_resources_keep_ratio 应在 refresh_all() 之后调用")
	if i_sync <= i_aura:
		tm.free()
		return
	
	var i_req = _index_of(tm.sequence, "to_request_action")
	assert_true(i_req > i_sync, "sync_resources_keep_ratio 应在进入 REQUEST_ACTION 之前调用")
	assert_eq(tm.last_sync_actor, tm._current_actor, "sync_resources_keep_ratio 应仅对当前行动者调用")
	
	tm._current_actor.free()
	tm.free()


func test_resolve_action_calls_sync_after_action_finished_before_cleanup_dead() -> void:
	var tm = TurnManagerSpy.new()
	
	var ctx = BattleContext.new()
	ctx.event_bus = DummyEventBus.new(tm.sequence)
	ctx.turn_component = DummyTurnComponent.new()
	
	# cast_to_cell 会走 SkillRuntime 的“最小构造”路径；这里提供占位对象即可。
	ctx.grid = RefCounted.new()
	ctx.dataset = RefCounted.new()
	ctx.enums_rt = RefCounted.new()
	ctx.runtime_dict = {"stats_by_entity": {}, "buff_by_entity": {}}
	
	tm._context = ctx
	tm._current_actor = DummyUnit.new()
	tm._turn_index = 1
	tm._current_command = TurnCommand.new("nonexistent_skill_id_for_test", Vector2i(0, 0))
	
	tm._handle_resolve_action()
	
	var i_finished = _index_of(tm.sequence, "action_finished")
	assert_true(i_finished >= 0, "应在 resolve_action 中 emit ACTION_FINISHED")
	if i_finished < 0:
		tm._current_actor.free()
		tm.free()
		return
	
	var i_sync = _index_of(tm.sequence, "sync")
	assert_true(i_sync > i_finished, "sync_resources_keep_ratio 应在 ACTION_FINISHED 之后调用")
	if i_sync <= i_finished:
		tm._current_actor.free()
		tm.free()
		return
	
	var i_cleanup = _index_of(tm.sequence, "cleanup")
	assert_true(i_cleanup > i_sync, "sync_resources_keep_ratio 应在 _clean_up_dead() 之前调用")
	assert_eq(tm.last_sync_actor, tm._current_actor, "sync_resources_keep_ratio 应仅对当前行动者调用")
	
	tm._current_actor.free()
	tm.free()

