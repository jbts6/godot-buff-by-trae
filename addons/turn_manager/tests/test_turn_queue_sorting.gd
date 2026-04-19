extends GutTest

const TurnManager = preload("res://addons/turn_manager/runtime/turn_manager.gd")

class DummyUnit extends Node:
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var speed: float
	
	func _init(p_id: int, p_camp: String, p_cell: Vector2i, p_speed: float) -> void:
		entity_id = p_id
		camp = p_camp
		cell = p_cell
		speed = p_speed
		
	func get_speed() -> float:
		return speed
		
	func is_dead() -> bool:
		return false

func test_sorting_by_speed() -> void:
	var u1 = DummyUnit.new(1, "ally", Vector2i(0, 0), 10.0)
	var u2 = DummyUnit.new(2, "enemy", Vector2i(1, 0), 20.0)
	var u3 = DummyUnit.new(3, "ally", Vector2i(2, 0), 15.0)
	
	var tm = TurnManager.new()
	tm.stable_order_mode = "cell"
	tm._units = [u1, u2, u3]
	tm._build_turn_queue()
	
	assert_eq(tm._turn_queue[0], u2, "Highest speed should be first")
	assert_eq(tm._turn_queue[1], u3)
	assert_eq(tm._turn_queue[2], u1)
	
	u1.free()
	u2.free()
	u3.free()
	tm.free()

func test_sorting_by_camp_priority() -> void:
	var u1 = DummyUnit.new(1, "enemy", Vector2i(0, 0), 10.0)
	var u2 = DummyUnit.new(2, "ally", Vector2i(1, 0), 10.0)
	
	var tm = TurnManager.new()
	tm.ally_camp_name = "ally"
	tm._units = [u1, u2]
	tm._build_turn_queue()
	
	assert_eq(tm._turn_queue[0], u2, "Ally should go first if speed is tied")
	assert_eq(tm._turn_queue[1], u1)
	
	u1.free()
	u2.free()
	tm.free()

func test_stable_sorting_by_spawn_index() -> void:
	var u1 = DummyUnit.new(1, "ally", Vector2i(0, 0), 10.0)
	u1.set_meta("spawn_index", 1)
	var u2 = DummyUnit.new(2, "ally", Vector2i(1, 0), 10.0)
	u2.set_meta("spawn_index", 0)
	
	var tm = TurnManager.new()
	tm.stable_order_mode = "spawn_index"
	tm._units = [u1, u2]
	tm._build_turn_queue()
	
	assert_eq(tm._turn_queue[0], u2, "Lower spawn_index should go first")
	assert_eq(tm._turn_queue[1], u1)
	
	u1.free()
	u2.free()
	tm.free()
