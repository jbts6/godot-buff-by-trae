extends GutTest

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const Validate = preload("res://addons/omnibuff/config/compiler/validators.gd")


func _has_issue(issues: Array, level: int, contains: String) -> bool:
	for i in issues:
		if int(i.level) == level and String(i.message).find(contains) >= 0:
			return true
	return false


func test_unknown_fields_are_warning_in_lenient_and_error_in_strict() -> void:
	var manifest_path: String = "res://data/rpg_tests/manifest.json"
	var res: OmniManifestLoader.Result = ManifestLoader.load_dataset_full(manifest_path, true)

	# 注入未知字段
	var sources: Dictionary = res.sources.duplicate(true)
	var buff_defs: Dictionary = sources["buff_defs"]
	var buffs: Array = buff_defs.get("buffs", [])
	var b0: Dictionary = buffs[0]
	b0["unknown_x"] = 123

	# lenient：warning
	var issues_lenient: Array = Validate.validate_all(manifest_path, res.manifest, res.enums, sources, false)
	assert_true(_has_issue(issues_lenient, OmniValidate.Level.WARNING, "unknown field"))

	# strict：error
	var issues_strict: Array = Validate.validate_all(manifest_path, res.manifest, res.enums, sources, true)
	assert_true(_has_issue(issues_strict, OmniValidate.Level.ERROR, "unknown field"))

	# G4：Issue 定位字段必须可用
	var i0: OmniValidate.Issue = issues_lenient[0]
	assert_true(String(i0.file) != "")
	assert_true(String(i0.loc) != "")
	assert_true(String(i0.message) != "")
