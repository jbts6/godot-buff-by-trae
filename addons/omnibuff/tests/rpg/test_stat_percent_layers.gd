extends GutTest

## 用例：支持“分段乘法”的百分比层（percent layers）
##
## 例子（ATK 默认=10）：
## - flat：武器 +10、被动 +5
## - pct layer0：饰品 A +5%、饰品 B +10%
## - pct layer1：宝物 总攻击力 +20%
##
## 期望：
## (10 + 10 + 5) * (1 + 0.05 + 0.10) * (1 + 0.20) = 34.5

const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_percent_layers_apply_in_order() -> void:
	var loaded: Dictionary = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var e: Dictionary = TestBattle.make_entity(9801, ds, enums_rt)
	var atk_id: int = int(ds.stat_id("ATK"))
	assert_true(atk_id >= 0)

	# baseline：ATK 默认=10
	assert_true(is_equal_approx(float(e.stats.get_final(atk_id)), 10.0))

	# flat：+10 +5
	e.buffs.apply_buff(e.stats, "buff_test_weapon_atk_flat_10", 9801)
	e.buffs.apply_buff(e.stats, "buff_test_passive_atk_flat_5", 9801)

	# pct layer0：+5% +10%
	e.buffs.apply_buff(e.stats, "buff_atk_pct_5", 9801) # existing, layer 默认=0
	e.buffs.apply_buff(e.stats, "buff_test_trinket_atk_pct_10", 9801)

	# pct layer1：总攻击力 +20%
	e.buffs.apply_buff(e.stats, "buff_test_total_atk_pct_20", 9801)

	var expected: float = (10.0 + 10.0 + 5.0) * (1.0 + 0.05 + 0.10) * (1.0 + 0.20)
	assert_true(
		is_equal_approx(float(e.stats.get_final(atk_id)), expected),
		"expected=%s got=%s" % [expected, e.stats.get_final(atk_id)]
	)

