extends GutTest

## 用例：当传入 replay 时，DamageTrace.stage_triggers 应包含所有阶段键（即便该阶段未触发任何 buff）
##
## 覆盖：
## - BUILD / BEFORE_DEAL / BEFORE_TAKE / APPLY_ATK / APPLY_DEF / AFTER_DEAL / AFTER_TAKE
## - 固定命中/暴击/闪避：HIT_RATE=1、CRIT_RATE=0、EVADE=0（避免随机分支干扰）

const ReplayScript = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

var _enums_rt: OmniEnumsRuntime


func tag_mask(tags: Array) -> int:
	if _enums_rt == null:
		return 0
	return int(_enums_rt.tag_mask(tags))


func _set_final_stat(stats: OmniStatsComponent, stat_id: int, target: float) -> void:
	var cur: float = float(stats.get_final(stat_id))
	stats.add_base(stat_id, target - cur)


func test_damage_trace_stage_triggers_keys_present() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	_enums_rt = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var attacker = TestBattle.make_entity(7101, ds, _enums_rt)
	var defender = TestBattle.make_entity(7102, ds, _enums_rt)

	var hit_id: int = ds.stat_id("HIT_RATE")
	var crit_rate_id: int = ds.stat_id("CRIT_RATE")
	var evade_id: int = ds.stat_id("EVADE")
	assert_true(hit_id >= 0)
	assert_true(crit_rate_id >= 0)
	assert_true(evade_id >= 0)

	_set_final_stat(attacker.stats, hit_id, 1.0)
	_set_final_stat(attacker.stats, crit_rate_id, 0.0)
	_set_final_stat(defender.stats, evade_id, 0.0)

	var pipe = OmniDamagePipeline.new()
	var replay = ReplayScript.new()
	var runtime = TestBattle.make_runtime([attacker, defender])

	pipe.deal_damage(
		attacker.stats,
		defender.stats,
		attacker.buffs,
		defender.buffs,
		ds,
		30.0,
		replay,
		1,
		tag_mask(["BUFF"]),
		runtime
	)

	assert_eq(replay.damage_traces.size(), 1)
	var trace = replay.damage_traces[0]

	assert_true(trace.stage_triggers.has("BUILD"))
	assert_true(trace.stage_triggers.has("BEFORE_DEAL"))
	assert_true(trace.stage_triggers.has("BEFORE_TAKE"))
	assert_true(trace.stage_triggers.has("APPLY_ATK"))
	assert_true(trace.stage_triggers.has("APPLY_DEF"))
	assert_true(trace.stage_triggers.has("AFTER_DEAL"))
	assert_true(trace.stage_triggers.has("AFTER_TAKE"))
