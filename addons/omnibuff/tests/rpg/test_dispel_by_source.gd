extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _count(buffs: OmniBuffCore, ds: OmniCompiledDataset, buff_id_str: String) -> int:
	var n := 0
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		if String(ds.buff_defs[int(inst.buff_def_id)].get("id", "")) == buff_id_str:
			n += 1
	return n


func test_dispel_by_source_removes_only_that_source() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7610, ds, enums_rt)

	# 同一个 buff_id，来源 1001 与 2002 各施加一次
	e.buffs.apply_buff(e.stats, "buff_dispel_source_mark", 1001)
	e.buffs.apply_buff(e.stats, "buff_dispel_source_mark", 2002)
	assert_eq(_count(e.buffs, ds, "buff_dispel_source_mark"), 2)

	var def_id := ds.stat_id("DEF")
	assert_eq(float(e.stats.get_final(def_id)), 5.0 + 5.0 + 5.0)

	# 仅驱散来源 1001：应只移除该来源实例，且 DEF 数值回退 5
	var removed: int = int(e.buffs.dispel_by_source(e.stats, 1001, false))
	assert_eq(removed, 1)
	assert_eq(_count(e.buffs, ds, "buff_dispel_source_mark"), 1)
	assert_eq(float(e.stats.get_final(def_id)), 5.0 + 5.0)

