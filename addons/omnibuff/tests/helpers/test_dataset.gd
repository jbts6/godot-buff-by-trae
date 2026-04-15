class_name OmniTestDataset
extends RefCounted

## 测试 helper：统一加载 base_demo 数据集，并返回 enums_rt + compiled dataset
##
## 说明：
## - 测试必须走真实链路 `load_dataset_full`，以覆盖：
##   - manifest.files[] 全量加载
##   - validators（strict/lenient、未知字段治理、触发链检测等）
## - 返回值使用 Dictionary，便于测试脚本少写样板代码。

static func load_base_demo(strict: bool = true) -> Dictionary:
	var result := OmniManifestLoader.load_dataset_full("res://data/base_demo/manifest.json", strict)
	var enums_rt := OmniEnumsRuntime.from_enums_json(result.enums)
	var ds := OmniDatasetCompiler.compile(result.manifest, enums_rt, result.sources)
	return {
		"result": result,
		"enums_rt": enums_rt,
		"ds": ds
	}

static func load_rpg_tests(strict: bool = true) -> Dictionary:
	var result := OmniManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", strict)
	var enums_rt := OmniEnumsRuntime.from_enums_json(result.enums)
	var ds := OmniDatasetCompiler.compile(result.manifest, enums_rt, result.sources)
	return {
		"result": result,
		"enums_rt": enums_rt,
		"ds": ds
	}
