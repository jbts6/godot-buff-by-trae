extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const EnumsRt = preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")


func test_tags_mask_roundtrip_is_traceable_and_stable() -> void:
	# 这里不要求 strict 下 issues 为空（strict 会把 warning 升级为 error）；
	# 我们只要求：能成功加载 enums，并且不存在 ERROR 级别 issue。
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/base_demo/manifest.json", false)
	for i in res.issues:
		assert_true(int(i.level) != int(OmniValidate.Level.ERROR), "should not have ERROR issues: %s" % String(i.message))

	var rt: OmniEnumsRuntime = EnumsRt.from_enums_json(res.enums)

	var mask: int = int(rt.tag_mask(["DOT", "POISON"]))
	var tags: Array[String] = rt.tags_from_mask(mask)
	assert_true(tags.has("DOT"))
	assert_true(tags.has("POISON"))
