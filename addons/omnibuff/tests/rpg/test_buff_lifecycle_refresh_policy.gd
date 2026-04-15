extends GutTest

const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_refresh_policy_none_does_not_reset_remaining_turns() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var pipe = OmniDamagePipeline.new()
	var turn = OmniTurnComponent.new()

	var eid = 7301
	var e = TestBattle.make_entity(eid, ds, enums_rt)
	var runtime = TestBattle.make_runtime([e])
	var ids = PackedInt32Array([eid])
	ids.sort()

	# 第一次施加：turns=2
	e.buffs.apply_buff(e.stats, "buff_life_stack_atk_10_2t_max3_none", 111)
	var inst_id = int(e.buffs.inst_ids[0])
	assert_eq(int(e.buffs.instances_by_id[inst_id].remaining_turns), 2)

	# Turn1 end：2->1
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null)
	assert_eq(int(e.buffs.instances_by_id[inst_id].remaining_turns), 1)

	# 再次施加（ADD_STACK 命中已有实例）：
	# refresh_policy=NONE => remaining_turns 仍应为 1（不重置到2）
	e.buffs.apply_buff(e.stats, "buff_life_stack_atk_10_2t_max3_none", 111)
	assert_eq(int(e.buffs.instances_by_id[inst_id].remaining_turns), 1)


func test_refresh_policy_reset_to_max_resets_remaining_turns() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var pipe = OmniDamagePipeline.new()
	var turn = OmniTurnComponent.new()

	var eid = 7302
	var e = TestBattle.make_entity(eid, ds, enums_rt)
	var runtime = TestBattle.make_runtime([e])
	var ids = PackedInt32Array([eid])
	ids.sort()

	# refresh_policy=RESET_TO_MAX
	e.buffs.apply_buff(e.stats, "buff_life_stack_atk_10_2t_max3", 111)
	var inst_id = int(e.buffs.inst_ids[0])

	# 2->1
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null)
	assert_eq(int(e.buffs.instances_by_id[inst_id].remaining_turns), 1)

	# 命中已有实例，应重置回2
	e.buffs.apply_buff(e.stats, "buff_life_stack_atk_10_2t_max3", 111)
	assert_eq(int(e.buffs.instances_by_id[inst_id].remaining_turns), 2)
