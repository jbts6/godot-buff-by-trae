extends GutTest

## 用例：roll_key 作为额外 seed 维度，使得同一回合/同一对手的多次结算也能产生独立的 hit/crit。
## 同时，Replay.DamageTrace 应记录 roll_key，便于回放解释与回归断言。

const ReplayScript = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid: int = int(ds.stat_id(stat_name))
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	entity.stats.add_base(sid, v - float(entity.stats.get_final(sid)))
	assert_true(is_equal_approx(float(entity.stats.get_final(sid)), v))


func test_roll_key_changes_rng_with_same_turn_index() -> void:
	var loaded: Dictionary = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe: OmniDamagePipeline = OmniDamagePipeline.new()
	var replay: RefCounted = ReplayScript.new()

	var attacker_id: int = 9701
	var defender_id: int = 9702
	var attacker: Dictionary = TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender: Dictionary = TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime: Dictionary = TestBattle.make_runtime([attacker, defender])

	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.5)
	_set_stat_final(attacker, ds, "CRIT_DMG", 1.0)

	var turn_index: int = 777
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 同一个 turn_index，用不同 roll_key 跑两次
	var ctx1 = pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 12.0, replay, turn_index, tags_mask, runtime, 1001)
	var ctx2 = pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 12.0, replay, turn_index, tags_mask, runtime, 1002)

	assert_true(bool(ctx1.hit))
	assert_true(bool(ctx2.hit))
	assert_eq(replay.damage_traces.size(), 2)

	# Replay 必须记录 roll_key
	assert_eq(int(replay.damage_traces[0].roll_key), 1001)
	assert_eq(int(replay.damage_traces[1].roll_key), 1002)
