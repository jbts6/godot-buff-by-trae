extends GutTest

## 整回合脚本式集成测试（TURN_START 语义）
##
## 流程：
## - Turn1：defender 上盾
## - Turn2：attacker 挂 buff_on_hit_apply_dot，并三连对 defender（每段 AFTER_DEAL 挂 1 个 DOT）
## - Turn3 start：DOT 结算（3 traces）
## - Turn3：驱散 DEBUFF 成功（移除 DOT）
## - Turn4 start：无 trace
## - Turn4：再三连挂 DOT；设置 defender 对 DEBUFF 驱散免疫，驱散失败
## - Turn5 start：DOT 仍结算（trace + 3）
##
## 稳定性要求：
## - attacker：HIT_RATE=1（确保命中）
## - attacker：CRIT_RATE=0（避免暴击干扰数值与 trace 断言）

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _set_attacker_deterministic_hit_and_crit(attacker: Dictionary, ds: OmniCompiledDataset) -> void:
	var hit_id := ds.stat_id("HIT_RATE")
	var crit_id := ds.stat_id("CRIT_RATE")
	assert_true(hit_id >= 0)
	assert_true(crit_id >= 0)

	# 用 add_base 把最终值“拨到”期望值，避免依赖默认值常量。
	attacker.stats.add_base(hit_id, 1.0 - float(attacker.stats.get_final(hit_id)))
	attacker.stats.add_base(crit_id, 0.0 - float(attacker.stats.get_final(crit_id)))

	assert_true(is_equal_approx(float(attacker.stats.get_final(hit_id)), 1.0))
	assert_true(is_equal_approx(float(attacker.stats.get_final(crit_id)), 0.0))


func _count_instances_by_buff_id(buffs: OmniBuffCore, ds: OmniCompiledDataset, buff_id_str: String) -> int:
	var cnt := 0
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		var def: Dictionary = ds.buff_defs[int(inst.buff_def_id)]
		if String(def.get("id", "")) == buff_id_str:
			cnt += 1
	return cnt


func _assert_dot_traces(replay: RefCounted, from_idx: int, expected_count: int, attacker_id: int, defender_id: int) -> void:
	assert_true(replay != null)
	# 注意：GDScript 没有 `has_property`；这里直接假定 replay 为 OmniReplay 实例（由 ReplayScript.new() 创建）。

	var after_idx := from_idx + expected_count
	assert_true(replay.dot_traces.size() >= after_idx, "dot_traces should have at least %s entries" % [after_idx])
	for i in range(from_idx, after_idx):
		assert_eq(int(replay.dot_traces[i].source_entity_id), attacker_id)
		assert_eq(int(replay.dot_traces[i].target_entity_id), defender_id)


