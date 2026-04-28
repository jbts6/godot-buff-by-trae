class_name OmniManifestLoader
extends RefCounted

class Result:
	var manifest: Dictionary
	var enums: Dictionary
	var sources: Dictionary = {}
	var source_paths: Dictionary = {}
	var issues: Array[OmniValidate.Issue] = []
	var mod_conflicts: Array = []

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

static func load_dataset_full(manifest_path: String, strict: bool) -> Result:
	var res := load_dataset(manifest_path, strict)

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

	_apply_mod_overrides(manifest_path, res, strict)

	var extra := OmniValidate.validate_all(manifest_path, res.manifest, res.enums, res.sources, strict)
	for i in extra:
		res.issues.append(i)

	return res

static func _apply_mod_overrides(manifest_path: String, res: Result, strict: bool) -> void:
	var mod_cfg: Dictionary = res.manifest.get("mod_overrides", {})
	if mod_cfg.is_empty():
		return
	var mods: Array = res.manifest.get("mods", [])
	if mods.is_empty():
		return
	var policy := String(mod_cfg.get("policy", "last_wins_by_id"))
	var report_conflicts: bool = bool(mod_cfg.get("report_conflicts", true))

	for mod_entry in mods:
		var mod_dir := String(mod_entry.get("dir", ""))
		if mod_dir == "":
			continue
		var mod_path := _resolve_relative(manifest_path, mod_dir)
		var da = DirAccess.open(mod_path)
		if da == null:
			res.issues.append(OmniValidate.warning(mod_path, "root", "", "mod directory not found"))
			continue
		da.list_dir_begin()
		var fn := da.get_next()
		while fn != "":
			if fn.ends_with(".json"):
				var full_path := mod_path.path_join(fn)
				var mod_data: Dictionary = OmniJson.load_dict(full_path)
				if mod_data.is_empty():
					fn = da.get_next()
					continue
				var mod_type := String(mod_data.get("type", ""))
				if mod_type == "":
					fn = da.get_next()
					continue
				if not res.sources.has(mod_type):
					res.sources[mod_type] = _empty_source_for_type(mod_type)
					res.source_paths[mod_type] = full_path
				_merge_mod_into_source(res, mod_type, mod_data, full_path, policy, report_conflicts)
			fn = da.get_next()
		da.list_dir_end()

static func _empty_source_for_type(mod_type: String) -> Variant:
	match mod_type:
		"buff_defs":
			return {"buffs": []}
		"skill_defs":
			return {"skills": []}
		"stat_defs":
			return {"stats": []}
		"damage_pipeline":
			return {"pipeline": []}
		"set_bonus":
			return {"sets": []}
		_:
			return {}

static func _merge_mod_into_source(res: Result, mod_type: String, mod_data: Dictionary, mod_path: String, policy: String, report_conflicts: bool) -> void:
	var list_key := _list_key_for_type(mod_type)
	if list_key == "":
		return
	var base_src = res.sources.get(mod_type, {})
	var base_list: Array = base_src.get(list_key, []) if base_src is Dictionary else []
	var mod_list: Array = mod_data.get(list_key, []) if mod_data is Dictionary else []
	if mod_list.is_empty():
		return
	if policy == "last_wins_by_id":
		var id_set: Dictionary = {}
		for i in range(base_list.size()):
			var entry = base_list[i]
			if entry is Dictionary and entry.has("id"):
				id_set[String(entry.get("id", ""))] = i
		for mod_entry in mod_list:
			if not (mod_entry is Dictionary and mod_entry.has("id")):
				continue
			var entry_id := String(mod_entry.get("id", ""))
			if id_set.has(entry_id):
				var base_idx: int = int(id_set[entry_id])
				if report_conflicts:
					var base_entry = base_list[base_idx]
					res.mod_conflicts.append({
						"type": mod_type,
						"id": entry_id,
						"base_index": base_idx,
						"mod_path": mod_path,
						"action": "replace"
					})
				base_list[base_idx] = mod_entry
			else:
				base_list.append(mod_entry)
				id_set[entry_id] = base_list.size() - 1
		if base_src is Dictionary:
			base_src[list_key] = base_list

static func _list_key_for_type(mod_type: String) -> String:
	match mod_type:
		"buff_defs":
			return "buffs"
		"skill_defs":
			return "skills"
		"stat_defs":
			return "stats"
		"damage_pipeline":
			return "pipeline"
		"set_bonus":
			return "sets"
		"equipment":
			return "rows"
		_:
			return ""

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
