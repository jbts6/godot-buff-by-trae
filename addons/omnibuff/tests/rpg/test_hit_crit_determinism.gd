extends GutTest

## 用例：同 turn_index 下命中/暴击/最终伤害必须是确定性结果
##
## 约束（按任务要求固定）：
## - attacker: HIT_RATE=0.3, CRIT_RATE=0.3, CRIT_DMG=1.0
## - defender: EVADE=0
## - 固定 base_damage / ATK / DEF
## - 连续两次调用 deal_damage（相同 turn_index），断言 ctx.hit / ctx.crit / ctx.final_damage 完全一致

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


static func _set_final_stat(stats: OmniStatsComponent, stat_id: int, target: float) -> void:
	# OmniStatsComponent 只有 add_base；这里用 delta 把当前 final 调整到目标值
	var cur := float(stats.get_final(stat_id))
	stats.add_base(stat_id, target - cur)


func test_same_turn_index_twice_produces_identical_hit_crit_and_final_damage() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var a := TestBattle.make_entity(6301, ds, enums_rt)
	var d := TestBattle.make_entity(6302, ds, enums_rt)
	var runtime := TestBattle.make_runtime([a, d])

	# === 固定 base_damage / ATK / DEF ===
	var atk_id := ds.stat_id("ATK")
	var def_id := ds.stat_id("DEF")
	assert_true(atk_id >= 0)
	assert_true(def_id >= 0)
	_set_final_stat(a.stats, atk_id, 10.0)
	_set_final_stat(d.stats, def_id, 5.0)

	var base_damage := 30.0

	# === 固定 HIT_RATE / EVADE / CRIT_RATE / CRIT_DMG ===
	var hit_id := ds.stat_id("HIT_RATE")
	var evade_id := ds.stat_id("EVADE")
	var crit_rate_id := ds.stat_id("CRIT_RATE")
	var crit_dmg_id := ds.stat_id("CRIT_DMG")
	assert_true(hit_id >= 0)
	assert_true(evade_id >= 0)
	assert_true(crit_rate_id >= 0)
	assert_true(crit_dmg_id >= 0)

	_set_final_stat(a.stats, hit_id, 0.3)
	_set_final_stat(d.stats, evade_id, 0.0)
	_set_final_stat(a.stats, crit_rate_id, 0.3)
	_set_final_stat(a.stats, crit_dmg_id, 1.0)

	var turn_index := 123

	# 连续两次调用（相同 turn_index / attacker_id / defender_id）
	var ctx1 := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, base_damage, null, turn_index, tags_mask, runtime)
	var ctx2 := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, base_damage, null, turn_index, tags_mask, runtime)

	assert_eq(ctx1.hit, ctx2.hit, "ctx.hit must be deterministic for the same turn_index")
	assert_eq(ctx1.crit, ctx2.crit, "ctx.crit must be deterministic for the same turn_index")
	assert_eq(float(ctx1.final_damage), float(ctx2.final_damage), "ctx.final_damage must be identical for the same turn_index")

