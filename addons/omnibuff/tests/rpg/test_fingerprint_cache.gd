extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")


func _compile_base_demo() -> OmniCompiledDataset:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/base_demo/manifest.json", true)
	var enums_rt := OmniEnumsRuntime.from_enums_json(res.enums)
	return OmniDatasetCompiler.compile(res.manifest, enums_rt, res.sources)


func _compile_rpg_tests() -> OmniCompiledDataset:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	var enums_rt := OmniEnumsRuntime.from_enums_json(res.enums)
	return OmniDatasetCompiler.compile(res.manifest, enums_rt, res.sources)


func test_fingerprint_not_empty_base_demo() -> void:
	var ds := _compile_base_demo()
	assert_ne(ds.fingerprint, "", "fingerprint should not be empty for base_demo")


func test_fingerprint_not_empty_rpg_tests() -> void:
	var ds := _compile_rpg_tests()
	assert_ne(ds.fingerprint, "", "fingerprint should not be empty for rpg_tests")


func test_fingerprint_is_hex_string() -> void:
	var ds := _compile_base_demo()
	assert_gt(ds.fingerprint.length(), 0, "fingerprint should have content")
	var valid := true
	for c in ds.fingerprint:
		if not (c >= '0' and c <= '9') and not (c >= 'a' and c <= 'f'):
			valid = false
			break
	assert_true(valid, "fingerprint should be lowercase hex string")


func test_fingerprint_deterministic_same_input() -> void:
	var ds1 := _compile_rpg_tests()
	var ds2 := _compile_rpg_tests()
	assert_eq(ds1.fingerprint, ds2.fingerprint, "same input should produce same fingerprint")


func test_fingerprint_different_for_different_datasets() -> void:
	var ds_base := _compile_base_demo()
	var ds_rpg := _compile_rpg_tests()
	assert_ne(ds_base.fingerprint, ds_rpg.fingerprint, "different datasets should produce different fingerprints")
