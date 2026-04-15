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


func test_dispel_by_type_explicit_only() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7620, ds, enums_rt)

	var atk_id := ds.stat_id("ATK")

	# 3 个不同类型的 buff
	e.buffs.apply_buff(e.stats, "buff_life_replace_atk_10_2t", 1)   # EXPLICIT
	e.buffs.apply_buff(e.stats, "buff_dispel_implicit_atk_10", 1)   # IMPLICIT
	e.buffs.apply_buff(e.stats, "buff_dispel_passive_atk_10", 1)    # PASSIVE

	assert_eq(int(e.buffs.inst_ids.size()), 3)
	assert_eq(_count_by_id(e.buffs, ds, "buff_life_replace_atk_10_2t"), 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_implicit_atk_10"), 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_passive_atk_10"), 1)
	assert_eq(float(e.stats.get_final(atk_id)), 40.0) # 10 + 10*3

	var removed: int = int(e.buffs.dispel_by_type(e.stats, "EXPLICIT"))
	assert_eq(removed, 1)

	assert_eq(int(e.buffs.inst_ids.size()), 2)
	assert_eq(_count_by_id(e.buffs, ds, "buff_life_replace_atk_10_2t"), 0)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_implicit_atk_10"), 1)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_passive_atk_10"), 1)
	assert_eq(float(e.stats.get_final(atk_id)), 30.0) # 10 + 10*2

