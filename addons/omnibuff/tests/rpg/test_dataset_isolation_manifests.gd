extends GutTest

const OmniJson = preload("res://addons/omnibuff/config/parsers/json_reader.gd")

const RPG_TESTS_MANIFEST_PATH: String = "res://data/rpg_tests/manifest.json"
const BASE_DEMO_MANIFEST_PATH: String = "res://data/base_demo/manifest.json"
const SHARED_ENUMS_PATH: String = "../base_demo/enums.json"


func _is_allowed_rpg_tests_rel_path(rel: String) -> bool:
	# rpg_tests 只允许引用：
	# - rpg_tests/ 内文件（manifest.json 里的相对路径不包含 ../ 即视为在 rpg_tests 内）
	# - 共享枚举：../base_demo/enums.json
	if rel == "":
		return false

	var p: String = rel.simplify_path()

	if p == SHARED_ENUMS_PATH:
		return true

	# 禁止任何额外的跨数据集引用（例如 ../base_demo/*.json 其他文件）
	if p.begins_with("../base_demo/"):
		return false

	# 禁止向上跳目录（避免逃逸出 rpg_tests）
	if p.begins_with("../"):
		return false

	# 禁止显式绝对资源路径（避免绕过相对路径边界检查）
	if p.begins_with("res://") or p.begins_with("user://") or p.begins_with("/"):
		return false

	return true


func test_rpg_tests_manifest_only_refs_rpg_tests_files_and_shared_enums() -> void:
	var m: Dictionary = OmniJson.load_dict(RPG_TESTS_MANIFEST_PATH)
	assert_true(m.has("files"))

	var files: Array = m.get("files", [])
	for f in files:
		assert_true(typeof(f) == TYPE_DICTIONARY, "manifest.files[] must be objects, got: %s" % String(typeof(f)))
		var d: Dictionary = f
		var rel: String = String(d.get("path", ""))
		assert_true(_is_allowed_rpg_tests_rel_path(rel), "unexpected rpg_tests manifest path: %s" % rel)


func test_base_demo_manifest_does_not_ref_rpg_tests() -> void:
	var m: Dictionary = OmniJson.load_dict(BASE_DEMO_MANIFEST_PATH)
	assert_true(m.has("files"))

	var files: Array = m.get("files", [])
	for f in files:
		assert_true(typeof(f) == TYPE_DICTIONARY, "manifest.files[] must be objects, got: %s" % String(typeof(f)))
		var d: Dictionary = f
		var rel: String = String(d.get("path", ""))
		assert_true(rel.find("rpg_tests") < 0, "base_demo manifest should not reference rpg_tests: %s" % rel)

