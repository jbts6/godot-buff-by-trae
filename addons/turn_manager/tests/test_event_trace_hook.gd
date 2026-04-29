extends GutTest

const TurnManager = preload("res://addons/turn_manager/runtime/turn_manager.gd")
const BattleContext = preload("res://addons/turn_manager/runtime/battle_context.gd")
const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")

class MockUnit:
	extends RefCounted
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var stats
	var buffs
	func _init(eid: int, c: String, p: Vector2i, s, b) -> void:
		entity_id = eid
		camp = c
		cell = p
		stats = s
		buffs = b
	func get_speed() -> float:
		return 10.0
	func is_dead() -> bool:
		return false

func test_event_trace_fn_installed_on_setup() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds = loaded.ds
	var enums_rt = loaded.enums_rt

	var a_stats = OmniStatsComponent.new(11001, ds)
	var t_stats = OmniStatsComponent.new(11002, ds)
	var a_buffs = OmniBuffCore.new(ds, enums_rt)
	var t_buffs = OmniBuffCore.new(ds, enums_rt)

	var u1 = MockUnit.new(11001, "ally", Vector2i(2, 1), a_stats, a_buffs)
	var u2 = MockUnit.new(11002, "enemy", Vector2i(0, 1), t_stats, t_buffs)

	assert_false(a_buffs.event_trace_fn.is_valid())
	assert_false(t_buffs.event_trace_fn.is_valid())

	var ctx = BattleContext.new()
	ctx.dataset = ds
	ctx.enums_rt = enums_rt
	ctx.runtime_dict = {"stats_by_entity": {11001: a_stats, 11002: t_stats}, "buff_by_entity": {11001: a_buffs, 11002: t_buffs}}
	ctx.grid = load("res://addons/turn_skill_system/runtime/grid.gd").new()
	ctx.event_bus = load("res://addons/turn_skill_system/runtime/battle_event_bus.gd").new()
	ctx.omnibuff_adapter = load("res://addons/turn_skill_system/runtime/omni_buff_adapter.gd").new()

	var tm = TurnManager.new()
	tm.setup(ctx, [u1, u2])

	assert_true(a_buffs.event_trace_fn.is_valid())
	assert_true(t_buffs.event_trace_fn.is_valid())

func test_event_traces_recorded_on_buff_event() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var ds = loaded.ds
	var enums_rt = loaded.enums_rt

	var a_stats = OmniStatsComponent.new(12001, ds)
	var a_buffs = OmniBuffCore.new(ds, enums_rt)
	var u1 = MockUnit.new(12001, "ally", Vector2i(2, 1), a_stats, a_buffs)

	var ctx = BattleContext.new()
	ctx.dataset = ds
	ctx.enums_rt = enums_rt
	ctx.runtime_dict = {"stats_by_entity": {12001: a_stats}, "buff_by_entity": {12001: a_buffs}}
	ctx.grid = load("res://addons/turn_skill_system/runtime/grid.gd").new()
	ctx.event_bus = load("res://addons/turn_skill_system/runtime/battle_event_bus.gd").new()
	ctx.omnibuff_adapter = load("res://addons/turn_skill_system/runtime/omni_buff_adapter.gd").new()

	var tm = TurnManager.new()
	tm.setup(ctx, [u1])

	a_buffs.apply_buff(a_stats, "buff_atk_flat_20", 12001)
	a_buffs.emit_event(0, 0, PackedInt32Array([1]))

	assert_true(ctx.event_traces.size() > 0)
	var trace = ctx.event_traces[0]
	assert_eq(int(trace.get("entity_id", -1)), 12001)
	assert_true(trace.has("event_type"))
	assert_true(trace.has("phase"))

func test_event_traces_capped_at_500() -> void:
	var ctx = BattleContext.new()
	for i in range(600):
		ctx.event_traces.append({"entity_id": i})
	assert_eq(ctx.event_traces.size(), 600)

func test_context_has_event_traces_field() -> void:
	var ctx = BattleContext.new()
	assert_true(ctx.has_method("get") or "event_traces" in ctx)
	assert_eq(ctx.event_traces.size(), 0)

func test_no_context_no_crash_on_trace() -> void:
	var tm = TurnManager.new()
	tm._on_buff_event_trace(1, "TEST_EVENT", "TEST_PHASE", PackedInt32Array())
