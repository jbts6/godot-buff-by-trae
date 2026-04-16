extends GutTest

## Phase 1：Filters 扩展回归/验收（初始应失败，直到实现完成）
##
## 覆盖：
## - require_crit
## - require_shield_absorbed / min_absorbed_shield
## - min_final_damage
## - damage_type_any / element_any
## - Boss 火焰免疫（element=FIRE 时 final_damage=0，采用“护盾吸收”实现）

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

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


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid := int(ds.stat_id(stat_name))
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	entity.stats.add_base(sid, v - float(entity.stats.get_final(sid)))
	assert_true(is_equal_approx(float(entity.stats.get_final(sid)), v), "failed to set %s to %s" % [stat_name, v])


func test_require_crit_filter_only_triggers_on_crit() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 8801
	var defender_id := 8802
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(defender, ds, "DEF", 0.0)

	# crit=1：应触发（require_crit=true 的 listener）
	_set_stat_final(attacker, ds, "CRIT_RATE", 1.0)
	_set_stat_final(attacker, ds, "CRIT_DMG", 0.0)
	attacker.buffs.apply_buff(attacker.stats, "buff_filter_require_crit_add_base_5", attacker_id)
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var ctx1 := pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 10.0, replay, 1, tags_mask, runtime)
	assert_true(ctx1.crit)
	assert_true(is_equal_approx(float(ctx1.base_damage), 15.0), "require_crit should add +5 base damage when crit")

	# crit=0：不应触发
	attacker.buffs.remove_by_buff_id(attacker.stats, "buff_filter_require_crit_add_base_5", "ALL")
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	var ctx2 := pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 10.0, replay, 2, tags_mask, runtime)
	assert_false(ctx2.crit)
	assert_true(is_equal_approx(float(ctx2.base_damage), 10.0), "require_crit should not trigger when not crit")


func test_require_shield_absorbed_filter_only_triggers_when_absorbed() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 8811
	var defender_id := 8812
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(defender, ds, "DEF", 0.0)

	# defender 装一个“吸盾才触发”的 listener（例如 AFTER_TAKE: absorbed_shield>0 时给 attacker 挂 BUFF）
	defender.buffs.apply_buff(defender.stats, "buff_filter_require_shield_absorbed_apply_buff", defender_id)
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 无护盾：不触发
	_set_stat_final(defender, ds, "SHIELD", 0.0)
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 10.0, replay, 1, tags_mask, runtime)
	assert_eq(attacker.buffs.inst_ids.size(), 0, "should not apply buff when no shield absorbed")

	# 有护盾：触发
	_set_stat_final(defender, ds, "SHIELD", 50.0)
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 10.0, replay, 2, tags_mask, runtime)
	assert_eq(attacker.buffs.inst_ids.size(), 1, "should apply buff when absorbed_shield>0")


func test_min_final_damage_filter() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 8821
	var defender_id := 8822
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(defender, ds, "DEF", 0.0)

	defender.buffs.apply_buff(defender.stats, "buff_filter_min_final_damage_apply_dot", defender_id)
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# final_damage 很小：不触发（例如阈值=5）
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 1.0, replay, 1, tags_mask, runtime)
	assert_eq(defender.buffs.inst_ids.size(), 1, "precondition: only trigger buff itself exists")

	# final_damage 足够大：触发（给自己挂 DOT）
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 10.0, replay, 2, tags_mask, runtime)
	assert_true(defender.buffs.inst_ids.size() >= 2, "should apply dot when min_final_damage condition met")


func test_damage_type_and_element_any_filters() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 8831
	var defender_id := 8832
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(defender, ds, "DEF", 0.0)

	# defender：仅当 damage_type_any=[MAGIC] 且 element_any=[FIRE] 时触发（例如 SET_STAT_FINAL(SHIELD=999999)）
	defender.buffs.apply_buff(defender.stats, "buff_filter_magic_fire_immunity", defender_id)
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var dmg_magic := int(enums_rt.enum_int("damage_type", "MAGIC"))
	var el_fire := int(enums_rt.enum_int("element", "FIRE"))
	var dmg_phys := int(enums_rt.enum_int("damage_type", "PHYSICAL"))
	var el_none := int(enums_rt.enum_int("element", "NONE"))

	var hp_id := int(ds.stat_id("HP"))
	var hp0 := float(defender.stats.get_final(hp_id))
	# 期望：MAGIC+FIRE 免疫 => final_damage=0
	var ctx1 := pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 10.0, replay, 1, tags_mask, runtime, 0, -1, dmg_magic, el_fire)
	assert_true(is_equal_approx(float(ctx1.final_damage), 0.0))
	assert_true(is_equal_approx(float(defender.stats.get_final(hp_id)), hp0))
	var shield_id := int(ds.stat_id("SHIELD"))
	if shield_id >= 0:
		assert_true(is_equal_approx(float(defender.stats.get_final(shield_id)), 0.0), "immunity via shield-to-damage should not leave remaining shield")

	# 期望：PHYSICAL+NONE 不免疫 => final_damage>0
	var ctx2 := pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 10.0, replay, 2, tags_mask, runtime, 0, -1, dmg_phys, el_none)
	assert_true(float(ctx2.final_damage) > 0.0)


