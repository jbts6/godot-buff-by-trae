extends GutTest

const SkillRuntime := preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")
const Grid := preload("res://addons/turn_skill_system/runtime/grid.gd")


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


func test_skill_runtime_simulate_cast_compiles_and_runs() -> void:
	var caster := FakeUnit.new(100, "ally", Vector2i(2, 1))
	var enemy := FakeUnit.new(200, "enemy", Vector2i(0, 1))
	var grid := Grid.new()
	grid.set_units([caster, enemy])

	# 若 SkillRuntime.gd 存在语法/类型推断错误，本测试会在加载阶段直接失败（RED）。
	var sim := SkillRuntime.simulate_cast("act_demo_single", caster, null, {
		"grid": grid,
		"a_stats": {"ATK": 100},
	})
	assert_true(bool(sim.get("ok", false)))
