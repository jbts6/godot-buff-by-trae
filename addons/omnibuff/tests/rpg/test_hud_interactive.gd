extends GutTest

const BuffCore = preload("res://addons/omnibuff/runtime/core/buff_core.gd")
const StatsComponent = preload("res://addons/omnibuff/runtime/components/stats_component.gd")
const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const EnumsRuntime = preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")
const DatasetCompiler = preload("res://addons/omnibuff/config/compiler/dataset_compiler.gd")
const DamagePipeline = preload("res://addons/omnibuff/runtime/core/damage_pipeline.gd")
const Replay = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TurnComponent = preload("res://addons/omnibuff/runtime/components/turn_component.gd")

var _ds = null
var _enums_rt = null


func before_all() -> void:
	var res = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	assert_ne(res, null, "manifest should load")
	_enums_rt = EnumsRuntime.from_enums_json(res.enums)
	_ds = DatasetCompiler.compile(res.manifest, _enums_rt, res.sources)


func test_event_trace_fn_called_on_emit() -> void:
	var stats = StatsComponent.new(101, _ds)
	var buffs = BuffCore.new(_ds, _enums_rt)
	var traces: Array = []
	buffs.event_trace_fn = func(et: String, ph: String, ids: PackedInt32Array):
		traces.append([et, ph, ids])
	stats.core.set_base(_ds.stat_id("HP"), 100.0)
	stats.core.set_base(_ds.stat_id("ATK"), 10.0)
	buffs.apply_buff(stats, "buff_atk_flat_20", 101)
	var pipe = DamagePipeline.new()
	var replay = Replay.new()
	var turn = TurnComponent.new()
	pipe.deal_damage(stats, stats, buffs, buffs, _ds, 10.0, replay, turn.turn_index, 0, {})
	assert_gt(traces.size(), 0, "event_trace_fn should be called during damage pipeline")


func test_event_trace_fn_default_is_noop() -> void:
	var stats = StatsComponent.new(101, _ds)
	var buffs = BuffCore.new(_ds, _enums_rt)
	stats.core.set_base(_ds.stat_id("HP"), 100.0)
	stats.core.set_base(_ds.stat_id("ATK"), 10.0)
	buffs.apply_buff(stats, "buff_atk_flat_20", 101)
	var pipe = DamagePipeline.new()
	var replay = Replay.new()
	var turn = TurnComponent.new()
	pipe.deal_damage(stats, stats, buffs, buffs, _ds, 10.0, replay, turn.turn_index, 0, {})
	assert_true(true, "default event_trace_fn (empty Callable) should not crash")


func test_event_trace_fn_records_event_type_and_phase() -> void:
	var stats = StatsComponent.new(101, _ds)
	var buffs = BuffCore.new(_ds, _enums_rt)
	var recorded: Array = []
	buffs.event_trace_fn = func(et: String, ph: String, _ids: PackedInt32Array):
		recorded.append([et, ph])
	stats.core.set_base(_ds.stat_id("HP"), 100.0)
	stats.core.set_base(_ds.stat_id("ATK"), 10.0)
	buffs.apply_buff(stats, "buff_atk_flat_20", 101)
	var pipe = DamagePipeline.new()
	var replay = Replay.new()
	var turn = TurnComponent.new()
	pipe.deal_damage(stats, stats, buffs, buffs, _ds, 10.0, replay, turn.turn_index, 0, {})
	assert_gt(recorded.size(), 0, "should record at least one event")
	var first = recorded[0]
	assert_ne(String(first[0]), "", "event_type should not be empty")
	assert_ne(String(first[1]), "", "phase should not be empty")


func test_event_trace_fn_receives_packed_int32_array() -> void:
	var stats = StatsComponent.new(101, _ds)
	var buffs = BuffCore.new(_ds, _enums_rt)
	var recorded_ids: Array = []
	buffs.event_trace_fn = func(_et: String, _ph: String, ids: PackedInt32Array):
		recorded_ids.append(ids)
	stats.core.set_base(_ds.stat_id("HP"), 100.0)
	stats.core.set_base(_ds.stat_id("ATK"), 10.0)
	buffs.apply_buff(stats, "buff_atk_flat_20", 101)
	var pipe = DamagePipeline.new()
	var replay = Replay.new()
	var turn = TurnComponent.new()
	pipe.deal_damage(stats, stats, buffs, buffs, _ds, 10.0, replay, turn.turn_index, 0, {})
	assert_gt(recorded_ids.size(), 0, "callback should be called")
	for ids in recorded_ids:
		assert_eq(typeof(ids), TYPE_PACKED_INT32_ARRAY, "hit_ids should be PackedInt32Array")


func test_set_stat_base_updates_final() -> void:
	var stats = StatsComponent.new(101, _ds)
	var hp_sid: int = _ds.stat_id("HP")
	stats.core.set_base(hp_sid, 100.0)
	assert_eq(float(stats.get_final(hp_sid)), 100.0, "initial HP should be 100")
	stats.core.set_base(hp_sid, 200.0)
	assert_eq(float(stats.get_final(hp_sid)), 200.0, "HP should update to 200 after set_base")
