extends GutTest

## 用例：碎盾（SHIELD=0）应在 DAMAGE/APPLY 阶段、护盾吸收前生效
##
## 覆盖：
## - baseline：有盾无碎盾 -> HP 不变，SHIELD 从 50 降到 20（吸收 30）
## - shatter：攻击者挂 buff_on_hit_shatter_shield -> 本次直接扣 HP 30 且 SHIELD 为 0

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_shatter_shield_happens_before_shield_absorb() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	var attacker := TestBattle.make_entity(7801, ds, enums_rt)
	var defender := TestBattle.make_entity(7802, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var hp_id := ds.stat_id("HP")
	var shield_id := ds.stat_id("SHIELD")
	assert_true(hp_id >= 0)
	assert_true(shield_id >= 0)

	# rpg_tests 默认 ATK=10、DEF=5 => damage_final = base + 5
	# 为了让本用例“本次伤害=30”更直观：base 取 25
	var base_damage := 25.0

	# baseline：有盾，没碎盾 -> 本次伤害优先被盾吸收，HP 不变
	defender.buffs.apply_buff(defender.stats, "buff_shield_50", 7802)
	var hp0 := float(defender.stats.get_final(hp_id))
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, base_damage, replay, 1, tags_mask, runtime)
	assert_true(is_equal_approx(float(defender.stats.get_final(hp_id)), hp0))
	assert_eq(float(defender.stats.get_final(shield_id)), 20.0) # 50-30

	# reset：重新上盾（并换一组 eid，避免 runtime/buff 侧缓存相互影响）
	defender = TestBattle.make_entity(7803, ds, enums_rt)
	attacker = TestBattle.make_entity(7804, ds, enums_rt)
	runtime = TestBattle.make_runtime([attacker, defender])
	defender.buffs.apply_buff(defender.stats, "buff_shield_50", 7803)

	# 有碎盾 buff：应在 APPLY 阶段把盾置0，本次伤害直接扣HP
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_shatter_shield", 7804)
	hp0 = float(defender.stats.get_final(hp_id))
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, base_damage, replay, 2, tags_mask, runtime)
	assert_eq(float(defender.stats.get_final(shield_id)), 0.0)
	assert_eq(float(defender.stats.get_final(hp_id)), hp0 - 30.0)

