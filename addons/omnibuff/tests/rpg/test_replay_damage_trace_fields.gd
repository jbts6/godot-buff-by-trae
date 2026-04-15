extends GutTest

## 用例：当传入 replay 时，应产生 1 条 DamageTrace，且字段齐全（类型正确）
##
## 断言字段：
## - turn / attacker_id / defender_id / hit / crit / base_damage / final_damage
## - tags_mask / triggered_inst_ids / stage_triggers
##
## 额外：固定命中/暴击/闪避，避免随机分支干扰（HIT_RATE=1、CRIT_RATE=0、EVADE=0）

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


func test_damage_trace_fields_are_present() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	_enums_rt = loaded.enums_rt

	var pipe = OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()

	var attacker = TestBattle.make_entity(8301, ds, _enums_rt)
	var defender = TestBattle.make_entity(8302, ds, _enums_rt)
	var runtime = TestBattle.make_runtime([attacker, defender])

	var hit_id: int = ds.stat_id("HIT_RATE")
	var crit_rate_id: int = ds.stat_id("CRIT_RATE")
	var evade_id: int = ds.stat_id("EVADE")
	assert_true(hit_id >= 0)
	assert_true(crit_rate_id >= 0)
	assert_true(evade_id >= 0)

	_set_final_stat(attacker.stats, hit_id, 1.0)
	_set_final_stat(attacker.stats, crit_rate_id, 0.0)
	_set_final_stat(defender.stats, evade_id, 0.0)

	pipe.deal_damage(
		attacker.stats,
		defender.stats,
		attacker.buffs,
		defender.buffs,
		ds,
		10.0,
		replay,
		1,
		tag_mask(["BUFF"]),
		runtime
	)

	assert_eq(replay.damage_traces.size(), 1)

	var t: OmniReplay.DamageTrace = replay.damage_traces[0]
	assert_true(typeof(t.turn) == TYPE_INT)
	assert_true(typeof(t.attacker_id) == TYPE_INT)
	assert_true(typeof(t.defender_id) == TYPE_INT)
	assert_true(typeof(t.hit) == TYPE_BOOL)
	assert_true(typeof(t.crit) == TYPE_BOOL)
	assert_true(typeof(t.base_damage) == TYPE_FLOAT)
	assert_true(typeof(t.final_damage) == TYPE_FLOAT)
	assert_true(typeof(t.tags_mask) == TYPE_INT)
	assert_true(typeof(t.triggered_inst_ids) == TYPE_PACKED_INT32_ARRAY)
	assert_true(typeof(t.stage_triggers) == TYPE_DICTIONARY)
