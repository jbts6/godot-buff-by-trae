class_name OmniManifestLoader
extends RefCounted

class Result:
	var manifest: Dictionary
	var enums: Dictionary
	var issues: Array[OmniValidate.Issue] = []

static func load_dataset(manifest_path: String, strict: bool) -> Result:
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
	var base_dir := base_file.get_base_dir()
	return base_dir.path_join(rel)

