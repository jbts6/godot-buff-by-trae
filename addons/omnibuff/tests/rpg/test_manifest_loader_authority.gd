extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")


func test_manifest_loader_only_loads_files_declared_in_manifest() -> void:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	assert_true(res.issues.is_empty(), "dataset should load without issues in strict mode")

	# sources 的 key 只能来自 manifest.files[].type（不包含 manifest/enums）
	var allowed: Dictionary = {}
	for f in res.manifest.get("files", []):
		var t: String = String(f.get("type", ""))
		if t != "" and t != "manifest" and t != "enums":
			allowed[t] = true

	for k in res.sources.keys():
		assert_true(allowed.has(String(k)), "sources contains unexpected key: %s" % String(k))

	# 关键：rpg_tests 的 enums 来自 ../base_demo/enums.json，能成功加载即说明 ../ 解析稳定
	assert_true(res.enums.has("tags"))
