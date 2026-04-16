extends GutTest

## 用例：AOE（多目标）+ 多段（3段）攻击时：
## - 每个目标都应独立进行 hit/crit 判定（受 defender_id 影响）
## - require_hit 的 AFTER_DEAL APPLY_BUFF 仅对命中目标生效
## - TURN_START tick 仅对命中目标产出 dot trace
##
## 设计：
## - 三段 base hits，对两个目标分别调用 deal_damage（共 6 次）
## - 目标A：HIT_RATE=1、EVADE=0 => 必中
## - 目标B：EVADE=1（且 HIT_RATE=1）=> hit_chance=0 => 必 miss
## - 暴击：CRIT_RATE 设为 0.5，并在测试内复制同样的 roll 算法推导期望 crit（避免访问 OmniDamagePipeline 私有常量/静态）

const ReplayScript = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

const _U32_MASK = 0xFFFFFFFF
const _CRIT_SALT = 0xC3D4E5F6


static func _xorshift32(x: int) -> int:
	x = int(x) & _U32_MASK
	x = int(x ^ ((x << 13) & _U32_MASK)) & _U32_MASK
	x = int(x ^ ((x >> 17) & _U32_MASK)) & _U32_MASK
	x = int(x ^ ((x << 5) & _U32_MASK)) & _U32_MASK
	return x & _U32_MASK


static func _make_seed(turn_index: int, attacker_id: int, defender_id: int, salt: int) -> int:
	var x = 0x9E3779B9
	x = int((x + (turn_index * 1103515245)) & _U32_MASK)
	x = int((x ^ (attacker_id * 2654435761)) & _U32_MASK)
	x = int((x + (defender_id * 374761393)) & _U32_MASK)
	x = int((x ^ salt) & _U32_MASK)
	if x == 0:
		x = 1
	return x


static func _roll01(turn_index: int, attacker_id: int, defender_id: int, salt: int) -> float:
	var seed = _make_seed(turn_index, attacker_id, defender_id, salt)
	var u = _xorshift32(seed)
	return float(u) / 4294967296.0


static func _set_final_stat(stats: OmniStatsComponent, stat_id: int, target: float) -> void:
	var cur = float(stats.get_final(stat_id))
	stats.add_base(stat_id, target - cur)


