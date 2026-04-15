extends GutTest

## 用例：Stat modifier 的 priority 与 OVERRIDE 语义（C plan / rpg_tests fixtures）
##
## 覆盖：
## 1) 多个 OVERRIDE 同时存在时，应按更高 priority 胜出
## 2) priority 相同，则按后施加（source_inst_id 更大）胜出

const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_override_higher_priority_wins() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var e = TestBattle.make_entity(7001, ds, enums_rt)
	var hit_id = ds.stat_id("HIT_RATE")
	assert_true(hit_id >= 0)

	# baseline：HIT_RATE 默认=1.0
	assert_eq(e.stats.get_final(hit_id), 1.0)

	# 先施加低优先级（p800 -> HIT_RATE=1），再施加高优先级（p900 -> HIT_RATE=0）
	var inst_low = e.buffs.apply_buff(e.stats, "buff_c_override_hit_1_p800", 7001)
	var inst_high = e.buffs.apply_buff(e.stats, "buff_c_override_hit_0_p900", 7001)
	assert_true(inst_low > 0)
	assert_true(inst_high > inst_low)

	# 期望：更高 priority 的 OVERRIDE 胜
	assert_eq(e.stats.get_final(hit_id), 0.0)


func test_override_same_priority_last_applied_wins_by_source_inst_id() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var e = TestBattle.make_entity(7002, ds, enums_rt)
	var hit_id = ds.stat_id("HIT_RATE")
	assert_true(hit_id >= 0)

	# baseline：HIT_RATE 默认=1.0
	assert_eq(e.stats.get_final(hit_id), 1.0)

	# 两个 OVERRIDE priority 都是 p850：先设为0，再设为1
	var inst_a = e.buffs.apply_buff(e.stats, "buff_c_override_hit_0_p850", 7002)
	var inst_b = e.buffs.apply_buff(e.stats, "buff_c_override_hit_1_p850", 7002)
	assert_true(inst_a > 0)
	assert_true(inst_b > inst_a)

	# 期望：priority 相同时，后施加（source_inst_id 更大）胜
	assert_eq(e.stats.get_final(hit_id), 1.0)
