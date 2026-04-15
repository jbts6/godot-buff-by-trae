extends GutTest

## E2 plan / Task3：DOT stacks 操作（MUL / ADD / SET / CLEAR）与 turns 刷新
##
## 覆盖点（行为断言，尽量不直接访问 BuffCore 私有字段）：
## - MUL：使 stacks 翻倍（1->2）且刷新 duration（先 tick 2 次剩 1 turn，再触发后应还能 tick 3 次）
## - SET：设为 3 层（并受 max_stack=3 限制）
## - ADD(-1)：可将 stacks 减到 0 并清除 DOT（后续不再 tick）
## - CLEAR：按 tag（POISON）清除，仅影响该类 DOT，FIRE 不受影响
##
## 断言手段：
## - 用 replay.dot_traces / replay.damage_traces 与 defender HP delta 推导 stacks 与是否仍在 tick
## - 通过设置 attacker.ATK == defender.DEF 且 direct hit base_damage=0，避免“普通伤害”污染 HP 断言

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid := ds.stat_id(stat_name)
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	entity.stats.add_base(sid, v - float(entity.stats.get_final(sid)))
	assert_true(is_equal_approx(float(entity.stats.get_final(sid)), v))


func _hp(entity: Dictionary, ds: OmniCompiledDataset) -> float:
	var hp_id := ds.stat_id("HP")
	assert_true(hp_id >= 0)
	return float(entity.stats.get_final(hp_id))


func _advance_to_next_turn_start(
	turn: OmniTurnComponent,
	ids_sorted: PackedInt32Array,
	runtime: Dictionary,
	pipe: OmniDamagePipeline,
	ds: OmniCompiledDataset,
	replay: RefCounted
) -> void:
	# TurnEnd 推进回合号（不结算 TURN_START DOT），再 TurnStart 结算 DOT
	turn.on_turn_end(ids_sorted, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	turn.on_turn_start(ids_sorted, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)


func test_dot_action_mul_doubles_stacks_and_refreshes_turns() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()
	var turn := OmniTurnComponent.new()

	var attacker_id := 8111
	var defender_id := 8112

	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	# 固定命中/暴击，避免随机性
	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)

	# 让 direct hit 不扣血：base_damage=0 且 ATK==DEF -> raw=max(0,0+ATK-DEF)=0
	# 同时 DOT 伤害只取 base_damage_i（因为 ATK-DEF=0）
	_set_stat_final(attacker, ds, "ATK", 10.0)
	_set_stat_final(defender, ds, "DEF", 10.0)

	# defender：先挂可叠层 FIRE DOT（stacks=1, turns=3）
	defender.buffs.apply_buff(defender.stats, "buff_dot_fire_stack_3t", attacker_id)
	# attacker：命中后将目标身上该 DOT stacks * 2，并刷新 turns
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_dot_mul2", attacker_id)

	var ids := PackedInt32Array([attacker_id, defender_id])
	ids.sort()

	# 先 tick 2 次：剩余 turns 应为 1（内部状态不直接读，通过“后续是否能多 tick”验证刷新）
	for _i in range(2):
		var before_dot := replay.dot_traces.size()
		var before_hp := _hp(defender, ds)
		_advance_to_next_turn_start(turn, ids, runtime, pipe, ds, replay)
		var after_hp := _hp(defender, ds)
		assert_eq(replay.dot_traces.size() - before_dot, 1, "precondition: each tick should create 1 dot trace")
		var t = replay.dot_traces[before_dot]
		assert_true(is_equal_approx(before_hp - after_hp, float(t.final_damage)), "hp delta should equal dot final_damage (no other damage sources)")
		# precondition：stacks 仍为 1 -> base_damage = 10 * 0.1 * 1 = 1
		assert_true(is_equal_approx(float(t.base_damage), 1.0), "precondition: stacks=1 should produce base_damage=1.0")

	# 当前 DOT 只剩 1 次 tick；触发 MUL 后应刷新 turns=3，且 stacks 变为 2
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	pipe.deal_damage(
		attacker.stats,
		defender.stats,
		attacker.buffs,
		defender.buffs,
		ds,
		0.0,
		replay,
		turn.turn_index,
		tags_mask,
		runtime
	)

	# 触发后应还能再 tick 3 次（turns 刷新），且每次 base_damage=10*0.1*2=2
	for _j in range(3):
		var before_dot2 := replay.dot_traces.size()
		var before_hp2 := _hp(defender, ds)
		_advance_to_next_turn_start(turn, ids, runtime, pipe, ds, replay)
		var after_hp2 := _hp(defender, ds)
		assert_eq(replay.dot_traces.size() - before_dot2, 1, "after DOT_MUL_STACKS, dot should continue ticking (refresh turns)")
		var t2 = replay.dot_traces[before_dot2]
		assert_true(is_equal_approx(float(t2.base_damage), 2.0), "MUL should double stacks: base_damage=2.0")
		assert_true(is_equal_approx(before_hp2 - after_hp2, float(t2.final_damage)))

	# 第 4 次 tick 不应再产生 DotTrace（验证 refresh 后恰好 tick 3 次并到期）
	var before_dot3 := replay.dot_traces.size()
	var before_hp3 := _hp(defender, ds)
	_advance_to_next_turn_start(turn, ids, runtime, pipe, ds, replay)
	var after_hp3 := _hp(defender, ds)
	assert_eq(replay.dot_traces.size() - before_dot3, 0, "dot should expire after 3 ticks post-refresh")
	assert_true(is_equal_approx(before_hp3, after_hp3), "no dot tick -> hp should not change")


