extends GutTest

## Phase 2：派生/转换属性 + bucket 顺序（最小覆盖）

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_phase2_linear_derived_str_to_max_hp_and_breakdown() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e := TestBattle.make_entity(12001, ds, enums_rt)

	var max_hp := int(ds.stat_id("MAX_HP"))
	var str := int(ds.stat_id("STR"))
	assert_true(max_hp >= 0 and str >= 0)

	# rpg_tests/stat_defs.json: MAX_HP has derived LINEAR from STR ratio=20
	var max_hp0 := float(e["stats"].get_final(max_hp))
	assert_true(max_hp0 >= 0.0)

	e["stats"].add_base(str, 5.0) # STR += 5 -> MAX_HP should increase by 5*20
	var max_hp1 := float(e["stats"].get_final(max_hp))
	assert_true(max_hp1 > max_hp0, "MAX_HP should increase after STR changes via derived")

	var bd: Dictionary = e["stats"].get_breakdown(max_hp)
	assert_true(bd.has("base") and bd.has("bonus") and bd.has("final"))
	assert_true(is_equal_approx(float(bd["final"]), max_hp1))
	assert_true(is_equal_approx(float(bd["bonus"]), float(bd["final"]) - float(bd["base"])))
