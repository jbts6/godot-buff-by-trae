class_name OmniJson
extends RefCounted

static func load_dict(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var obj := JSON.parse_string(txt)
	if obj == null or typeof(obj) != TYPE_DICTIONARY:
		push_error("[OmniJson] parse failed: " + path)
		return {}
	return obj

