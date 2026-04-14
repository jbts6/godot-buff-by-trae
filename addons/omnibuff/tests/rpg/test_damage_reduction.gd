extends GutTest

## 用例：DMG_REDUCE（减伤）应在 resolve 后、APPLY 前生效
##
## 覆盖：
## - DMG_REDUCE=0.2 时：final_damage = raw * (1-0.2)
## - 与护盾组合：减伤先于护盾吸收（护盾消耗的是减伤后的伤害）

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_damage_reduction_applies_to_final_damage() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()

	var a := TestBattle.make_entity(5001, ds, enums_rt)
	var d := TestBattle.make_entity(5002, ds, enums_rt)
	var runtime := TestBattle.make_runtime([a, d])

	# defender：受到伤害-20%
	d.buffs.apply_buff(d.stats, "buff_dmg_reduce_20p", 5002)

	var hp_id := ds.stat_id("HP")
	assert_true(hp_id >= 0)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# raw = base(30) + ATK(10) - DEF(5) = 35
	# reduced = 35 * 0.8 = 28
	var ctx := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, 30.0, null, 1, tags_mask, runtime)
	assert_true(is_equal_approx(float(ctx.final_damage), 35.0 * 0.8))
	assert_true(is_equal_approx(d.stats.get_final(hp_id), 100.0 - (35.0 * 0.8)))


func test_damage_reduction_happens_before_shield_absorb() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()

	var a := TestBattle.make_entity(5011, ds, enums_rt)
	var d := TestBattle.make_entity(5012, ds, enums_rt)
	var runtime := TestBattle.make_runtime([a, d])

	# defender：护盾+50、受到伤害-20%
	d.buffs.apply_buff(d.stats, "buff_shield_50", 5012)
	d.buffs.apply_buff(d.stats, "buff_dmg_reduce_20p", 5012)

	var hp_id := ds.stat_id("HP")
	var shield_id := ds.stat_id("SHIELD")
	assert_true(hp_id >= 0)
	assert_true(shield_id >= 0)

	assert_eq(d.stats.get_final(hp_id), 100.0)
	assert_eq(d.stats.get_final(shield_id), 50.0)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# raw = base(35) + ATK(10) - DEF(5) = 40
	# reduced = 40 * 0.8 = 32
	# shield should absorb 32 (NOT 40), leaving shield = 18 and HP unchanged
	var ctx := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, 35.0, null, 1, tags_mask, runtime)
	assert_eq(float(ctx.final_damage), 0.0)
	assert_true(is_equal_approx(d.stats.get_final(shield_id), 50.0 - (40.0 * 0.8)))
	assert_eq(d.stats.get_final(hp_id), 100.0)

