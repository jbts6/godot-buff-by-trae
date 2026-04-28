extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const EnumsRuntime = preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")
const DatasetCompiler = preload("res://addons/omnibuff/config/compiler/dataset_compiler.gd")
const BuffCore = preload("res://addons/omnibuff/runtime/core/buff_core.gd")
const StatsComponent = preload("res://addons/omnibuff/runtime/components/stats_component.gd")


func test_mod_override_replaces_existing_buff() -> void:
	var res = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest_modded.json", true)
	assert_eq(res.mod_conflicts.size(), 1, "should report 1 conflict (buff_atk_flat_20 overridden)")
	var conflict = res.mod_conflicts[0]
	assert_eq(String(conflict.get("id", "")), "buff_atk_flat_20", "conflict should be for buff_atk_flat_20")
	assert_eq(String(conflict.get("action", "")), "replace", "action should be replace")


func test_mod_override_applies_new_value() -> void:
	var res = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest_modded.json", true)
	var _enums_rt = EnumsRuntime.from_enums_json(res.enums)
	var ds = DatasetCompiler.compile(res.manifest, _enums_rt, res.sources)
	var idx: int = ds.buff_id("buff_atk_flat_20")
	assert_gte(idx, 0, "buff_atk_flat_20 should exist")
	var cbd = ds.buff_defs_compiled[idx]
	assert_eq(cbd.effects.size(), 1, "should have 1 effect")
	var ce = cbd.effects[0]
	assert_eq(float(ce.value), 50.0, "mod should override value to 50")


func test_mod_adds_new_buff() -> void:
	var res = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest_modded.json", true)
	var _enums_rt = EnumsRuntime.from_enums_json(res.enums)
	var ds = DatasetCompiler.compile(res.manifest, _enums_rt, res.sources)
	var idx: int = ds.buff_id("buff_mod_only_atk_30")
	assert_gte(idx, 0, "buff_mod_only_atk_30 should be added by mod")


func test_mod_new_buff_functional() -> void:
	var res = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest_modded.json", true)
	var _enums_rt = EnumsRuntime.from_enums_json(res.enums)
	var ds = DatasetCompiler.compile(res.manifest, _enums_rt, res.sources)
	var stats = StatsComponent.new(101, ds)
	var buffs = BuffCore.new(ds, _enums_rt)
	stats.core.set_base(ds.stat_id("ATK"), 10.0)
	buffs.apply_buff(stats, "buff_mod_only_atk_30", 101)
	var atk_sid: int = ds.stat_id("ATK")
	assert_eq(float(stats.get_final(atk_sid)), 40.0, "ATK should be 10+30=40 after mod buff")


func test_no_mods_no_conflicts() -> void:
	var res = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	assert_eq(res.mod_conflicts.size(), 0, "base manifest without mods should have 0 conflicts")
