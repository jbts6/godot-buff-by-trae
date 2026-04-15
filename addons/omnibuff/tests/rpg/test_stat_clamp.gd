extends GutTest

## 用例：Stat clamp（C plan / rpg_tests fixtures）
##
## 目标：
## - 使用 rpg_tests fixture `buff_c_add_hit_plus_2` 将 HIT_RATE 推到 > 1
## - 断言 get_final(HIT_RATE) == 1.0（clamp 生效）
##
## 备注：避免使用 `:=`，以规避 GDScript 推断相关问题。

const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_hit_rate_is_clamped_to_one() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var e = TestBattle.make_entity(7101, ds, enums_rt)
	var hit_id = ds.stat_id("HIT_RATE")
	assert_true(hit_id >= 0)

	# baseline：HIT_RATE 默认=1.0
	assert_eq(e.stats.get_final(hit_id), 1.0)

	# ADD/FLAT：HIT_RATE +2 -> 应被 clamp 到 max=1.0
	var inst_id = e.buffs.apply_buff(e.stats, "buff_c_add_hit_plus_2", 7101)
	assert_true(inst_id > 0)
	assert_eq(e.stats.get_final(hit_id), 1.0)

