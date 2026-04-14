extends GutTest

## 用例：op=MUL phase=PERCENT 的 modifier 应按 (base+flat)*(1+pct) 生效
##
## 目的：
## - 覆盖 RPG 测试数据集中的 `buff_atk_pct_5`（ATK +5%）
## - 确保与现有 ADD/FLAT 行为兼容，不回归

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_mul_percent_modifier_applies_after_flat() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var e := TestBattle.make_entity(3001, ds, enums_rt)
	var atk_id := ds.stat_id("ATK")
	assert_true(atk_id >= 0)

	# baseline：ATK 默认=10
	assert_eq(e.stats.get_final(atk_id), 10.0)

	# 仅百分比：10 * 1.05
	e.buffs.apply_buff(e.stats, "buff_atk_pct_5", 3001)
	assert_true(is_equal_approx(e.stats.get_final(atk_id), 10.0 * 1.05))

	# 叠加平铺： (10+20) * 1.05
	e.buffs.apply_buff(e.stats, "buff_atk_flat_20", 3001)
	assert_true(is_equal_approx(e.stats.get_final(atk_id), (10.0 + 20.0) * 1.05))


func test_add_flat_behavior_not_regressed() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var e := TestBattle.make_entity(3002, ds, enums_rt)
	var atk_id := ds.stat_id("ATK")
	assert_true(atk_id >= 0)

	e.buffs.apply_buff(e.stats, "buff_atk_flat_20", 3002)
	assert_eq(e.stats.get_final(atk_id), 30.0)
