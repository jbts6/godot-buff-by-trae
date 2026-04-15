extends GutTest

## E1 plan / Task3：
## - 对同一目标施加：
##   - FIRE DOT 两来源（buff_dot_fire_3t）
##   - POISON DOT 两来源（buff_dot_poison_3t）
## - TurnStart tick 后：
##   - dot_traces 增量 == 4（每个DOT实例一条）
##   - damage_traces 增量 == 2（FIRE聚合一段 + POISON聚合一段，按 tags_mask 分段）
##   - HP 下降量 == 四条 DotTrace.final_damage 之和

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid := ds.stat_id(stat_name)
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	entity.stats.add_base(sid, v - float(entity.stats.get_final(sid)))
	assert_true(is_equal_approx(float(entity.stats.get_final(sid)), v))


func test_dot_aggregate_separates_by_tags_mask() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()
	var turn := OmniTurnComponent.new()

	var src1_id := 7911
	var src2_id := 7912
	var tgt_id := 7913

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

	# 让两来源 ATK 不同，避免“恰好相等”掩盖问题
	_set_stat_final(src1, ds, "ATK", 30.0)
	_set_stat_final(src2, ds, "ATK", 50.0)

	# 同一目标：两来源 FIRE DOT + 两来源 POISON DOT
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", src1_id)
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", src2_id)
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_poison_3t", src1_id)
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_poison_3t", src2_id)

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

	# 1) 每个DOT实例都应产出一条 DotTrace：2(FIRE) + 2(POISON) = 4
	assert_eq(replay.dot_traces.size() - before_dot_traces, 4, "one tick should create 4 dot traces (2 fire + 2 poison, by source)")

	# 2) E1 聚合：同 target + tick_phase 但不同 tags_mask（FIRE vs POISON）应拆成两段伤害
	assert_eq(replay.damage_traces.size() - before_damage_traces, 2, "E1 aggregate: different tags_mask should produce 2 damage traces (fire + poison)")

	var fire_bit: int = int(enums_rt.tag_mask(["FIRE"]))
	var poison_bit: int = int(enums_rt.tag_mask(["POISON"]))
	var seen_fire := false
	var seen_poison := false
	var sum_damage_trace := 0.0
	for i in range(before_damage_traces, replay.damage_traces.size()):
		var dt = replay.damage_traces[i]
		var tm := int(dt.tags_mask)
		seen_fire = seen_fire or ((tm & fire_bit) != 0)
		seen_poison = seen_poison or ((tm & poison_bit) != 0)
		sum_damage_trace += float(dt.final_damage)
	assert_true(seen_fire, "damage traces should include a FIRE segment (tags_mask contains FIRE)")
	assert_true(seen_poison, "damage traces should include a POISON segment (tags_mask contains POISON)")

	# 3) HP 下降量 == 四条 DotTrace.final_damage 之和（并与两段 DamageTrace 合计一致）
	var hp_delta := before_hp - after_hp
	assert_true(hp_delta > 0.0, "hp should be reduced by dot ticks")

	var sum_dot_damage := 0.0
	for i in range(before_dot_traces, replay.dot_traces.size()):
		sum_dot_damage += float(replay.dot_traces[i].final_damage)
	assert_true(is_equal_approx(hp_delta, sum_dot_damage), "hp delta should equal sum of 4 dot final_damage")
	assert_true(is_equal_approx(hp_delta, sum_damage_trace), "hp delta should equal sum of 2 aggregated damage traces")

