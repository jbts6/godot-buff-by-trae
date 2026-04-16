extends GutTest

## deal_damage_v1：对外稳定兼容入口（不含 is_bonus_damage 参数）

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")
const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")


func test_deal_damage_v1_should_work() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds
	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var a := TestBattle.make_entity(9801, ds, enums_rt)
	var d := TestBattle.make_entity(9802, ds, enums_rt)
	var rt := TestBattle.make_runtime([a, d])

	var ctx = pipe.deal_damage_v1(a.stats, d.stats, a.buffs, d.buffs, ds, 10.0, replay, 1, 0, rt, 0, -1, 0, 0)
	assert_not_null(ctx)

