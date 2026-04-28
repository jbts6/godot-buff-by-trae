extends GutTest

const Formula = preload("res://addons/turn_skill_system/runtime/formula.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")

class UnitWithOmni:
	extends RefCounted
	var entity_id: int
	var stats
	var buffs
	func _init(eid: int, s, b) -> void:
		entity_id = eid
		stats = s
		buffs = b

func test_formula_auto_resolves_atk_from_dataset() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds = loaded.ds
	var enums_rt = loaded.enums_rt

	var a_stats = OmniStatsComponent.new(1001, ds)
	var t_stats = OmniStatsComponent.new(1002, ds)
	var a_buffs = OmniBuffCore.new(ds, enums_rt)
	var t_buffs = OmniBuffCore.new(ds, enums_rt)

	var caster = UnitWithOmni.new(1001, a_stats, a_buffs)
	var target = UnitWithOmni.new(1002, t_stats, t_buffs)

	var ctx := {
		"caster": caster,
		"target": target,
		"dataset": ds,
		"a_stats": {},
		"t_stats": {},
	}

	var r = Formula.eval_expr("a.ATK + 10", ctx)
	assert_true(bool(r.get("ok", false)))
	var atk_id = int(ds.stat_id("ATK"))
	var expected_atk = float(a_stats.get_final(atk_id))
	assert_eq(float(r.get("value", -1.0)), floor(expected_atk + 10.0))

func test_formula_auto_resolves_t_def_from_dataset() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds = loaded.ds
	var enums_rt = loaded.enums_rt

	var a_stats = OmniStatsComponent.new(2001, ds)
	var t_stats = OmniStatsComponent.new(2002, ds)
	var a_buffs = OmniBuffCore.new(ds, enums_rt)
	var t_buffs = OmniBuffCore.new(ds, enums_rt)

	var caster = UnitWithOmni.new(2001, a_stats, a_buffs)
	var target = UnitWithOmni.new(2002, t_stats, t_buffs)

	var ctx := {
		"caster": caster,
		"target": target,
		"dataset": ds,
		"a_stats": {},
		"t_stats": {},
	}

	var r = Formula.eval_expr("t.DEF", ctx)
	assert_true(bool(r.get("ok", false)))
	var def_id = int(ds.stat_id("DEF"))
	var expected_def = float(t_stats.get_final(def_id))
	assert_eq(float(r.get("value", -1.0)), floor(expected_def))

func test_formula_a_stats_dict_takes_priority() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds = loaded.ds
	var enums_rt = loaded.enums_rt

	var a_stats = OmniStatsComponent.new(3001, ds)
	var t_stats = OmniStatsComponent.new(3002, ds)
	var a_buffs = OmniBuffCore.new(ds, enums_rt)
	var t_buffs = OmniBuffCore.new(ds, enums_rt)

	var caster = UnitWithOmni.new(3001, a_stats, a_buffs)
	var target = UnitWithOmni.new(3002, t_stats, t_buffs)

	var ctx := {
		"caster": caster,
		"target": target,
		"dataset": ds,
		"a_stats": {"ATK": 999.0},
		"t_stats": {},
	}

	var r = Formula.eval_expr("a.ATK", ctx)
	assert_true(bool(r.get("ok", false)))
	assert_eq(float(r.get("value", -1.0)), 999.0)

func test_formula_no_dataset_returns_zero() -> void:
	var ctx := {
		"caster": null,
		"target": null,
		"a_stats": {},
		"t_stats": {},
	}

	var r = Formula.eval_expr("a.ATK", ctx)
	assert_true(bool(r.get("ok", false)))
	assert_eq(float(r.get("value", -1.0)), 0.0)

func test_formula_unknown_stat_returns_zero() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds = loaded.ds
	var enums_rt = loaded.enums_rt

	var a_stats = OmniStatsComponent.new(4001, ds)
	var a_buffs = OmniBuffCore.new(ds, enums_rt)
	var caster = UnitWithOmni.new(4001, a_stats, a_buffs)

	var ctx := {
		"caster": caster,
		"target": null,
		"dataset": ds,
		"a_stats": {},
		"t_stats": {},
	}

	var r = Formula.eval_expr("a.NONEXISTENT_STAT", ctx)
	assert_true(bool(r.get("ok", false)))
	assert_eq(float(r.get("value", -1.0)), 0.0)
