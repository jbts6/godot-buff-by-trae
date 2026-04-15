extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")


func test_manifest_loader_only_loads_files_declared_in_manifest() -> void:
	# 这里不要求 strict 下 issues 为空（strict 会把 warning 升级为 error）；
	# 我们只要求：能成功加载 manifest/enums/sources，并且不存在 ERROR 级别 issue。
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", false)
	for i in res.issues:
		assert_true(int(i.level) != int(OmniValidate.Level.ERROR), "should not have ERROR issues: %s" % String(i.message))

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
