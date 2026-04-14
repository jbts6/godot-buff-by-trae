extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_turns_buff_expires_on_turn_end() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var pipe := OmniDamagePipeline.new()
	var turn := OmniTurnComponent.new()

	var eid := 7201
	var e := TestBattle.make_entity(eid, ds, enums_rt)
	var runtime := TestBattle.make_runtime([e])
	var ids := PackedInt32Array([eid])
	ids.sort()

	e.buffs.apply_buff(e.stats, "buff_life_replace_atk_10_2t", 111)
	assert_eq(float(e.stats.get_final(ds.stat_id("ATK"))), 20.0)

	# Turn1 end：remaining_turns 2->1，仍有效
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null)
	assert_eq(float(e.stats.get_final(ds.stat_id("ATK"))), 20.0)

	# Turn2 end：remaining_turns 1->0，到期移除
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null)
	assert_eq(float(e.stats.get_final(ds.stat_id("ATK"))), 10.0)

