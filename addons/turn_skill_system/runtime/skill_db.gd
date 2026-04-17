extends RefCounted
class_name SkillDB

const JsonIO := preload("res://addons/turn_skill_system/runtime/json_io.gd")
const SkillValidator := preload("res://addons/turn_skill_system/runtime/skill_validator.gd")

const INDEX_PATH := "res://addons/turn_skill_system/data/skills/index.json"

var _index_by_id: Dictionary = {} # skill_id -> entry
var _cache_by_id: Dictionary = {} # skill_id -> {"skill":Dictionary,"mtime":int}

func reload_index() -> Dictionary:
	_index_by_id.clear()
	var r := JsonIO.read_json(INDEX_PATH)
	if not bool(r.get("ok", false)):
		return {"ok": false, "errors": ["index_open_failed"], "path": INDEX_PATH}
	if typeof(r.get("data")) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["index_invalid_json"], "path": INDEX_PATH}

	var data: Dictionary = r.get("data", {})
	var skills: Array = data.get("skills", [])
	if typeof(skills) != TYPE_ARRAY:
		return {"ok": false, "errors": ["index_missing_skills_array"], "path": INDEX_PATH}

	for e in skills:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id := String(e.get("id", ""))
		if id == "":
			continue
		_index_by_id[id] = e
	return {"ok": true}


func clear_cache() -> void:
	_cache_by_id.clear()


func refresh_skill(skill_id: String) -> void:
	_cache_by_id.erase(skill_id)


func get_skill(skill_id: String, strict := true) -> Dictionary:
	if not _index_by_id.has(skill_id):
		return {"ok": false, "errors": ["unknown_skill_id:%s" % skill_id]}

	var entry: Dictionary = _index_by_id[skill_id]
	var path := String(entry.get("path", ""))
	if path == "":
		return {"ok": false, "errors": ["index_entry_missing_path:%s" % skill_id]}

	var mtime := int(entry.get("mtime_unix", 0))
	if _cache_by_id.has(skill_id):
		var cached: Dictionary = _cache_by_id[skill_id]
		if int(cached.get("mtime", -1)) == mtime:
			return {"ok": true, "skill": cached["skill"], "issues": cached.get("issues", [])}

	var r := JsonIO.read_json(path)
	if not bool(r.get("ok", false)):
		return {"ok": false, "errors": ["skill_open_failed:%s" % path]}
	if typeof(r.get("data")) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["skill_json_must_be_object:%s" % path]}

	var skill: Dictionary = r.get("data", {})
	if String(skill.get("type", "")) == "active":
		SkillValidator.normalize_active_in_place(skill)

	var issues := SkillValidator.validate_skill(skill, path, strict)
	var has_error := false
	for it in issues:
		if String(it.get("severity", "")) == "error":
			has_error = true
			break
	if strict and has_error:
		return {"ok": false, "errors": ["skill_validation_failed:%s" % skill_id], "issues": issues}

	_cache_by_id[skill_id] = {"skill": skill, "mtime": mtime, "issues": issues}
	return {"ok": true, "skill": skill, "issues": issues}