func test_aoe_multitarget_multihit_per_target_hit_crit_and_dot() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe = OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker_id = 9101
	var target_a_id = 9102
	var target_b_id = 9103

	var attacker = TestBattle.make_entity(attacker_id, ds, enums_rt)
	var target_a = TestBattle.make_entity(target_a_id, ds, enums_rt)
	var target_b = TestBattle.make_entity(target_b_id, ds, enums_rt)
	var runtime = TestBattle.make_runtime([attacker, target_a, target_b])

	# attacker：命中后才给目标挂 DOT（require_hit）
	attacker.buffs.apply_buff(attacker.stats, "buff_on_hit_apply_dot_require_hit", attacker_id)

	var hit_id: int = ds.stat_id("HIT_RATE")
	var evade_id: int = ds.stat_id("EVADE")
	var crit_rate_id: int = ds.stat_id("CRIT_RATE")
	var crit_dmg_id: int = ds.stat_id("CRIT_DMG")
	assert_true(hit_id >= 0)
	assert_true(evade_id >= 0)
	assert_true(crit_rate_id >= 0)
	assert_true(crit_dmg_id >= 0)

	# A 必中，B 必 miss（通过 EVADE 拉到 hit_chance=0）
	_set_final_stat(attacker.stats, hit_id, 1.0)
	_set_final_stat(target_a.stats, evade_id, 0.0)
	_set_final_stat(target_b.stats, evade_id, 1.0)

	var crit_rate = 0.5
	_set_final_stat(attacker.stats, crit_rate_id, crit_rate)
	_set_final_stat(attacker.stats, crit_dmg_id, 0.5)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var base_hits = [12.0, 14.0, 18.0]
	for i in range(base_hits.size()):
		var turn_index = 200 + i

		var ctx_a = pipe.deal_damage(
			attacker.stats,
			target_a.stats,
			attacker.buffs,
			target_a.buffs,
			ds,
			float(base_hits[i]),
			replay,
			turn_index,
			tags_mask,
			runtime
		)
		var ctx_b = pipe.deal_damage(
			attacker.stats,
			target_b.stats,
			attacker.buffs,
			target_b.buffs,
			ds,
			float(base_hits[i]),
			replay,
			turn_index,
			tags_mask,
			runtime
		)

		# per-target 命中判定
		assert_true(ctx_a.hit, "target A should always hit")
		assert_false(ctx_b.hit, "target B should always miss")

		# per-target 暴击判定（测试内复制 roll 算法推导期望值；避免访问 OmniDamagePipeline 私有成员）
		var expect_crit_a = (_roll01(turn_index, attacker_id, target_a_id, _CRIT_SALT) < crit_rate)
		assert_eq(ctx_a.crit, expect_crit_a, "target A crit should follow deterministic roll")
		assert_false(ctx_b.crit, "missed hit should never crit")

	# 6 次 deal_damage => 6 条 damage_traces（A 3 条 + B 3 条）
	assert_eq(replay.damage_traces.size(), 6)

	for i in range(base_hits.size()):
		# 追帧顺序应与调用顺序一致：每段先 A 再 B
		var t_a: OmniReplay.DamageTrace = replay.damage_traces[i * 2]
		var t_b: OmniReplay.DamageTrace = replay.damage_traces[i * 2 + 1]

		assert_eq(int(t_a.attacker_id), attacker_id)
		assert_eq(int(t_a.defender_id), target_a_id)
		assert_true(t_a.hit)
		var expect_crit_a = (_roll01(200 + i, attacker_id, target_a_id, _CRIT_SALT) < crit_rate)
		assert_eq(bool(t_a.crit), expect_crit_a)

		assert_eq(int(t_b.attacker_id), attacker_id)
		assert_eq(int(t_b.defender_id), target_b_id)
		assert_false(t_b.hit)
		assert_false(t_b.crit)

	# DOT 仅对命中目标挂上：
	# - buff 实例：A 3 个（每段命中一次），B 0 个
	assert_eq(target_a.buffs.inst_ids.size(), 3, "target A should receive 3 dot-buff instances from 3 hits")
	assert_eq(target_b.buffs.inst_ids.size(), 0, "target B should receive no dot-buff instances on miss")

	# - DOT 池：按 (buff_def_id, source_entity_id, tick_phase) 复用，A 应只有 1 个 DOT 实例
	var dots_a: Array = target_a.buffs.dots_by_target.get(target_a_id, [])
	var dots_b: Array = target_b.buffs.dots_by_target.get(target_b_id, [])
	assert_eq(dots_a.size(), 1, "target A should have exactly 1 dot instance (reused by source)")
	assert_eq(dots_b.size(), 0, "target B should have no dot instances")

	# TURN_START tick：只对目标A产出 dot trace
	var turn = OmniTurnComponent.new()
	var entity_ids = PackedInt32Array([attacker_id, target_a_id, target_b_id])
	entity_ids.sort()

	var before_end = replay.dot_traces.size()
	turn.on_turn_end(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	assert_eq(replay.dot_traces.size() - before_end, 0, "TURN_START semantics: no dot tick at turn end")

	var before_start = replay.dot_traces.size()
	turn.on_turn_start(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	assert_eq(replay.dot_traces.size() - before_start, 1, "only target A should tick dot and produce dot trace")

	var dt = replay.dot_traces[before_start]
	assert_eq(int(dt.source_entity_id), attacker_id)
	assert_eq(int(dt.target_entity_id), target_a_id)
