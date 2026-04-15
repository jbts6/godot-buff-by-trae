extends GutTest

## 用例：DOT 多来源应产生多条 DotTrace（每来源一条），并且 trace 中来源归因正确
##
## 目的：
## - 验证 DOT “按来源独立实例” 的设计成立
## - 用 trace 断言避免肉眼观察遗漏（例如只看到最后一条 trace）

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_dot_multi_source_produces_two_traces_per_tick() -> void:
	var loaded := TestDataset.load_base_demo(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	var src_a := TestBattle.make_entity(3001, ds, enums_rt)
	src_a.buffs.apply_buff(src_a.stats, "buff_equip_weapon_001", 3001) # ATK=30

	var src_b := TestBattle.make_entity(3002, ds, enums_rt)
	src_b.buffs.apply_buff(src_b.stats, "buff_equip_weapon_001", 3002) # ATK=30
	src_b.stats.add_base(ds.stat_id("ATK"), 20.0) # ATK=50

	var tgt := TestBattle.make_entity(3003, ds, enums_rt)
	# 目标身上的 BuffCore 挂 DOT（按来源独立实例）
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", 3001)
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", 3002)

	var runtime := TestBattle.make_runtime([src_a, src_b, tgt])
	var turn := OmniTurnComponent.new()
	var ids := PackedInt32Array([3001, 3002, 3003])
	ids.sort()

	# DOT 默认在 TURN_START 结算：挂上的当回合不结算，下一回合开始（TurnStart）才结算
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay) # 推进到下一回合
	var before := replay.dot_traces.size()
	turn.on_turn_start(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	var after := replay.dot_traces.size()

	# 断言：一次 tick 产生 2 条 DotTrace（两来源）
	assert_eq(after - before, 2, "one tick should create 2 dot traces for 2 sources")

	var t1 = replay.dot_traces[before]
	var t2 = replay.dot_traces[before + 1]

	var srcs := [int(t1.source_entity_id), int(t2.source_entity_id)]
	srcs.sort()
	assert_eq(srcs, [3001, 3002])

	# 断言：来源属性快照符合预期（src_a=30, src_b=50）
	var vals := [float(t1.source_stat_value), float(t2.source_stat_value)]
	vals.sort()
	assert_eq(vals, [30.0, 50.0])
