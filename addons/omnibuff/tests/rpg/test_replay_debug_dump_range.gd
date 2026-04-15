extends GutTest

## H3 / Task3：
## - 构造至少 2 条 damage_traces（两次 deal_damage）
## - 构造至少 1 条 dot_traces（挂 DOT 并在 TurnStart tick）
## - 断言 debug_dump_damage_range / debug_dump_dot_range 输出包含关键子串
##   - [DamageTrace] / turn= / base= / final=
##   - [DotTrace] / turn= / src= / tgt= / base= / final=
##
## 注意：避免 `:=` 引起的类型推断坑（尤其是 Dictionary.get()/[] 返回 Variant）

const ReplayScript = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TurnComponentScript = preload("res://addons/omnibuff/runtime/components/turn_component.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid: int = int(ds.stat_id(stat_name))
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	var stats: OmniStatsComponent = entity["stats"]
	var cur: float = float(stats.get_final(sid))
	stats.add_base(sid, v - cur)
	assert_true(is_equal_approx(float(stats.get_final(sid)), v), "failed to set stat %s to %s" % [stat_name, v])


func test_replay_debug_dump_damage_range_and_dot_range_contains_keys() -> void:
	var loaded: Dictionary = TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded["ds"]
	var enums_rt: OmniEnumsRuntime = loaded["enums_rt"]

	var pipe: OmniDamagePipeline = OmniDamagePipeline.new()
	var replay: OmniReplay = ReplayScript.new()
	var turn: OmniTurnComponent = TurnComponentScript.new()

	var attacker_id: int = 8321
	var defender_id: int = 8322
	var attacker: Dictionary = TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender: Dictionary = TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime: Dictionary = TestBattle.make_runtime([attacker, defender])

	# 固定命中/暴击/闪避：避免随机分支导致 trace 缺失
	_set_stat_final(attacker, ds, "HIT_RATE", 1.0)
	_set_stat_final(attacker, ds, "CRIT_RATE", 0.0)
	_set_stat_final(defender, ds, "EVADE", 0.0)

	# 产生两条 damage trace（两次调用 deal_damage）
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	pipe.deal_damage(
		attacker["stats"],
		defender["stats"],
		attacker["buffs"],
		defender["buffs"],
		ds,
		10.0,
		replay,
		1,
		tags_mask,
		runtime
	)
	pipe.deal_damage(
		attacker["stats"],
		defender["stats"],
		attacker["buffs"],
		defender["buffs"],
		ds,
		10.0,
		replay,
		1,
		tags_mask,
		runtime
	)
	assert_true(replay.damage_traces.size() >= 2, "precondition: should have at least 2 damage traces")

	# 产生至少 1 条 dot trace：挂 DOT 并推进到下一回合 TurnStart tick
	defender["buffs"].apply_buff(defender["stats"], "buff_dot_fire_3t", attacker_id)
	var ids: PackedInt32Array = PackedInt32Array([attacker_id, defender_id])
	ids.sort()

	# DOT 为 TURN_START 语义：挂上的当回合不结算，推进后在下一次 TurnStart 结算
	turn.on_turn_end(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, replay)
	var before_dot_traces: int = int(replay.dot_traces.size())
	turn.on_turn_start(ids, runtime["buff_by_entity"], runtime["stats_by_entity"], pipe, ds, replay)
	assert_true(replay.dot_traces.size() >= before_dot_traces + 1, "precondition: turn_start should tick dot and create dot trace")

	# debug_dump_damage_range：检查关键子串
	var s1: String = replay.debug_dump_damage_range(replay.damage_traces.size() - 2)
	assert_true(s1.find("[DamageTrace]") >= 0, s1)
	assert_true(s1.find("turn=") >= 0, s1)
	assert_true(s1.find("base=") >= 0, s1)
	assert_true(s1.find("final=") >= 0, s1)

	# debug_dump_dot_range：检查关键子串
	var s2: String = replay.debug_dump_dot_range(replay.dot_traces.size() - 1)
	assert_true(s2.find("[DotTrace]") >= 0, s2)
	assert_true(s2.find("turn=") >= 0, s2)
	assert_true(s2.find("src=") >= 0, s2)
	assert_true(s2.find("tgt=") >= 0, s2)
	assert_true(s2.find("base=") >= 0, s2)
	assert_true(s2.find("final=") >= 0, s2)

