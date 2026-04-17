extends GutTest

const SkillRuntime := preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")
const Grid := preload("res://addons/turn_skill_system/runtime/grid.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")


class UnitWithOmni:
	extends RefCounted
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var stats
	var buffs
	func _init(eid: int, c: String, p: Vector2i, s, b) -> void:
		entity_id = eid
		camp = c
		cell = p
		stats = s
		buffs = b


func test_cast_uses_omnibuff_damage_pipeline() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt = loaded.enums_rt
	var ds = loaded.ds

	var a_stats := OmniStatsComponent.new(3001, ds)
	var d_stats := OmniStatsComponent.new(3002, ds)
	var a_buffs := OmniBuffCore.new(ds, enums_rt)
	var d_buffs := OmniBuffCore.new(ds, enums_rt)

	var caster := UnitWithOmni.new(3001, "ally", Vector2i(2, 1), a_stats, a_buffs)
	var defender := UnitWithOmni.new(3002, "enemy", Vector2i(0, 1), d_stats, d_buffs)

	var grid := Grid.new()
	grid.set_units([caster, defender])

	var runtime_dict := {
		"stats_by_entity": {3001: a_stats, 3002: d_stats},
		"buff_by_entity": {3001: a_buffs, 3002: d_buffs},
	}

	var r := SkillRuntime.cast("act_demo_single", caster, null, {
		"grid": grid,
		"dataset": ds,
		"enums_rt": enums_rt,
		"runtime_dict": runtime_dict,
		"turn_index": 1,
		"a_stats": {"ATK": 100},
	})

	var ok := bool(r.get("ok", false))
	assert_true(ok)
	if not ok:
		print("[debug] cast failed: ", r)
		return
	var effects: Array = r.get("effects", [])
	assert_true(effects.size() >= 1)
	if effects.is_empty():
		print("[debug] effects empty: ", r)
		return
	assert_eq(String(effects[0].get("kind", "")), "damage")
	assert_true(float(effects[0].get("value", 0)) > 0.0)
