extends GutTest

const TurnManager = preload("res://addons/turn_manager/runtime/turn_manager.gd")
const BattleContext = preload("res://addons/turn_manager/runtime/battle_context.gd")
const TurnCommand = preload("res://addons/turn_manager/runtime/turn_command.gd")

class DummyUnit extends Node:
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var speed: float
		
	func get_speed() -> float:
		return speed
		
	func is_dead() -> bool:
		return false

func create_unit(p_id: int, p_camp: String, p_cell: Vector2i, p_speed: float) -> DummyUnit:
	var u = DummyUnit.new()
	u.entity_id = p_id
	u.camp = p_camp
	u.cell = p_cell
	u.speed = p_speed
	return u

class DummyEventBus:
	var events = []
	func emit_event(event_name: String, data: Dictionary) -> void:
		events.append({"name": event_name, "data": data})

class DummyTurnComponent:
	func on_turn_start(entity_ids_sorted, buff_by_entity, stats_by_entity, pipeline, ds, replay) -> void:
		pass
	func on_turn_end(entity_ids_sorted, buff_by_entity, stats_by_entity, pipeline, ds, replay) -> void:
		pass

class DummyGrid:
	func set_units(units: Array[Node]) -> void:
		pass

func test_event_sequence() -> void:
	var tm = TurnManager.new()
	var ctx = BattleContext.new()
	
	ctx.event_bus = DummyEventBus.new()
	ctx.turn_component = DummyTurnComponent.new()
	ctx.grid = DummyGrid.new()
	ctx.dataset = Resource.new()
	ctx.enums_rt = Resource.new()
	ctx.omnibuff_adapter = RefCounted.new()
	
	var u1 = create_unit(1, "ally", Vector2i(0, 0), 10.0)
	var u2 = create_unit(2, "enemy", Vector2i(1, 0), 10.0)
	
	var units: Array[Node] = []
	units.assign([u1, u2])
	tm.setup(ctx, units)
	tm.start_battle()
	
	# Wait for state machine to advance to REQUEST_ACTION
	await get_tree().process_frame
	await get_tree().process_frame
	
	# After start_battle, state should be REQUEST_ACTION for u1
	assert_eq(tm.get_state(), TurnManager.State.REQUEST_ACTION)
	
	# Submit command
	var cmd = TurnCommand.new("dummy_skill", Vector2i(1, 0))
	tm.submit_player_command(cmd)
	
	# Wait for state to change or advance manually if not deferred. 
	# Wait, _advance is called via call_deferred, so we need to yield
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Now check event bus
	var event_names = []
	for e in ctx.event_bus.events:
		event_names.append(e.name)
		
	# EventNames.TURN_STARTED, ACTION_STARTED, ACTION_FINISHED, TURN_ENDED
	assert_true("turn_started" in event_names, "Should emit turn_started")
	assert_true("action_started" in event_names, "Should emit action_started")
	assert_true("action_finished" in event_names, "Should emit action_finished")
	assert_true("turn_ended" in event_names, "Should emit turn_ended")
	
	u1.free()
	u2.free()
	tm.free()