func test_dot_action_set_sets_stacks_to_3_and_caps_to_max_stack() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()
	var turn := OmniTurnComponent.new()

	var attacker_id := 8121
	var defender_id := 8122

	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 10.0)
	_set_stat_final(defender, ds, "DEF", 10.0)

	defender.buffs.apply_buff(defender.stats, "buff_dot_fire_stack_3t", attacker_id) # stacks=1
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_dot_set3", attacker_id)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	pipe.deal_damage(
		attacker.stats,
		defender.stats,
		attacker.buffs,
		defender.buffs,
		ds,
		0.0,
		replay,
		turn.turn_index,
		tags_mask,
		runtime
	)

	var ids := PackedInt32Array([attacker_id, defender_id])
	ids.sort()

	var before_dot := replay.dot_traces.size()
	var before_hp := _hp(defender, ds)
	_advance_to_next_turn_start(turn, ids, runtime, pipe, ds, replay)
	var after_hp := _hp(defender, ds)

	assert_eq(replay.dot_traces.size() - before_dot, 1, "SET should keep dot alive and tick normally")
	var t = replay.dot_traces[before_dot]
	# SET=3 且 max_stack=3：期望 base_damage=10*0.1*3=3
	assert_true(is_equal_approx(float(t.base_damage), 3.0), "DOT_SET_STACKS(value=3) should result in stacks=3 (capped by max_stack=3)")
	assert_true(is_equal_approx(before_hp - after_hp, float(t.final_damage)))


func test_dot_action_add_minus1_can_clear_dot() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()
	var turn := OmniTurnComponent.new()

	var attacker_id := 8131
	var defender_id := 8132

	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 10.0)
	_set_stat_final(defender, ds, "DEF", 10.0)

	defender.buffs.apply_buff(defender.stats, "buff_dot_fire_stack_3t", attacker_id) # stacks=1
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_dot_add_minus1", attacker_id)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	pipe.deal_damage(
		attacker.stats,
		defender.stats,
		attacker.buffs,
		defender.buffs,
		ds,
		0.0,
		replay,
		turn.turn_index,
		tags_mask,
		runtime
	)

	var ids := PackedInt32Array([attacker_id, defender_id])
	ids.sort()

	# 下一回合 TurnStart：DOT 应已被清除（stacks<=0 -> remove），不再 tick
	var before_dot := replay.dot_traces.size()
	var before_hp := _hp(defender, ds)
	_advance_to_next_turn_start(turn, ids, runtime, pipe, ds, replay)
	var after_hp := _hp(defender, ds)

	assert_eq(replay.dot_traces.size() - before_dot, 0, "DOT_ADD_STACKS(-1) from stacks=1 should clear the dot (no tick)")
	assert_true(is_equal_approx(before_hp, after_hp), "no dot tick -> hp should not change")


func test_dot_action_clear_poison_only_clears_poison() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()
	var turn := OmniTurnComponent.new()

	var attacker_id := 8141
	var defender_id := 8142

	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "ATK", 10.0)
	_set_stat_final(defender, ds, "DEF", 10.0)

	# defender：同时有 FIRE 与 POISON DOT
	defender.buffs.apply_buff(defender.stats, "buff_dot_fire_stack_3t", attacker_id)
	defender.buffs.apply_buff(defender.stats, "buff_dot_poison_3t", attacker_id)

	# attacker：命中后清除目标身上的 POISON DOT
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_dot_clear_poison", attacker_id)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	pipe.deal_damage(
		attacker.stats,
		defender.stats,
		attacker.buffs,
		defender.buffs,
		ds,
		0.0,
		replay,
		turn.turn_index,
		tags_mask,
		runtime
	)

	var ids := PackedInt32Array([attacker_id, defender_id])
	ids.sort()

	# 下一回合 TurnStart：只剩 FIRE tick（DotTrace=1，DamageTrace 分段=1，且 tags_mask 不含 POISON）
	var before_dot := replay.dot_traces.size()
	var before_damage := replay.damage_traces.size()
	var before_hp := _hp(defender, ds)
	_advance_to_next_turn_start(turn, ids, runtime, pipe, ds, replay)
	var after_hp := _hp(defender, ds)

	assert_eq(replay.dot_traces.size() - before_dot, 1, "after DOT_CLEAR(POISON), only FIRE dot should tick")
	assert_eq(replay.damage_traces.size() - before_damage, 1, "after DOT_CLEAR(POISON), aggregated dot damage should have only 1 segment (FIRE)")

	var fire_bit: int = int(enums_rt.tag_mask(["FIRE"]))
	var poison_bit: int = int(enums_rt.tag_mask(["POISON"]))

	var dtt = replay.dot_traces[before_dot]
	assert_true((int(dtt.tags_mask) & fire_bit) != 0, "remaining dot trace should include FIRE tag")
	assert_true((int(dtt.tags_mask) & poison_bit) == 0, "remaining dot trace should NOT include POISON tag")

	var dmg_t = replay.damage_traces[before_damage]
	assert_true((int(dmg_t.tags_mask) & fire_bit) != 0, "remaining damage trace should include FIRE tag")
	assert_true((int(dmg_t.tags_mask) & poison_bit) == 0, "remaining damage trace should NOT include POISON tag")

	assert_true(is_equal_approx(before_hp - after_hp, float(dtt.final_damage)), "hp delta should equal remaining dot final_damage")
