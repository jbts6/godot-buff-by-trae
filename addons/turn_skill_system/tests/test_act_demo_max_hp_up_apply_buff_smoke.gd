extends GutTest

const SkillRuntime = preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")
const Grid = preload("res://addons/turn_skill_system/runtime/grid.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")


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

	func is_dead() -> bool:
		return false


func test_act_demo_max_hp_up_applies_buff_and_increases_max_hp() -> void:
	# 目的：冒烟锁定链路：
	# SkillRuntime.cast_to_cell -> apply_buff effect -> OmniBuffAdapter.apply_buff -> BuffCore -> stats.get_final(MAX_HP) 改变
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt = loaded.enums_rt
	var ds = loaded.ds

	var a_stats = OmniStatsComponent.new(5001, ds)
	var a_buffs = OmniBuffCore.new(ds, enums_rt)
	var caster = UnitWithOmni.new(5001, "ally", Vector2i(2, 1), a_stats, a_buffs)

	var grid = Grid.new()
	grid.set_units([caster])

	var runtime_dict = {
		"stats_by_entity": {5001: a_stats},
		"buff_by_entity": {5001: a_buffs},
	}

	var max_hp_id = int(ds.stat_id("MAX_HP"))
	assert_true(max_hp_id >= 0)
	if max_hp_id < 0:
		return
	var max_hp_before = float(a_stats.get_final(max_hp_id))

	var r = SkillRuntime.cast_to_cell("act_demo_max_hp_up", caster, caster.cell, {
		"grid": grid,
		"dataset": ds,
		"enums_rt": enums_rt,
		"runtime_dict": runtime_dict,
		"turn_index": 1
	})

	var ok = bool(r.get("ok", false))
	if not ok:
		print("[debug] cast failed: ", r)
	assert_true(ok)
	if not ok:
		return

	var max_hp_after = float(a_stats.get_final(max_hp_id))
	assert_true(max_hp_after > max_hp_before, "MAX_HP should increase after applying buff")

