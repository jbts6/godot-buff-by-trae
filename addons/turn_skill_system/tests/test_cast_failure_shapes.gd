extends GutTest

const SkillRuntime = preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")
const Grid = preload("res://addons/turn_skill_system/runtime/grid.gd")

class U:
	extends RefCounted
	var entity_id: int = 1
	var camp: String = "ally"
	var cell: Vector2i = Vector2i(2, 1)
	var stats = null
	var buffs = null

func _assert_shape(r: Dictionary) -> void:
	assert_true(r.has("ok"), "missing 'ok'")
	assert_true(r.has("simulation"), "missing 'simulation'")
	assert_true(r.has("skill_id"), "missing 'skill_id'")
	assert_true(r.has("caster_id"), "missing 'caster_id'")
	assert_true(r.has("targets"), "missing 'targets'")
	assert_true(r.has("effects"), "missing 'effects'")
	assert_true(r.has("events"), "missing 'events'")
	assert_true(r.has("resolved_formulas"), "missing 'resolved_formulas'")
	assert_true(r.has("rng_seed"), "missing 'rng_seed'")
	assert_true(r.has("errors"), "missing 'errors'")
	assert_true(r.has("issues"), "missing 'issues'")
	assert_true(r.has("predicted_deltas"), "missing 'predicted_deltas'")

func test_fail_unknown_skill_id_shape() -> void:
	var grid = Grid.new()
	var caster = U.new()
	grid.set_units([caster])

	var r = SkillRuntime.simulate_cast("__missing__", caster, null, {"grid": grid})
	assert_false(bool(r.get("ok", true)))
	_assert_shape(r)
	assert_true(r.get("errors", []).size() >= 1)