func test_full_turn_script_battle_dot_turn_start_dispel_and_immunity() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()
	var turn := OmniTurnComponent.new()

	var attacker_id := 9001
	var defender_id := 9002
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	_set_attacker_deterministic_hit_and_crit(attacker, ds)

	var hp_id := ds.stat_id("HP")
	var shield_id := ds.stat_id("SHIELD")
	assert_true(hp_id >= 0)
	assert_true(shield_id >= 0)

	var entity_ids := PackedInt32Array([attacker_id, defender_id])
	entity_ids.sort()

	# === Turn 1：defender 上盾 ===
	defender.buffs.apply_buff(defender.stats, "buff_shield_50", defender_id)
	assert_eq(float(defender.stats.get_final(shield_id)), 50.0)
	assert_eq(float(defender.stats.get_final(hp_id)), 100.0)

	# TurnEnd：推进到 Turn2（TURN_START 语义下，TurnEnd 不应 tick DOT）
	var before_end := replay.dot_traces.size()
	turn.on_turn_end(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	var after_end := replay.dot_traces.size()
	assert_eq(after_end - before_end, 0)

	# === Turn 2：attacker 三连，每段 AFTER_DEAL 挂 DOT ===
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_apply_dot", attacker_id)
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var base_hits := [12.0, 14.0, 18.0]
	for i in range(base_hits.size()):
		pipe.deal_damage(
			attacker.stats,
			defender.stats,
			attacker.buffs,
			defender.buffs,
			ds,
			float(base_hits[i]),
			replay,
			200 + i,
			tags_mask,
			runtime
		)

	assert_eq(_count_instances_by_buff_id(defender.buffs, ds, "buff_dot_fire_3t"), 3, "defender should have 3 DOT buff instances after 3 hits")

	# TurnEnd：推进到 Turn3（仍不应 tick DOT）
	before_end = replay.dot_traces.size()
	turn.on_turn_end(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	after_end = replay.dot_traces.size()
	assert_eq(after_end - before_end, 0, "applying dots this turn should not tick at turn end (TURN_START semantics)")

	# === Turn 3 start：DOT 结算（应产出 3 条 trace）===
	var hp_before := float(defender.stats.get_final(hp_id))
	var before := replay.dot_traces.size()
	turn.on_turn_start(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	var after := replay.dot_traces.size()
	assert_eq(after - before, 3, "Turn3 start should tick 3 dot instances (3 traces)")
	_assert_dot_traces(replay, before, 3, attacker_id, defender_id)
	assert_true(float(defender.stats.get_final(hp_id)) < hp_before, "DOT tick should reduce HP")

	# === Turn 3：驱散 DEBUFF（应移除 DOT）===
	# 显式类型：避免 `:=` 在动态对象返回值上推断失败
	var removed: int = int(defender.buffs.dispel_by_tag(defender.stats, "DEBUFF", false))
	assert_gt(removed, 0)
	assert_eq(_count_instances_by_buff_id(defender.buffs, ds, "buff_dot_fire_3t"), 0, "DOT should be removed after dispel_by_tag(DEBUFF)")

	# TurnEnd：推进到 Turn4
	before_end = replay.dot_traces.size()
	turn.on_turn_end(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	after_end = replay.dot_traces.size()
	assert_eq(after_end - before_end, 0)

	# === Turn 4 start：不再结算 DOT（无 trace）===
	hp_before = float(defender.stats.get_final(hp_id))
	before = replay.dot_traces.size()
	turn.on_turn_start(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	after = replay.dot_traces.size()
	assert_eq(after - before, 0, "after dispel, Turn4 start should not tick DOT (no trace)")
	assert_true(is_equal_approx(float(defender.stats.get_final(hp_id)), hp_before), "after dispel, HP should not change on Turn4 start")

	# === Turn 4：再三连挂 DOT；设置驱散免疫（对 DEBUFF）并驱散失败 ===
	for i in range(base_hits.size()):
		pipe.deal_damage(
			attacker.stats,
			defender.stats,
			attacker.buffs,
			defender.buffs,
			ds,
			float(base_hits[i]),
			replay,
			400 + i,
			tags_mask,
			runtime
		)
	assert_eq(_count_instances_by_buff_id(defender.buffs, ds, "buff_dot_fire_3t"), 3)

	# 免疫对 DEBUFF 的驱散
	defender.buffs.target_dispel_immunity_mask |= int(enums_rt.tag_mask(["DEBUFF"]))
	removed = defender.buffs.dispel_by_tag(defender.stats, "DEBUFF", false)
	assert_eq(removed, 0, "dispel should fail due to target_dispel_immunity_mask")
	assert_eq(_count_instances_by_buff_id(defender.buffs, ds, "buff_dot_fire_3t"), 3, "DOT should remain when dispel is immune")

	# TurnEnd：推进到 Turn5（仍不应 tick DOT）
	before_end = replay.dot_traces.size()
	turn.on_turn_end(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	after_end = replay.dot_traces.size()
	assert_eq(after_end - before_end, 0)

	# === Turn 5 start：DOT 仍应结算（trace + 3）===
	hp_before = float(defender.stats.get_final(hp_id))
	before = replay.dot_traces.size()
	turn.on_turn_start(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	after = replay.dot_traces.size()
	assert_eq(after - before, 3, "Turn5 start should tick 3 dot instances (3 traces)")
	_assert_dot_traces(replay, before, 3, attacker_id, defender_id)
	assert_true(float(defender.stats.get_final(hp_id)) < hp_before, "DOT tick should reduce HP on Turn5 start")
