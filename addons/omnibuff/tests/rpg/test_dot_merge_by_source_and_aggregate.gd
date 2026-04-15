extends GutTest

## E1 / Task2：
## - 两个来源（7901/7902）对同一目标施加同一个 FIRE DOT（buff_dot_fire_3t）
## - 断言 dots_by_target[target].size()==2（按来源独立实例）
## - TurnStart tick 后 dot_traces 增量==2（每来源一条 DotTrace）
## - 并通过 HP before/after 断言总伤害发生且为“一次性扣除”
##   - 若实现了 E1 的 tick 聚合：damage_traces 增量应为 1
##   - 且该 1 条 DamageTrace.final_damage == 两条 DotTrace.final_damage 之和 == HP 下降量

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid := ds.stat_id(stat_name)
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	entity.stats.add_base(sid, v - float(entity.stats.get_final(sid)))
	assert_true(is_equal_approx(float(entity.stats.get_final(sid)), v))


func test_dot_two_sources_fire_dot_merge_by_source_and_aggregate() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()
	var turn := OmniTurnComponent.new()

	var src1_id := 7901
	var src2_id := 7902
	var tgt_id := 7903

	var src1 := TestBattle.make_entity(src1_id, ds, enums_rt)
	var src2 := TestBattle.make_entity(src2_id, ds, enums_rt)
	var tgt := TestBattle.make_entity(tgt_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([src1, src2, tgt])

	# 为避免命中/暴击随机性干扰断言：固定 HIT_RATE=1，CRIT_RATE=0，目标 EVADE=0
	_set_stat_final(src1, ds, "HIT_RATE", 1.0)
	_set_stat_final(src2, ds, "HIT_RATE", 1.0)
	_set_stat_final(src1, ds, "CRIT_RATE", 0.0)
	_set_stat_final(src2, ds, "CRIT_RATE", 0.0)
	_set_stat_final(tgt, ds, "EVADE", 0.0)

	# 让两来源的 ATK 不同，避免“恰好相等”掩盖问题（数值用于辅助排错，不做硬编码断言）
	_set_stat_final(src1, ds, "ATK", 30.0)
	_set_stat_final(src2, ds, "ATK", 50.0)

	# 两个来源对同一目标施加同一个 DOT（同 buff_id，不同 source_entity_id）
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", src1_id)
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", src2_id)

	# Godot 4：Dictionary.get() 返回 Variant，使用显式类型避免 “Cannot infer the type” 解析错误
	var dots_any: Variant = tgt.buffs.dots_by_target.get(tgt_id, null)
	assert_not_null(dots_any, "dots_by_target[target] should exist after applying dot")
	var dots: Array = dots_any
	assert_eq(int(dots.size()), 2, "two sources should produce 2 dot instances on the same target")

	var ids := PackedInt32Array([src1_id, src2_id, tgt_id])
	ids.sort()

	# DOT 为 TURN_START 语义：挂上的当回合不结算，推进到下一回合再在 TurnStart 结算
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

	var hp_id := ds.stat_id("HP")
	assert_true(hp_id >= 0)
	var before_hp := float(tgt.stats.get_final(hp_id))

	var before_dot_traces := replay.dot_traces.size()
	var before_damage_traces := replay.damage_traces.size()

	turn.on_turn_start(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

	var after_hp := float(tgt.stats.get_final(hp_id))

	# 每来源一条 DotTrace
	assert_eq(replay.dot_traces.size() - before_dot_traces, 2, "one tick should create 2 dot traces for 2 sources")
	var new_dot_1 = replay.dot_traces[before_dot_traces]
	var new_dot_2 = replay.dot_traces[before_dot_traces + 1]
	var srcs := [int(new_dot_1.source_entity_id), int(new_dot_2.source_entity_id)]
	srcs.sort()
	assert_eq(srcs, [src1_id, src2_id])

	# E1：同一 target + tick_phase + tags_mask（FIRE/DOT）应聚合为“一段伤害”
	assert_eq(
		replay.damage_traces.size() - before_damage_traces,
		1,
		"E1 aggregate: same tags_mask dot ticks should produce 1 damage trace"
	)

	# HP 必须下降，且下降量应等于两条 DOT 跳伤之和
	var hp_delta := before_hp - after_hp
	assert_true(hp_delta > 0.0, "hp should be reduced by dot ticks")

	var sum_dot_damage := float(new_dot_1.final_damage) + float(new_dot_2.final_damage)
	assert_true(is_equal_approx(hp_delta, sum_dot_damage), "hp delta should equal sum of dot final_damage")

	# 若聚合为 1 条 DamageTrace，则该条的 final_damage 应与 HP delta 一致
	var dt = replay.damage_traces[before_damage_traces]
	assert_true(is_equal_approx(float(dt.final_damage), hp_delta), "aggregated damage trace should match hp delta")
