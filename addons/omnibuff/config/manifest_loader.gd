class_name OmniManifestLoader
extends RefCounted

## manifest.json 入口加载器（最小可用版）
##
## 职责：
## - 读取 manifest.json（权威入口）
## - 找到并加载 enums.json（required=true，必须最先成功）
## - 返回 issues（包含 strict/lenient 的错误等级）
##
## 注意：本文件只做“入口与enums”的最小校验；
## 后续会扩展为：按 load_order 收集所有文件、计算 fingerprint、合并 base+mods 等。

class Result:
	## manifest 原始字典（Schema绑定层：仅 Parser/Compiler 可读字段名）
	var manifest: Dictionary
	## enums.json 原始字典（用于生成 OmniEnumsRuntime）
	var enums: Dictionary
	## 解析后的源文件内容（Schema绑定层）
	## key 建议使用 manifest.files[].type（例如 "stat_defs"/"buff_defs"/"equipment"）
	var sources: Dictionary = {}
	## 解析时的源文件路径（用于错误定位与调试）
	## key 同 sources
	var source_paths: Dictionary = {}
	## 加载与校验问题列表（Error/Warning/Info）
	var issues: Array[OmniValidate.Issue] = []

static func load_dataset(manifest_path: String, strict: bool) -> Result:
	## 加载数据集入口（当前阶段只读取 manifest + enums）
	## - strict=true：缺字段/非法结构作为 Error（阻断）
	## - strict=false：缺字段作为 Warning（允许继续，但运行结果不保证）
	var res := Result.new()
	res.manifest = OmniJson.load_dict(manifest_path)
	if res.manifest.is_empty():
		res.issues.append(OmniValidate.error(manifest_path, "root", "", "manifest empty/invalid"))
		return res

	if not res.manifest.has("files"):
		res.issues.append(OmniValidate.error(manifest_path, "$.files", "", "missing files[]"))
		return res

	var enums_path := ""
	for f in res.manifest["files"]:
		if f.get("type", "") == "enums":
			enums_path = _resolve_relative(manifest_path, f.get("path", ""))
			break

	if enums_path == "":
		res.issues.append(OmniValidate.error(manifest_path, "$.files", "", "enums.json required"))
		return res

	res.enums = OmniJson.load_dict(enums_path)
	if res.enums.is_empty():
		res.issues.append(OmniValidate.error(enums_path, "root", "", "enums parse failed"))
		return res

	if strict:
		if not res.enums.has("enums") or not res.enums.has("tags"):
			res.issues.append(OmniValidate.error(enums_path, "root", "", "missing enums/tags"))
	else:
		if not res.enums.has("enums") or not res.enums.has("tags"):
			res.issues.append(OmniValidate.warning(enums_path, "root", "", "missing enums/tags"))

	return res

static func load_dataset_full(manifest_path: String, strict: bool) -> Result:
	## 加载数据集入口（完整版，M9）
	## - 读取 manifest + enums
	## - 按 manifest.files 加载全部 CSV/JSON 源文件
	## - 运行 OmniValidate.validate_all 做工程化校验（>=12条）
	var res := load_dataset(manifest_path, strict)
	if not res.issues.is_empty():
		# 若 manifest/enums 已经报错，仍继续尝试加载（便于输出更多定位信息）
		pass

	# 读取全部源文件
	if res.manifest.has("files"):
		var files: Array = res.manifest["files"]
		var load_order: Array = res.manifest.get("load_order", [])
		var sorted_files: Array = files
		if not load_order.is_empty():
			sorted_files = _sort_by_load_order(files, load_order)
		for f in sorted_files:
			var f_type := String(f.get("type", ""))
			var rel := String(f.get("path", ""))
			if f_type == "" or rel == "":
				continue
			# manifest/enums 已在 load_dataset 处理过
			if f_type == "manifest" or f_type == "enums":
				continue

			var p := _resolve_relative(manifest_path, rel)
			res.source_paths[f_type] = p

			var fmt := String(f.get("format", "json"))
			if fmt == "json":
				res.sources[f_type] = OmniJson.load_dict(p)
			elif fmt == "csv":
				res.sources[f_type] = OmniCsv.load_rows(p)
			else:
				var lv := OmniValidate.Level.ERROR if strict else OmniValidate.Level.WARNING
				if lv == OmniValidate.Level.ERROR:
					res.issues.append(OmniValidate.error(p, "root", "", "unknown format=" + fmt))
				else:
					res.issues.append(OmniValidate.warning(p, "root", "", "unknown format=" + fmt))

	# 统一校验
	var extra := OmniValidate.validate_all(manifest_path, res.manifest, res.enums, res.sources, strict)
	for i in extra:
		res.issues.append(i)

	return res

static func _resolve_relative(base_file: String, rel: String) -> String:
	var base_dir := base_file.get_base_dir()
	return base_dir.path_join(rel)

static func _sort_by_load_order(files: Array, load_order: Array) -> Array:
	var order_map := {}
	for i in range(load_order.size()):
		order_map[String(load_order[i])] = i
	var sorted := files.duplicate()
	sorted.sort_custom(func(a, b) -> bool:
		var ta := String(a.get("type", ""))
		var tb := String(b.get("type", ""))
		var oa := int(order_map.get(ta, 999))
		var ob := int(order_map.get(tb, 999))
		if oa != ob:
			return oa < ob
		return ta < tb
	)
	return sorted
