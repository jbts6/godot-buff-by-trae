extends GutTest

## Task2：事件动作 ADD_BASE_DAMAGE 应在 BEFORE_DEAL 阶段累加到 ctx.base_damage，并影响最终伤害。
##
## 用例约束：
## - 固定命中/暴击（HIT_RATE=1 / CRIT_RATE=0 / EVADE=0），避免随机性导致 trigger 不稳定
## - ATK/DEF=0，使公式 raw=max(0, base_damage+ATK-DEF) 退化为 raw=base_damage
## - base_damage=10，攻击者挂 buff_event_add_base_damage_5 后：
##   断言 ctx.base_damage==15 且 ctx.final_damage==15

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid := ds.stat_id(stat_name)
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	entity.stats.add_base(sid, v - float(entity.stats.get_final(sid)))
	assert_true(is_equal_approx(float(entity.stats.get_final(sid)), v), "failed to set %s to %s" % [stat_name, v])


func test_event_add_base_damage_affects_ctx_and_final_damage() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()

	var attacker_id := 8301
	var defender_id := 8302

	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	# 固定命中/暴击，避免随机性（filters.require_hit=true）
	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)

	# ATK/DEF=0 -> final_damage 应等于 ctx.base_damage
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(defender, ds, "DEF", 0.0)

	attacker.buffs.apply_buff(attacker.stats, "buff_event_add_base_damage_5", attacker_id)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var ctx := pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 10.0, null, 1, tags_mask, runtime)

	assert_true(is_equal_approx(float(ctx.base_damage), 15.0))
	assert_true(is_equal_approx(float(ctx.final_damage), 15.0))

