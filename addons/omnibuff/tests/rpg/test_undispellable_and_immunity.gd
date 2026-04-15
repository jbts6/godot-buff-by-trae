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


func test_undispellable_cannot_be_dispelled_by_any_method() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7630, ds, enums_rt)

	# 挂一个不可驱散的 EXPLICIT buff
	e.buffs.apply_buff(e.stats, "buff_dispel_undispellable_atk_10", 999)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_undispellable_atk_10"), 1)

	var removed: int = int(e.buffs.dispel_by_tag(e.stats, "BUFF", true))
	assert_eq(removed, 0)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_undispellable_atk_10"), 1)

	removed = int(e.buffs.dispel_by_type(e.stats, "EXPLICIT"))
	assert_eq(removed, 0)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_undispellable_atk_10"), 1)

	removed = int(e.buffs.dispel_by_source(e.stats, 999, false))
	assert_eq(removed, 0)
	assert_eq(_count_by_id(e.buffs, ds, "buff_dispel_undispellable_atk_10"), 1)


func test_dispel_immunity_blocks_all_dispel_methods() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e = TestBattle.make_entity(7631, ds, enums_rt)

	# 目标拥有一个可被驱散的 EXPLICIT（用于 by_type），以及一个按来源拆分的 buff（用于 by_source）
	e.buffs.apply_buff(e.stats, "buff_life_replace_atk_10_2t", 111) # EXPLICIT
	e.buffs.apply_buff(e.stats, "buff_dispel_source_mark", 1001)   # EXPLICIT, BY_SOURCE_INSTANCE
	assert_true(int(e.buffs.inst_ids.size()) >= 2)

	# 设置免疫：只要 mask 非 0，就应阻止所有 dispel_*（按本轮决定）
	e.buffs.target_dispel_immunity_mask |= int(enums_rt.tag_mask(["DEBUFF"]))
	assert_true(e.buffs.target_dispel_immunity_mask != 0)

	var removed: int = int(e.buffs.dispel_by_tag(e.stats, "BUFF", true))
	assert_eq(removed, 0)

	removed = int(e.buffs.dispel_by_source(e.stats, 1001, false))
	assert_eq(removed, 0)

	removed = int(e.buffs.dispel_by_type(e.stats, "EXPLICIT"))
	assert_eq(removed, 0)

