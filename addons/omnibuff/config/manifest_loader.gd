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

static func _resolve_relative(base_file: String, rel: String) -> String:
	# 将 manifest 内的相对路径解析为绝对资源路径
	var base_dir := base_file.get_base_dir()
	return base_dir.path_join(rel)
