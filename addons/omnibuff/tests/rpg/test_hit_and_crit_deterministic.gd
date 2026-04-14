extends GutTest

## 用例：命中/暴击判定应为确定性（xorshift32 roll），并写入 ctx 与 Replay.DamageTrace
##
## 覆盖：
## - 必未命中：HIT_RATE=0 -> ctx.hit=false 且 final_damage=0
## - 必暴击：CRIT_RATE=1 -> ctx.crit=true 且 final_damage *= (1+CRIT_DMG)
## - 同 turn_index、同 attacker/defender 两次结果一致（hit/crit/final 全一致）

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func test_force_miss_sets_hit_false_and_final_damage_zero() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	var a := TestBattle.make_entity(6001, ds, enums_rt)
	var d := TestBattle.make_entity(6002, ds, enums_rt)
	var runtime := TestBattle.make_runtime([a, d])

	# attacker：HIT_RATE 默认=1.0，施加 -1 => 0（必未命中）
	a.buffs.apply_buff(a.stats, "buff_force_miss", 6001)

	var hp_id := ds.stat_id("HP")
	assert_true(hp_id >= 0)
	assert_eq(d.stats.get_final(hp_id), 100.0)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF", "DEBUFF"]))
	var ctx := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, 30.0, replay, 1, tags_mask, runtime)

	assert_false(ctx.hit)
	assert_false(ctx.crit)
	assert_eq(float(ctx.final_damage), 0.0)
	assert_eq(d.stats.get_final(hp_id), 100.0)

	assert_eq(replay.damage_traces.size(), 1)
	assert_false(replay.damage_traces[0].hit)
	assert_false(replay.damage_traces[0].crit)
	assert_eq(float(replay.damage_traces[0].final_damage), 0.0)


func test_force_crit_multiplies_final_damage_and_sets_crit_true() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	var a := TestBattle.make_entity(6101, ds, enums_rt)
	var d := TestBattle.make_entity(6102, ds, enums_rt)
	var runtime := TestBattle.make_runtime([a, d])

	# attacker：CRIT_RATE 默认=0.05，施加 +0.95 => 1.0（必暴击）
	a.buffs.apply_buff(a.stats, "buff_force_crit", 6101)

	var hp_id := ds.stat_id("HP")
	assert_true(hp_id >= 0)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# raw = base(30) + ATK(10) - DEF(5) = 35
	# crit => 35 * (1 + CRIT_DMG(0.5)) = 52.5
	var ctx := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, 30.0, replay, 1, tags_mask, runtime)
	assert_true(ctx.hit)
	assert_true(ctx.crit)
	assert_true(is_equal_approx(float(ctx.final_damage), 35.0 * 1.5))
	assert_true(is_equal_approx(d.stats.get_final(hp_id), 100.0 - (35.0 * 1.5)))

	assert_eq(replay.damage_traces.size(), 1)
	assert_true(replay.damage_traces[0].hit)
	assert_true(replay.damage_traces[0].crit)
	assert_true(is_equal_approx(float(replay.damage_traces[0].final_damage), 35.0 * 1.5))


func test_same_turn_index_produces_same_hit_and_crit_result() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var hit_id := ds.stat_id("HIT_RATE")
	var crit_id := ds.stat_id("CRIT_RATE")
	assert_true(hit_id >= 0)
	assert_true(crit_id >= 0)

	var turn_index := 77

	# run #1
	var a1 := TestBattle.make_entity(6201, ds, enums_rt)
	var d1 := TestBattle.make_entity(6202, ds, enums_rt)
	var rt1 := TestBattle.make_runtime([a1, d1])
	# HIT_RATE=0.5 / CRIT_RATE=0.5（避免 0/1 退化，确保确实走 roll）
	a1.stats.add_base(hit_id, -0.5)
	a1.stats.add_base(crit_id, 0.45)
	var ctx1 := pipe.deal_damage(a1.stats, d1.stats, a1.buffs, d1.buffs, ds, 30.0, null, turn_index, tags_mask, rt1)

	# run #2（同 turn_index / attacker_id / defender_id，应得到完全一致结果）
	var a2 := TestBattle.make_entity(6201, ds, enums_rt)
	var d2 := TestBattle.make_entity(6202, ds, enums_rt)
	var rt2 := TestBattle.make_runtime([a2, d2])
	a2.stats.add_base(hit_id, -0.5)
	a2.stats.add_base(crit_id, 0.45)
	var ctx2 := pipe.deal_damage(a2.stats, d2.stats, a2.buffs, d2.buffs, ds, 30.0, null, turn_index, tags_mask, rt2)

	assert_eq(ctx1.hit, ctx2.hit, "hit should be deterministic for same turn_index")
	assert_eq(ctx1.crit, ctx2.crit, "crit should be deterministic for same turn_index")
	assert_true(is_equal_approx(float(ctx1.final_damage), float(ctx2.final_damage)), "final_damage should match for same turn_index")

