extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _count_by_id(buffs: OmniBuffCore, ds: OmniCompiledDataset, buff_id_str: String) -> int:
	var n := 0
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		if String(ds.buff_defs[int(inst.buff_def_id)].get("id", "")) == buff_id_str:
			n += 1
	return n


func test_replace_global_keeps_one_instance() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var e := TestBattle.make_entity(7101, ds, enums_rt)
	e.buffs.apply_buff(e.stats, "buff_life_replace_atk_10_2t", 111)
	e.buffs.apply_buff(e.stats, "buff_life_replace_atk_10_2t", 222)
	assert_eq(_count_by_id(e.buffs, ds, "buff_life_replace_atk_10_2t"), 1)


func test_add_stack_global_increases_stacks_and_caps() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var e := TestBattle.make_entity(7102, ds, enums_rt)
	for i in range(5):
		e.buffs.apply_buff(e.stats, "buff_life_stack_atk_10_2t_max3", 111)
	assert_eq(_count_by_id(e.buffs, ds, "buff_life_stack_atk_10_2t_max3"), 1)
	# stacks 应被 cap 到 3
	var inst_id := int(e.buffs.inst_ids[0])
	var inst = e.buffs.instances_by_id[inst_id]
	assert_eq(int(inst.stacks), 3)
	# ATK: (10 base + 10*3) = 40
	assert_eq(float(e.stats.get_final(ds.stat_id("ATK"))), 40.0)


func test_multi_instance_creates_three_instances() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var e := TestBattle.make_entity(7103, ds, enums_rt)
	for i in range(3):
		e.buffs.apply_buff(e.stats, "buff_life_multi_atk_10_2t", 111)
	assert_eq(_count_by_id(e.buffs, ds, "buff_life_multi_atk_10_2t"), 3)
	# ATK: (10 base + 10*3) = 40
	assert_eq(float(e.stats.get_final(ds.stat_id("ATK"))), 40.0)


func test_add_stack_by_source_creates_two_owner_instances() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt

	var e := TestBattle.make_entity(7104, ds, enums_rt)
	# source 1001 叠两层（max2）
	e.buffs.apply_buff(e.stats, "buff_life_stack_by_source_def_5_2t_max2", 1001)
	e.buffs.apply_buff(e.stats, "buff_life_stack_by_source_def_5_2t_max2", 1001)
	# source 2002 叠一层
	e.buffs.apply_buff(e.stats, "buff_life_stack_by_source_def_5_2t_max2", 2002)

	# 期望：存在 2 个实例（按来源拆分），DEF = 5 base + (5*2 + 5*1) = 20
	assert_eq(_count_by_id(e.buffs, ds, "buff_life_stack_by_source_def_5_2t_max2"), 2)
	assert_eq(float(e.stats.get_final(ds.stat_id("DEF"))), 20.0)
