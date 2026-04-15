class_name OmniJson
extends RefCounted

static func load_dict(path: String) -> Dictionary:
	## 读取并解析 JSON（返回 Dictionary；失败返回空字典）
	## 注意：更严格的 schema 校验在 validators 中完成。
	var txt := FileAccess.get_file_as_string(path)
	var obj := JSON.parse_string(txt)
	if obj == null or typeof(obj) != TYPE_DICTIONARY:
		push_error("[OmniJson] parse failed: " + path)
		return {}
	return obj
