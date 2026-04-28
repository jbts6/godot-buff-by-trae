extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const BuffCore = preload("res://addons/omnibuff/runtime/core/buff_core.gd")
const StatsComponent = preload("res://addons/omnibuff/runtime/components/stats_component.gd")


func _make_buff_core() -> OmniBuffCore:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	var enums_rt := OmniEnumsRuntime.from_enums_json(res.enums)
	var ds := OmniDatasetCompiler.compile(res.manifest, enums_rt, res.sources)
	return OmniBuffCore.new(ds, enums_rt)


func test_ownership_key_no_collision_small_ids() -> void:
	var keys := {}
	for bdid in range(20):
		for src in range(20):
			var key: int = OmniBuffCore._ownership_key(bdid, "BY_SOURCE_INSTANCE", src)
			var pair := "%d_%d" % [bdid, src]
			assert_false(keys.has(key), "collision at bdid=%d src=%d key=%d conflicts with %s" % [bdid, src, key, keys.get(key, "")])
			keys[key] = pair


func test_ownership_key_no_collision_large_entity_ids() -> void:
	var keys := {}
	var large_ids := [65535, 65536, 100000, 999999, 1000000]
	for bdid in range(10):
		for src in large_ids:
			var key: int = OmniBuffCore._ownership_key(bdid, "BY_SOURCE_INSTANCE", src)
			var pair := "%d_%d" % [bdid, src]
			assert_false(keys.has(key), "collision at bdid=%d src=%d key=%d conflicts with %s" % [bdid, src, key, keys.get(key, "")])
			keys[key] = pair


func test_ownership_key_global_mode_same_for_all_sources() -> void:
	var k1: int = OmniBuffCore._ownership_key(5, "GLOBAL", 100)
	var k2: int = OmniBuffCore._ownership_key(5, "GLOBAL", 999)
	assert_eq(k1, k2, "GLOBAL mode should produce same key regardless of source")


func test_ownership_key_by_source_different_for_different_sources() -> void:
	var k1: int = OmniBuffCore._ownership_key(5, "BY_SOURCE_INSTANCE", 100)
	var k2: int = OmniBuffCore._ownership_key(5, "BY_SOURCE_INSTANCE", 999)
	assert_ne(k1, k2, "BY_SOURCE_INSTANCE mode should produce different keys for different sources")


func test_apply_buff_with_large_entity_id() -> void:
	var bc := _make_buff_core()
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	var enums_rt := OmniEnumsRuntime.from_enums_json(res.enums)
	var ds := OmniDatasetCompiler.compile(res.manifest, enums_rt, res.sources)
	var stats := OmniStatsComponent.new(1000000, ds)
	var inst_id := bc.apply_buff(stats, "buff_atk_flat_20", 1000000)
	assert_gt(inst_id, -1, "apply_buff should succeed with large entity_id=1000000")
