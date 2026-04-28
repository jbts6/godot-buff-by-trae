extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const EnumsRuntime = preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")
const DatasetCompiler = preload("res://addons/omnibuff/config/compiler/dataset_compiler.gd")
const BuffCore = preload("res://addons/omnibuff/runtime/core/buff_core.gd")
const StatsComponent = preload("res://addons/omnibuff/runtime/components/stats_component.gd")
const DamagePipeline = preload("res://addons/omnibuff/runtime/core/damage_pipeline.gd")
const Replay = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TurnComponent = preload("res://addons/omnibuff/runtime/components/turn_component.gd")
const ScenarioRunner = preload("res://addons/omnibuff/demo/scenario_runner.gd")

var _ds = null
var _enums_rt = null


func before_all() -> void:
	var res = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	_enums_rt = EnumsRuntime.from_enums_json(res.enums)
	_ds = DatasetCompiler.compile(res.manifest, _enums_rt, res.sources)


func test_stress_100_apply_remove_cycles() -> void:
	var stats = StatsComponent.new(101, _ds)
	var buffs = BuffCore.new(_ds, _enums_rt)
	stats.core.set_base(_ds.stat_id("HP"), 1000.0)
	stats.core.set_base(_ds.stat_id("ATK"), 50.0)
	stats.core.set_base(_ds.stat_id("DEF"), 20.0)
	for i in range(100):
		buffs.apply_buff(stats, "buff_atk_flat_20", 101)
		var first_id: int = int(buffs.inst_ids[0])
		buffs.remove_by_instance(stats, first_id)
	assert_eq(int(buffs.inst_ids.size()), 0, "all buffs should be removed after 100 cycles")


func test_stress_10_entities_5_buffs_each() -> void:
	var entities: Array = []
	for i in range(10):
		var eid := 100 + i
		var s = StatsComponent.new(eid, _ds)
		s.core.set_base(_ds.stat_id("HP"), 1000.0)
		s.core.set_base(_ds.stat_id("ATK"), 50.0)
		s.core.set_base(_ds.stat_id("DEF"), 20.0)
		var b = BuffCore.new(_ds, _enums_rt)
		for _j in range(5):
			b.apply_buff(s, "buff_atk_flat_20", eid)
		entities.append({"stats": s, "buffs": b})
	for e in entities:
		var s = e.stats
		var atk_sid: int = _ds.stat_id("ATK")
		assert_gt(float(s.get_final(atk_sid)), 50.0, "ATK should be boosted")


func test_stress_100_damage_pipeline_calls() -> void:
	var atk_stats = StatsComponent.new(101, _ds)
	var def_stats = StatsComponent.new(202, _ds)
	var atk_buffs = BuffCore.new(_ds, _enums_rt)
	var def_buffs = BuffCore.new(_ds, _enums_rt)
	atk_stats.core.set_base(_ds.stat_id("HP"), 1000.0)
	atk_stats.core.set_base(_ds.stat_id("ATK"), 50.0)
	def_stats.core.set_base(_ds.stat_id("HP"), 10000.0)
	def_stats.core.set_base(_ds.stat_id("DEF"), 20.0)
	atk_buffs.apply_buff(atk_stats, "buff_atk_flat_20", 101)
	var pipe = DamagePipeline.new()
	var turn = TurnComponent.new()
	for i in range(100):
		var replay = Replay.new()
		pipe.deal_damage(atk_stats, def_stats, atk_buffs, def_buffs, _ds, 30.0, replay, turn.turn_index, i, {})
	var hp_sid: int = _ds.stat_id("HP")
	assert_gt(float(def_stats.get_final(hp_sid)), 0.0, "defender should still have HP after 100 hits")


func test_stress_scenario_stress_10_entities() -> void:
	var runner = ScenarioRunner.new()
	var scenario = {
		"id": "stress_inline",
		"dataset": "rpg_tests",
		"setup": [
			{"entity_id": 1, "base_stats": {"HP": 1000, "ATK": 50, "DEF": 20}},
			{"entity_id": 2, "base_stats": {"HP": 1000, "ATK": 50, "DEF": 20}}
		],
		"steps": [
			{"action": "apply_buff", "entity_id": 1, "buff_id": "buff_atk_flat_20", "source_entity_id": 1},
			{"action": "deal_damage", "attacker_id": 1, "defender_id": 2, "base_damage": 30.0}
		],
		"assertions": [
			{"path": "entity.1.stat.ATK", "op": "gt", "value": 50},
			{"path": "entity.2.stat.HP", "op": "lt", "value": 1000}
		]
	}
	var result = runner.run_scenario(scenario, func(_msg: String) -> void: pass)
	assert_true(result, "inline stress scenario should pass")


func test_stress_compiled_buff_def_lookup_speed() -> void:
	var start_msec := Time.get_ticks_msec()
	for _i in range(1000):
		for j in range(_ds.buff_defs_compiled.size()):
			var cbd = _ds.buff_defs_compiled[j]
			var _v1 = cbd.buff_id_str
			var _v2 = cbd.tag_mask
			var _v3 = cbd.effects.size()
	var elapsed := Time.get_ticks_msec() - start_msec
	assert_lt(elapsed, 500, "1000 iterations of compiled buff def lookup should complete in <500ms, got %dms" % elapsed)
