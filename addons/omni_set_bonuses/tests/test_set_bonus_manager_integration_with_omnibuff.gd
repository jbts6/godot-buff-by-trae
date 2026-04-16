extends GutTest

const SBM = preload("res://addons/omni_set_bonuses/runtime/set_bonus_manager.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_set_bonuses_apply_and_remove_affect_stats() -> void:
	var loaded: Dictionary = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var e: Dictionary = TestBattle.make_entity(9901, ds, enums_rt)
	var atk_id: int = int(ds.stat_id("ATK"))
	assert_true(atk_id >= 0)

	# baseline: ATK=10 (rpg_tests default)
	assert_true(is_equal_approx(float(e.stats.get_final(atk_id)), 10.0))

	var set_defs: Dictionary = {"dragon": {2: "set_dragon_2pc", 4: "set_dragon_4pc"}}
	var items2: Array = [
		{"item_id": "x1", "set_id": "dragon"},
		{"item_id": "x2", "set_id": "dragon"}
	]
	var items4: Array = [
		{"item_id": "x1", "set_id": "dragon"},
		{"item_id": "x2", "set_id": "dragon"},
		{"item_id": "x3", "set_id": "dragon"},
		{"item_id": "x4", "set_id": "dragon"}
	]
	var items0: Array = []

	var mgr := SBM.new()

	# 2pc: * (1 + 0.10)
	mgr.refresh_entity(e.stats, e.buffs, items2, set_defs, int(e.stats.entity_id))
	assert_true(is_equal_approx(float(e.stats.get_final(atk_id)), 10.0 * 1.10))

	# 4pc: * (1 + 0.10) * (1 + 0.20)
	mgr.refresh_entity(e.stats, e.buffs, items4, set_defs, int(e.stats.entity_id))
	assert_true(is_equal_approx(float(e.stats.get_final(atk_id)), 10.0 * 1.10 * 1.20))

	# remove all
	mgr.refresh_entity(e.stats, e.buffs, items0, set_defs, int(e.stats.entity_id))
	assert_true(is_equal_approx(float(e.stats.get_final(atk_id)), 10.0))

