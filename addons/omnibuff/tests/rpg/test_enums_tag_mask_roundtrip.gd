extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const EnumsRt = preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")


func test_tags_mask_roundtrip_is_traceable_and_stable() -> void:
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/base_demo/manifest.json", true)
	assert_true(res.issues.is_empty())

	var rt: OmniEnumsRuntime = EnumsRt.from_enums_json(res.enums)

	var mask: int = int(rt.tag_mask(["DOT", "POISON"]))
	var tags: Array[String] = rt.tags_from_mask(mask)
	assert_true(tags.has("DOT"))
	assert_true(tags.has("POISON"))
