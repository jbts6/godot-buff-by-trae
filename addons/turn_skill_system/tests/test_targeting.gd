extends GutTest

const Grid := preload("res://addons/turn_skill_system/runtime/grid.gd")
const TargetingRegistry := preload("res://addons/turn_skill_system/runtime/targeting/targeting_registry.gd")


class FakeUnit:
	extends RefCounted
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var stats = null
	var buffs = null
	func _init(eid: int, c: String, p: Vector2i) -> void:
		entity_id = eid
		camp = c
		cell = p


func test_targeting_first_picks_sorted_first_enemy() -> void:
	var caster := FakeUnit.new(1, "ally", Vector2i(2, 2))
	var e1 := FakeUnit.new(2, "enemy", Vector2i(1, 2))
	var e2 := FakeUnit.new(3, "enemy", Vector2i(0, 1))
	var grid := Grid.new()
	grid.set_units([caster, e1, e2])

	var tr := TargetingRegistry.new()
	tr.register_defaults()

	var skill := {"targeting": "FIRST"}
	var targets := tr.resolve(skill, caster, null, grid, {})
	assert_eq(targets.size(), 1)
	assert_eq(int(targets[0].get("unit_id", -1)), 3) # (0,1) should be first by row/col


func test_targeting_cross_returns_units_in_cross() -> void:
	var caster := FakeUnit.new(1, "ally", Vector2i(2, 2))
	var u_center := FakeUnit.new(2, "enemy", Vector2i(1, 1))
	var u_up := FakeUnit.new(3, "enemy", Vector2i(0, 1))
	var u_left := FakeUnit.new(4, "enemy", Vector2i(1, 0))
	var u_diag := FakeUnit.new(5, "enemy", Vector2i(0, 0))
	var grid := Grid.new()
	grid.set_units([caster, u_center, u_up, u_left, u_diag])

	var tr := TargetingRegistry.new()
	tr.register_defaults()

	var skill := {"targeting": {"rule": "cross"}}
	var targets := tr.resolve(skill, caster, Vector2i(1, 1), grid, {})
	var ids: Array[int] = []
	for t in targets:
		ids.append(int(t.get("unit_id", -1)))
	assert_true(ids.has(2))
	assert_true(ids.has(3))
	assert_true(ids.has(4))
	assert_false(ids.has(5)) # diagonal not included

