extends RefCounted
class_name SkillValidator

const ALLOWED_TYPES = ["active", "passive", "aura"]

static func validate_skill(skill: Dictionary, file_path: String, strict: bool) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []

	_require_type(skill, "version", TYPE_INT, file_path, "$.version", issues, strict)
	_require_type(skill, "id", TYPE_STRING, file_path, "$.id", issues, strict)
	_require_type(skill, "type", TYPE_STRING, file_path, "$.type", issues, strict)

	var t = String(skill.get("type", ""))
	if t != "" and not ALLOWED_TYPES.has(t):
		_push_issue(issues, "error" if strict else "warning", file_path, "$.type", "invalid_type: %s" % t)

	# targeting：允许 string（FIRST/ALL）或 object（rule/params）
	if t == "active" or t == "aura":
		if not skill.has("targeting"):
			_push_issue(issues, "error" if strict else "warning", file_path, "$.targeting", "missing_targeting")
		else:
			var tt = typeof(skill["targeting"])
			if tt != TYPE_STRING and tt != TYPE_DICTIONARY:
				_push_issue(issues, "error" if strict else "warning", file_path, "$.targeting", "targeting_must_be_string_or_object")

	if t == "active":
		# 权威字段：on_cast/on_hit
		_require_type(skill, "on_cast", TYPE_ARRAY, file_path, "$.on_cast", issues, strict)
		_require_type(skill, "on_hit", TYPE_ARRAY, file_path, "$.on_hit", issues, strict)
		# legacy：effects
		if skill.has("effects"):
			_push_issue(issues, "warning", file_path, "$.effects", "legacy_field_effects_present: prefer on_cast")

	if t == "passive":
		_require_type(skill, "triggers", TYPE_ARRAY, file_path, "$.triggers", issues, strict)

	if t == "aura":
		_require_type(skill, "aura", TYPE_DICTIONARY, file_path, "$.aura", issues, strict)
		if typeof(skill.get("aura")) == TYPE_DICTIONARY:
			var aura: Dictionary = skill.get("aura", {})
			_require_type(aura, "on_enter", TYPE_ARRAY, file_path, "$.aura.on_enter", issues, strict)
			_require_type(aura, "on_exit", TYPE_ARRAY, file_path, "$.aura.on_exit", issues, strict)

	return issues


static func normalize_active_in_place(skill: Dictionary) -> void:
	# legacy: effects -> on_cast
	if skill.has("effects") and (not skill.has("on_cast")):
		skill["on_cast"] = skill["effects"]
	if not skill.has("on_cast"):
		skill["on_cast"] = []
	if not skill.has("on_hit"):
		skill["on_hit"] = []


static func _require_type(d: Dictionary, key: String, t: int, file_path: String, field_path: String, issues: Array, strict: bool) -> void:
	if not d.has(key):
		_push_issue(issues, "error" if strict else "warning", file_path, field_path, "missing_field")
		return
	if typeof(d[key]) != t:
		_push_issue(issues, "error" if strict else "warning", file_path, field_path, "type_mismatch_expected_%s" % _type_name(t))


static func _push_issue(issues: Array, severity: String, file_path: String, field_path: String, message: String) -> void:
	issues.append({
		"severity": severity,
		"file_path": file_path,
		"field_path": field_path,
		"message": message,
	})


static func _type_name(t: int) -> String:
	match t:
		TYPE_NIL: return "nil"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "string"
		TYPE_ARRAY: return "array"
		TYPE_DICTIONARY: return "dictionary"
		_: return "type_%d" % t
