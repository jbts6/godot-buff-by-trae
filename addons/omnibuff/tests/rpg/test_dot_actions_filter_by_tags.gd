extends GutTest

## E2 plan / Task4：按 tags_mask_any（dot_tags_mask_any）筛选 DOT 操作目标
##
## 场景：
## - defender 同时有 FIRE 与 POISON DOT（各两来源）
## - attacker 挂 buff_on_hit_dot_clear_poison（AFTER_DEAL scope=TARGET action DOT_CLEAR dot_tags_mask_any=["POISON"]）
## - attacker 对 defender 造成一次 BUFF 标签伤害触发清除
## - 推进到下一回合 TurnStart tick：
##   - 只剩 FIRE 生效（damage_traces 段数=1 且包含 FIRE；POISON 段不存在）

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid := ds.stat_id(stat_name)
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	entity.stats.add_base(sid, v - float(entity.stats.get_final(sid)))
	assert_true(is_equal_approx(float(entity.stats.get_final(sid)), v))


func test_dot_action_clear_filters_by_tags_mask_any() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()
	var turn := OmniTurnComponent.new()

	var attacker_id := 8011
	var src2_id := 8012
	var defender_id := 8013

	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var src2 := TestBattle.make_entity(src2_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, src2, defender])

	# 为避免命中/暴击随机性干扰断言：固定 HIT_RATE=1，CRIT_RATE=0，目标 EVADE=0
	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)

	# 两来源 ATK 不同，便于定位 DOT 伤害来自哪个 source（不做硬编码数值断言）
	_set_stat_final(attacker, ds, "ATK", 30.0)
	_set_stat_final(src2, ds, "ATK", 50.0)

	# defender：两来源 FIRE DOT + 两来源 POISON DOT（均为 TURN_START 语义）
	defender.buffs.apply_buff(defender.stats, "buff_dot_fire_3t", attacker_id)
	defender.buffs.apply_buff(defender.stats, "buff_dot_fire_3t", src2_id)
	defender.buffs.apply_buff(defender.stats, "buff_dot_poison_3t", attacker_id)
	defender.buffs.apply_buff(defender.stats, "buff_dot_poison_3t", src2_id)

	# attacker：命中后清除目标身上的 POISON DOT
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_dot_clear_poison", attacker_id)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	pipe.deal_damage(
		attacker.stats,
		defender.stats,
		attacker.buffs,
		defender.buffs,
		ds,
		10.0,
		replay,
		9901,
		tags_mask,
		runtime
	)

	# 触发后立刻检查：defender 的 DOT 池中应仅剩 FIRE（两来源 -> 2 个实例）
	var dots_any: Variant = defender.buffs.dots_by_target.get(defender_id, null)
	assert_not_null(dots_any, "dots_by_target[defender] should exist")
	var dots: Array = dots_any
	assert_eq(int(dots.size()), 2, "after DOT_CLEAR(POISON), defender should only have 2 FIRE dot instances (2 sources)")
	for x in dots:
		var d = x
		var def: Dictionary = ds.buff_defs[int(d.buff_def_id)]
		assert_eq(String(def.get("id", "")), "buff_dot_fire_3t", "remaining dot should be FIRE only")

	# 推进到下一回合 TurnStart tick（DOT 为 TURN_START 语义）
	var ids := PackedInt32Array([attacker_id, src2_id, defender_id])
	ids.sort()
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

	var before_dot_traces := replay.dot_traces.size()
	var before_damage_traces := replay.damage_traces.size()
	turn.on_turn_start(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

	# tick 后：只剩 FIRE 两来源 -> 2 条 DotTrace；聚合后应只有 1 段 DamageTrace
	assert_eq(replay.dot_traces.size() - before_dot_traces, 2, "one tick should create 2 dot traces (2 FIRE sources); POISON should be absent")
	assert_eq(replay.damage_traces.size() - before_damage_traces, 1, "damage traces should have only 1 segment (FIRE only)")

	var fire_bit: int = int(enums_rt.tag_mask(["FIRE"]))
	var poison_bit: int = int(enums_rt.tag_mask(["POISON"]))
	var dt = replay.damage_traces[before_damage_traces]
	var tm := int(dt.tags_mask)
	assert_true((tm & fire_bit) != 0, "the only damage trace should include FIRE tag")
	assert_true((tm & poison_bit) == 0, "the only damage trace should NOT include POISON tag")

