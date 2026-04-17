extends GutTest

const SkillRuntime = preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")
const Grid = preload("res://addons/turn_skill_system/runtime/grid.gd")

class UnitNoOmni:
	extends RefCounted
	var entity_id: int
	var camp: String
	var cell: Vector2i
	func _init(eid: int, c: String, p: Vector2i) -> void:
		entity_id = eid
		camp = c
		cell = p

func test_simulate_cast_without_omnibuff_does_not_crash() -> void:
	var caster = UnitNoOmni.new(6001, "ally", Vector2i(2, 1))
	var target = UnitNoOmni.new(6002, "enemy", Vector2i(1, 1))
	var grid = Grid.new()
	grid.set_units([caster, target])
	
	# Simulate cast without dataset, enums_rt or runtime_dict
	var r = SkillRuntime.simulate_cast("act_demo_single", caster, null, {
		"grid": grid
	})
	
	# The cast should technically complete the simulation with predicted_deltas,
	# even if omnibuff is not initialized.
	assert_true(bool(r.has("ok")))
	assert_true(bool(r.get("simulation", false)))
	assert_true(r.has("predicted_deltas"))