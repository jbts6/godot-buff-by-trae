extends GutTest

## Task3：CHANCE_APPLY_BUFF 的判定应为确定性（基于 ctx + inst_id 的 seed）
##
## 场景：
## - attacker 挂 buff_event_chance_apply_dot_50（AFTER_DEAL 50% 概率给 TARGET 挂 buff_dot_fire_3t）
## - 用 attacker.buffs._event_seed(ctx, inst_id) 与 attacker.buffs._roll01(seed) 计算 expected（roll < 0.5）
## - 攻击一次后断言 defender 身上 buff_dot_fire_3t 是否存在与 expected 一致
## - 使用全新 runtime（同 turn_index / 同 attacker_id / defender_id）重复一次，结果应完全一致

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid := ds.stat_id(stat_name)
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	entity.stats.add_base(sid, v - float(entity.stats.get_final(sid)))
	assert_true(is_equal_approx(float(entity.stats.get_final(sid)), v))


func _has_buff(entity: Dictionary, ds: OmniCompiledDataset, buff_id_str: String) -> bool:
	var bdid := int(ds.buff_id(buff_id_str))
	assert_true(bdid >= 0, "unknown buff_id=%s" % [buff_id_str])
	for x in entity.buffs.inst_ids:
		var inst = entity.buffs.instances_by_id.get(int(x), null)
		if inst == null:
			continue
		if int(inst.buff_def_id) == bdid:
			return true
	return false


func _run_once(ds: OmniCompiledDataset, enums_rt: OmniEnumsRuntime, attacker_id: int, defender_id: int, turn_index: int) -> Dictionary:
	var pipe := OmniDamagePipeline.new()

	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	# 固定命中/暴击，避免随机性影响事件触发（只测 CHANCE_APPLY_BUFF）
	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)

	# attacker：挂 50% 概率命中后给目标挂 DOT
	var inst_id := int(attacker.buffs.apply_buff(attacker.stats, "buff_event_chance_apply_dot_50", attacker_id))
	assert_true(inst_id >= 0)

	assert_false(_has_buff(defender, ds, "buff_dot_fire_3t"), "precondition: defender should not have dot before attack")

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var ctx := pipe.deal_damage(
		attacker.stats,
		defender.stats,
		attacker.buffs,
		defender.buffs,
		ds,
		30.0,
		null,
		turn_index,
		tags_mask,
		runtime
	)

	var seed := int(attacker.buffs._event_seed(ctx, inst_id))
	var roll := float(attacker.buffs._roll01(seed))
	var expected := roll < 0.5
	var actual := _has_buff(defender, ds, "buff_dot_fire_3t")

	assert_eq(
		actual,
		expected,
		"chance apply buff should match deterministic roll. inst_id=%s seed=%s roll=%s" % [inst_id, seed, roll]
	)

	return {"expected": expected, "actual": actual, "seed": seed, "roll": roll, "inst_id": inst_id}


func test_event_chance_apply_buff_is_deterministic_for_same_turn_index() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var attacker_id := 9101
	var defender_id := 9102
	var turn_index := 123

	var r1 := _run_once(ds, enums_rt, attacker_id, defender_id, turn_index)
	var r2 := _run_once(ds, enums_rt, attacker_id, defender_id, turn_index)

	assert_eq(r1.inst_id, r2.inst_id, "fresh runtime should allocate same inst_id sequence")
	assert_eq(r1.seed, r2.seed, "seed should be deterministic for same turn_index + ids + inst_id")
	assert_true(is_equal_approx(float(r1.roll), float(r2.roll)), "roll should be deterministic for same seed")
	assert_eq(r1.expected, r2.expected, "expected should match across runs for same turn_index")
	assert_eq(r1.actual, r2.actual, "actual applied buff result should match across runs for same turn_index")
