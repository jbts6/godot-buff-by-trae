extends GutTest

const AllEnemiesTargeting := preload("res://addons/turn_skill_system/runtime/targeting/all_enemies_targeting.gd")
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


func test_all_enemies_targeting_compiles_and_runs() -> void:
	# 若 all_enemies_targeting.gd 存在解析期类型推断错误，本测试会在 preload 阶段直接失败（RED）。
	var caster = FakeUnit.new(1, "ally", Vector2i(2, 2))
	var e1 = FakeUnit.new(2, "enemy", Vector2i(0, 0))
	var e2 = FakeUnit.new(3, "enemy", Vector2i(1, 1))
	var grid = Grid.new()
	grid.set_units([caster, e1, e2])

	var rule = AllEnemiesTargeting.new()
	var targets = rule.resolve({"targeting":"ALL"}, caster, null, grid, {})
	assert_eq(targets.size(), 2)

