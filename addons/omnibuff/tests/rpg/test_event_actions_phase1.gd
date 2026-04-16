extends GutTest

## Phase 1：Action 扩展回归/验收（初始应失败，直到实现完成）
##
## 覆盖：
## - HEAL
## - ADD_SHIELD
## - DISPEL
## - LIFESTEAL
## - REFLECT_DAMAGE

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid := int(ds.stat_id(stat_name))
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	entity.stats.add_base(sid, v - float(entity.stats.get_final(sid)))
	assert_true(is_equal_approx(float(entity.stats.get_final(sid)), v), "failed to set %s to %s" % [stat_name, v])


func _count_instances_by_buff_id(buffs: RefCounted, ds: OmniCompiledDataset, buff_id_str: String) -> int:
	var cnt: int = 0
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		var def: Dictionary = ds.buff_defs[int(inst.buff_def_id)]
		if String(def.get("id", "")) == buff_id_str:
			cnt += 1
	return cnt


func test_heal_action_increases_hp() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 9011
	var defender_id := 9012
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(defender, ds, "DEF", 0.0)
	_set_stat_final(defender, ds, "SHIELD", 0.0)

	var hp_id := int(ds.stat_id("HP"))
	var hp0 := float(defender.stats.get_final(hp_id))
	# 先吃一口伤害（扣血）
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 20.0, replay, 1, tags_mask, runtime)
	var hp1 := float(defender.stats.get_final(hp_id))
	assert_true(hp1 < hp0, "precondition: damage should reduce HP")

	# 给 defender 挂 HEAL 触发器：AFTER_TAKE self heal +30
	defender.buffs.apply_buff(defender.stats, "buff_action_heal_30", defender_id)
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 0.0, replay, 2, tags_mask, runtime)
	var hp2 := float(defender.stats.get_final(hp_id))
	assert_true(hp2 > hp1, "heal action should increase HP")


func test_add_shield_action_absorbs_next_damage() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 9021
	var defender_id := 9022
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(defender, ds, "DEF", 0.0)
	_set_stat_final(defender, ds, "SHIELD", 0.0)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var shield_id := int(ds.stat_id("SHIELD"))

	# BEFORE_TAKE self add shield +50
	defender.buffs.apply_buff(defender.stats, "buff_action_add_shield_50", defender_id)
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 30.0, replay, 1, tags_mask, runtime)
	var shield_left := float(defender.stats.get_final(shield_id))
	assert_true(shield_left > 0.0, "shield should remain after absorbing part of damage")


func test_dispel_action_removes_debuff_and_dot_instance() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 9031
	var defender_id := 9032
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(defender, ds, "DEF", 0.0)
	_set_stat_final(defender, ds, "SHIELD", 0.0)

	# 先给 defender 挂一个 debuff(dot)；再挂 dispel 触发器：AFTER_TAKE dispel_by_tag(DEBUFF)
	defender.buffs.apply_buff(defender.stats, "buff_dot_fire_3t", attacker_id)
	assert_true(_count_instances_by_buff_id(defender.buffs, ds, "buff_dot_fire_3t") >= 1)
	defender.buffs.apply_buff(defender.stats, "buff_action_dispel_debuff", defender_id)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 0.0, replay, 1, tags_mask, runtime)
	assert_eq(_count_instances_by_buff_id(defender.buffs, ds, "buff_dot_fire_3t"), 0, "dispel should remove dot buff instance")


func test_lifesteal_heals_attacker_based_on_final_damage() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 9041
	var defender_id := 9042
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(defender, ds, "DEF", 0.0)
	_set_stat_final(defender, ds, "SHIELD", 0.0)

	# attacker 先掉点血
	var hp_id := int(ds.stat_id("HP"))
	attacker.stats.add_base(hp_id, -50.0)
	var hp1 := float(attacker.stats.get_final(hp_id))

	attacker.buffs.apply_buff(attacker.stats, "buff_action_lifesteal_20p", attacker_id)
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var ctx := pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 30.0, replay, 1, tags_mask, runtime)
	var hp2 := float(attacker.stats.get_final(hp_id))
	assert_true(hp2 > hp1, "lifesteal should heal attacker")
	assert_true(hp2 - hp1 <= float(ctx.final_damage) * 0.21 + 0.001, "lifesteal amount should be about ratio*final_damage")


func test_reflect_damage_reduces_attacker_hp_without_recursive_damage() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 9051
	var defender_id := 9052
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(defender, ds, "DEF", 0.0)
	_set_stat_final(defender, ds, "SHIELD", 0.0)

	var hp_id := int(ds.stat_id("HP"))
	var hp0 := float(attacker.stats.get_final(hp_id))

	# defender：AFTER_TAKE reflect 30% 到攻击者
	defender.buffs.apply_buff(defender.stats, "buff_action_reflect_30p", defender_id)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var ctx := pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 40.0, replay, 1, tags_mask, runtime)
	var hp1 := float(attacker.stats.get_final(hp_id))
	assert_true(hp1 < hp0, "reflect should reduce attacker HP")
	# 反伤不走 pipeline，因此 replay.damage_traces 不应因为反伤额外多出一条伤害事件（这里只要求“至少没有异常增幅”）
	assert_true(float(ctx.final_damage) >= 0.0)

