extends GutTest

## 用例：护盾（SHIELD）应在 APPLY 阶段优先吸收伤害，剩余再扣 HP
##
## 覆盖：
## - 单次吸收：护盾足够时 HP 不减少，ctx.final_damage=0
## - 两段连续：第一段消耗部分护盾；第二段先吃完剩余护盾，剩余伤害扣 HP

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_shield_absorb_single_hit_no_hp_loss() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()

	var a := TestBattle.make_entity(4001, ds, enums_rt)
	var d := TestBattle.make_entity(4002, ds, enums_rt)
	var runtime := TestBattle.make_runtime([a, d])

	# 给 defender 上 50 点护盾（以 modifier 形式提供初始值）
	d.buffs.apply_buff(d.stats, "buff_shield_50", 4002)

	var hp_id := ds.stat_id("HP")
	var shield_id := ds.stat_id("SHIELD")
	assert_true(hp_id >= 0)
	assert_true(shield_id >= 0)

	assert_eq(d.stats.get_final(hp_id), 100.0)
	assert_eq(d.stats.get_final(shield_id), 50.0)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# final = base + ATK(10) - DEF(5) = base + 5 => 35
	var ctx := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, 30.0, null, 1, tags_mask, runtime)

	# 35 点全部被护盾吸收：ctx.final_damage 应为吸收后剩余伤害 0
	assert_eq(float(ctx.final_damage), 0.0)
	assert_eq(d.stats.get_final(hp_id), 100.0)
	assert_eq(d.stats.get_final(shield_id), 15.0)


func test_shield_absorb_two_hits_consumes_then_bleeds_to_hp() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()

	var a := TestBattle.make_entity(4011, ds, enums_rt)
	var d := TestBattle.make_entity(4012, ds, enums_rt)
	var runtime := TestBattle.make_runtime([a, d])

	d.buffs.apply_buff(d.stats, "buff_shield_50", 4012)

	var hp_id := ds.stat_id("HP")
	var shield_id := ds.stat_id("SHIELD")
	assert_true(hp_id >= 0)
	assert_true(shield_id >= 0)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# hit1: final = 25 + 5 = 30，被护盾吸收后剩余 0，护盾剩 20
	var ctx1 := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, 25.0, null, 1, tags_mask, runtime)
	assert_eq(float(ctx1.final_damage), 0.0)
	assert_eq(d.stats.get_final(shield_id), 20.0)
	assert_eq(d.stats.get_final(hp_id), 100.0)

	# hit2: final = 35 + 5 = 40，先吃掉护盾 20，剩余 20 扣 HP
	var ctx2 := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, 35.0, null, 2, tags_mask, runtime)
	assert_eq(float(ctx2.final_damage), 20.0)
	assert_eq(d.stats.get_final(shield_id), 0.0)
	assert_eq(d.stats.get_final(hp_id), 80.0)

