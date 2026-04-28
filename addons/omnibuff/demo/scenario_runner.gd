extends RefCounted

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const EnumsRuntime = preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")
const DatasetCompiler = preload("res://addons/omnibuff/config/compiler/dataset_compiler.gd")
const DamagePipeline = preload("res://addons/omnibuff/runtime/core/damage_pipeline.gd")
const Replay = preload("res://addons/omnibuff/runtime/core/replay.gd")
const StatsComponent = preload("res://addons/omnibuff/runtime/components/stats_component.gd")
const TurnComponent = preload("res://addons/omnibuff/runtime/components/turn_component.gd")
const BuffCore = preload("res://addons/omnibuff/runtime/core/buff_core.gd")

var _ds = null
var _enums_rt = null
var _pipe = null
var _replay = null
var _stats_by_entity: Dictionary = {}
var _buff_by_entity: Dictionary = {}
var _turn = null

func load_scenarios_from_dir(dir_path: String) -> Array[Dictionary]:
	var scenarios: Array[Dictionary] = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return scenarios
	da.list_dir_begin()
	var fn := da.get_next()
	while fn != "":
		if fn.ends_with(".json"):
			var full_path := dir_path.path_join(fn)
			var f := FileAccess.open(full_path, FileAccess.READ)
			if f != null:
				var json := JSON.new()
				var err := json.parse(f.get_as_text())
				if err == OK:
					var data: Dictionary = json.data
					data["_source_file"] = full_path
					scenarios.append(data)
		fn = da.get_next()
	da.list_dir_end()
	return scenarios

func run_scenario(scenario: Dictionary, log_fn: Callable) -> bool:
	var dataset_name := String(scenario.get("dataset", "rpg_tests"))
	var manifest_path := "res://data/%s/manifest.json" % dataset_name
	var res = ManifestLoader.load_dataset_full(manifest_path, true)
	if res == null:
		log_fn.call("[ScenarioRunner] failed to load dataset: " + manifest_path)
		return false

	_enums_rt = EnumsRuntime.from_enums_json(res.enums)
	_ds = DatasetCompiler.compile(res.manifest, _enums_rt, res.sources)
	_pipe = DamagePipeline.new()
	_replay = Replay.new()
	_stats_by_entity = {}
	_buff_by_entity = {}
	_turn = TurnComponent.new()

	var setup: Array = scenario.get("setup", [])
	for s in setup:
		_setup_entity(s)

	var steps: Array = scenario.get("steps", [])
	for step in steps:
		var ok := _execute_step(step, log_fn)
		if not ok:
			return false

	var assertions: Array = scenario.get("assertions", [])
	for a in assertions:
		var ok := _check_assertion(a, log_fn)
		if not ok:
			return false

	return true

func _setup_entity(s: Dictionary) -> void:
	var eid := int(s.get("entity_id", 0))
	var stats = StatsComponent.new(eid, _ds)
	var buffs = BuffCore.new(_ds, _enums_rt)
	var base_stats: Dictionary = s.get("base_stats", {})
	for stat_name in base_stats:
		var sid: int = _ds.stat_id(String(stat_name))
		if sid >= 0:
			stats.core.set_base(sid, float(base_stats[stat_name]))
	_stats_by_entity[eid] = stats
	_buff_by_entity[eid] = buffs

func _execute_step(step: Dictionary, log_fn: Callable) -> bool:
	var action := String(step.get("action", "")).to_lower()
	match action:
		"apply_buff":
			var eid := int(step.get("entity_id", 0))
			var buff_id := String(step.get("buff_id", ""))
			var src_eid := int(step.get("source_entity_id", eid))
			var stats = _stats_by_entity.get(eid, null)
			var buffs = _buff_by_entity.get(eid, null)
			if stats == null or buffs == null:
				log_fn.call("[Step] apply_buff: entity %d not found" % eid)
				return false
			buffs.apply_buff(stats, buff_id, src_eid)
		"deal_damage":
			var atk_id := int(step.get("attacker_id", 0))
			var def_id := int(step.get("defender_id", 0))
			var bd := float(step.get("base_damage", 0.0))
			var atk_stats = _stats_by_entity.get(atk_id, null)
			var def_stats = _stats_by_entity.get(def_id, null)
			var atk_buffs = _buff_by_entity.get(atk_id, null)
			var def_buffs = _buff_by_entity.get(def_id, null)
			if atk_stats == null or def_stats == null:
				log_fn.call("[Step] deal_damage: entity not found")
				return false
			var tags_mask: int = int(_enums_rt.tag_mask(step.get("tags", [])))
			var runtime: Dictionary = {"stats_by_entity": _stats_by_entity, "buff_by_entity": _buff_by_entity}
			_pipe.deal_damage(atk_stats, def_stats, atk_buffs, def_buffs, _ds, bd, _replay, _turn.turn_index, tags_mask, runtime)
		"turn_end":
			var eids: Array = step.get("entity_ids", [])
			var sorted := PackedInt32Array()
			for e in eids:
				sorted.append(int(e))
			sorted.sort()
			_turn.on_turn_end(sorted, _buff_by_entity, _stats_by_entity, _pipe, _ds, _replay)
		"turn_start":
			var eids2: Array = step.get("entity_ids", [])
			var sorted2 := PackedInt32Array()
			for e2 in eids2:
				sorted2.append(int(e2))
			sorted2.sort()
			_turn.on_turn_start(sorted2, _buff_by_entity, _stats_by_entity, _pipe, _ds, _replay)
		"add_base":
			var eid3 := int(step.get("entity_id", 0))
			var stat_name := String(step.get("stat", ""))
			var val := float(step.get("value", 0.0))
			var stats3 = _stats_by_entity.get(eid3, null)
			if stats3 != null:
				var sid3: int = _ds.stat_id(stat_name)
				if sid3 >= 0:
					stats3.add_base(sid3, val)
		_:
			log_fn.call("[Step] unknown action: " + action)
			return false
	return true

func _check_assertion(a: Dictionary, log_fn: Callable) -> bool:
	var path := String(a.get("path", ""))
	var op := String(a.get("op", "eq")).to_lower()
	var expected = a.get("value", 0)

	var actual = _resolve_path(path)
	if actual == null:
		log_fn.call("[Assert] path not found: " + path)
		return false

	var ok := false
	match op:
		"eq":
			ok = float(actual) == float(expected)
		"ne":
			ok = float(actual) != float(expected)
		"gt":
			ok = float(actual) > float(expected)
		"lt":
			ok = float(actual) < float(expected)
		"ge":
			ok = float(actual) >= float(expected)
		"le":
			ok = float(actual) <= float(expected)
		_:
			log_fn.call("[Assert] unknown op: " + op)
			return false

	if not ok:
		log_fn.call("[Assert] FAIL: %s %s %s (actual=%s)" % [path, op, str(expected), str(actual)])
	return ok

func _resolve_path(path: String):
	var parts := path.split(".")
	if parts.size() < 3:
		return null
	if parts[0] != "entity":
		return null
	var eid := int(parts[1])
	if parts[2] == "stat" and parts.size() >= 4:
		var stats = _stats_by_entity.get(eid, null)
		if stats == null:
			return null
		var sid: int = _ds.stat_id(parts[3])
		if sid < 0:
			return null
		return stats.get_final(sid)
	if parts[2] == "buff_count":
		var buffs = _buff_by_entity.get(eid, null)
		if buffs == null:
			return null
		return buffs.instance_count()
	return null