func test_boss_fire_immunity_element_fire_final_damage_zero() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 8841
	var boss_id := 8842
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var boss := TestBattle.make_entity(boss_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, boss])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(boss, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(boss, ds, "DEF", 0.0)
	_set_stat_final(boss, ds, "SHIELD", 0.0)

	boss.buffs.apply_buff(boss.stats, "buff_boss_fire_immunity", boss_id)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var el_fire := int(enums_rt.enum_int("element", "FIRE"))
	var hp_id := int(ds.stat_id("HP"))
	var hp0 := float(boss.stats.get_final(hp_id))

	var ctx := pipe.deal_damage(attacker.stats, boss.stats, attacker.buffs, boss.buffs, ds, 10.0, replay, 1, tags_mask, runtime, 0, -1, int(enums_rt.enum_int("damage_type", "MAGIC")), el_fire)
	assert_true(is_equal_approx(float(ctx.final_damage), 0.0), "fire immune should make final_damage=0")
	assert_true(is_equal_approx(float(boss.stats.get_final(hp_id)), hp0), "fire immune should not reduce HP")
	var shield_id := int(ds.stat_id("SHIELD"))
	if shield_id >= 0:
		assert_true(is_equal_approx(float(boss.stats.get_final(shield_id)), 0.0), "fire immunity should not leave remaining shield")


func test_skill_id_filter() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 8851
	var defender_id := 8852
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(defender, ds, "DEF", 0.0)
	_set_stat_final(defender, ds, "SHIELD", 0.0)

	# defender：仅当 filters.skill_id==1001 时，AFTER_TAKE 给 attacker 挂 mark
	defender.buffs.apply_buff(defender.stats, "buff_filter_skill_id_apply_mark", defender_id)
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 正例：skill_id=1001 触发
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 10.0, replay, 1, tags_mask, runtime, 0, 1001)
	assert_true(attacker.buffs.inst_ids.size() >= 1, "skill_id=1001 should apply mark buff")

	# 反例：skill_id=2002 不触发（重置 attacker buffs）
	attacker.buffs.remove_by_buff_id(attacker.stats, "buff_dummy_mark_1", "ALL")
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 10.0, replay, 2, tags_mask, runtime, 0, 2002)
	assert_eq(_count_instances_by_buff_id(attacker.buffs, ds, "buff_dummy_mark_1"), 0, "skill_id mismatch should not apply mark buff")


func test_min_absorbed_shield_filter() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id := 8861
	var defender_id := 8862
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 0.0)
	_set_stat_final(defender, ds, "DEF", 0.0)

	defender.buffs.apply_buff(defender.stats, "buff_filter_min_absorbed_shield_apply_mark", defender_id)
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# A) shield=10, damage=10 => absorbed=10 < 20 -> 不触发
	_set_stat_final(defender, ds, "SHIELD", 10.0)
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 10.0, replay, 1, tags_mask, runtime, 0, 1001)
	assert_eq(_count_instances_by_buff_id(attacker.buffs, ds, "buff_dummy_mark_1"), 0, "absorbed=10 should not trigger min_absorbed_shield=20")

	# B) shield=50, damage=30 => absorbed=30 >= 20 -> 触发
	_set_stat_final(defender, ds, "SHIELD", 50.0)
	pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 30.0, replay, 2, tags_mask, runtime, 0, 1001)
	assert_true(_count_instances_by_buff_id(attacker.buffs, ds, "buff_dummy_mark_1") >= 1, "absorbed>=20 should trigger min_absorbed_shield=20")
