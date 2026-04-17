extends GutTest

## Phase 2：曲线（curves）最小覆盖

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_phase2_curve_dr_softcap_expected_value() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e := TestBattle.make_entity(12002, ds, enums_rt)

	var sid := int(ds.stat_id("DMG_REDUCE_RATING"))
	assert_true(sid >= 0)

	# rpg_tests/stat_defs.json: DR_SOFTCAP with k=100, apply_at=POST_FINAL
	# f(100)=100/(100+100)=0.5
	e["stats"].add_base(sid, 100.0)
	var v := float(e["stats"].get_final(sid))
	assert_true(is_equal_approx(v, 0.5, 0.0001), "expect 0.5, got=%s" % [v])


func test_phase2_curve_dr_softcap_is_monotonic() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e := TestBattle.make_entity(12003, ds, enums_rt)

	var sid := int(ds.stat_id("DMG_REDUCE_RATING"))
	assert_true(sid >= 0)

	e["stats"].add_base(sid, 10.0)
	var v1 := float(e["stats"].get_final(sid))
	e["stats"].add_base(sid, 10.0)
	var v2 := float(e["stats"].get_final(sid))
	assert_true(v2 >= v1, "DR curve should be monotonic non-decreasing")

