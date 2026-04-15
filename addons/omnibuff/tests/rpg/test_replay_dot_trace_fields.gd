extends GutTest

## H plan / Task2：
## - 给目标挂 buff_dot_fire_3t（TURN_START 语义：挂上的当回合不结算）
## - 推进到下一回合后执行 TurnComponent.on_turn_start（传 replay）
## - 断言 replay.dot_traces 至少新增 1 条，并且 dot trace 字段齐全且类型正确：
##   (turn/dot_inst_id/owner_buff_inst_id/source/target/read_source_stat/value/base_ratio/base_damage/final_damage/tags_mask)
##
## 说明：
## - 当前实现中 dot trace 字段命名为：
##   - source -> source_entity_id
##   - target -> target_entity_id
##   - value  -> source_stat_value
## - 避免使用 `:=`，减少 Godot 4 推断失败的坑。

const ReplayScript = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")


func _set_stat_final(entity: Dictionary, ds: OmniCompiledDataset, stat_name: String, v: float) -> void:
	var sid: int = int(ds.stat_id(stat_name))
	assert_true(sid >= 0, "missing stat: %s" % [stat_name])
	entity.stats.add_base(sid, v - float(entity.stats.get_final(sid)))
	assert_true(is_equal_approx(float(entity.stats.get_final(sid)), v))


func test_replay_dot_trace_fields_types_present() -> void:
	var loaded: Dictionary = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe: OmniDamagePipeline = OmniDamagePipeline.new()
	var replay: RefCounted = ReplayScript.new()
	var turn: OmniTurnComponent = OmniTurnComponent.new()

	var source_id: int = 9301
	var target_id: int = 9302

	var source_entity: Dictionary = TestBattle.make_entity(source_id, ds, enums_rt)
	var target_entity: Dictionary = TestBattle.make_entity(target_id, ds, enums_rt)
	var runtime: Dictionary = TestBattle.make_runtime([source_entity, target_entity])

	# 固定命中/暴击，避免伤害管线随机性影响 dot tick 产出
	_set_stat_final(source_entity, ds, "HIT_RATE", 1.0)
	_set_stat_final(source_entity, ds, "CRIT_RATE", 0.0)
	_set_stat_final(target_entity, ds, "EVADE", 0.0)
	_set_stat_final(source_entity, ds, "ATK", 30.0)

	# 目标挂 DOT（来源=source_id）
	target_entity.buffs.apply_buff(target_entity.stats, "buff_dot_fire_3t", source_id)

	var ids: PackedInt32Array = PackedInt32Array([source_id, target_id])
	ids.sort()

	# TURN_START 语义：先 TurnEnd 推进到下一回合，再 TurnStart 结算 DOT
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

	var before: int = int(replay.dot_traces.size())
	turn.on_turn_start(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	var after: int = int(replay.dot_traces.size())

	assert_true(after - before >= 1, "TurnStart should produce at least 1 dot trace after applying buff_dot_fire_3t")

	# 取新增的第一条 DotTrace
	var t: RefCounted = replay.dot_traces[before]

	# 字段存在 + 类型断言（避免仅靠隐式转换）
	assert_eq(typeof(t.turn), TYPE_INT)
	assert_eq(typeof(t.dot_inst_id), TYPE_INT)
	assert_eq(typeof(t.owner_buff_inst_id), TYPE_INT)
	assert_eq(typeof(t.source_entity_id), TYPE_INT)
	assert_eq(typeof(t.target_entity_id), TYPE_INT)
	assert_eq(typeof(t.read_source_stat), TYPE_STRING)
	assert_eq(typeof(t.source_stat_value), TYPE_FLOAT)
	assert_eq(typeof(t.base_ratio), TYPE_FLOAT)
	assert_eq(typeof(t.base_damage), TYPE_FLOAT)
	assert_eq(typeof(t.final_damage), TYPE_FLOAT)
	assert_eq(typeof(t.tags_mask), TYPE_INT)

	# 显式取值（对应计划字段名：source/target/value）
	var trace_turn: int = int(t.turn)
	var dot_inst_id: int = int(t.dot_inst_id)
	var owner_buff_inst_id: int = int(t.owner_buff_inst_id)
	var source: int = int(t.source_entity_id)
	var target: int = int(t.target_entity_id)
	var read_source_stat: String = String(t.read_source_stat)
	var value: float = float(t.source_stat_value)
	var base_ratio: float = float(t.base_ratio)
	var base_damage: float = float(t.base_damage)
	var final_damage: float = float(t.final_damage)
	var tags_mask: int = int(t.tags_mask)

	# 基础一致性校验（保证字段不是默认空值/占位）
	assert_gt(trace_turn, 0)
	assert_gt(dot_inst_id, 0)
	assert_gt(owner_buff_inst_id, 0)
	assert_eq(source, source_id)
	assert_eq(target, target_id)
	assert_true(read_source_stat.length() > 0)
	assert_true(value >= 0.0)
	assert_true(base_ratio >= 0.0)
	assert_true(base_damage >= 0.0)
	assert_true(final_damage >= 0.0)
	assert_gt(tags_mask, 0)

