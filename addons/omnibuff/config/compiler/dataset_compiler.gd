class_name OmniDatasetCompiler
extends RefCounted

static func compile(manifest: Dictionary, enums_rt: OmniEnumsRuntime, sources: Dictionary) -> OmniCompiledDataset:
	var ds := OmniCompiledDataset.new()

	var stat_defs: Array = sources.get("stat_defs", {}).get("stats", [])
	for i in range(stat_defs.size()):
		var s: Dictionary = stat_defs[i]
		ds.stat_id_to_int[String(s["id"])] = i
		ds.stat_defs.append(s)

	var n := ds.stat_defs.size()
	ds.derived_defs_by_stat.resize(n)
	ds.derived_inputs_by_stat.resize(n)
	ds.derived_dependents_by_stat.resize(n)
	for i in range(n):
		ds.derived_defs_by_stat[i] = {}
		ds.derived_inputs_by_stat[i] = PackedInt32Array()
		ds.derived_dependents_by_stat[i] = PackedInt32Array()

	for sid in range(n):
		var sdef: Dictionary = ds.stat_defs[sid]
		if not sdef.has("derived"):
			continue
		var d: Dictionary = sdef.get("derived", {})
		if typeof(d) != TYPE_DICTIONARY:
			continue
		ds.derived_defs_by_stat[sid] = d
		var inputs := PackedInt32Array()
		var seen_dep := {}
		var dt := String(d.get("type", "")).to_upper()
		if dt == "LINEAR":
			var from_name := String(d.get("from", ""))
			var from_id := int(ds.stat_id(from_name))
			if from_id >= 0 and (not seen_dep.has(from_id)):
				seen_dep[from_id] = true
				inputs.append(from_id)
		elif dt == "EXPR":
			for name in d.get("inputs", []):
				var dep_name := String(name)
				var dep := int(ds.stat_id(dep_name))
				if dep >= 0 and (not seen_dep.has(dep)):
					seen_dep[dep] = true
					inputs.append(dep)
		ds.derived_inputs_by_stat[sid] = inputs
		for dep in inputs:
			var arr_dep: PackedInt32Array = ds.derived_dependents_by_stat[int(dep)]
			arr_dep.append(int(sid))
			ds.derived_dependents_by_stat[int(dep)] = arr_dep

	var indeg := PackedInt32Array()
	indeg.resize(n)
	for sid in range(n):
		indeg[sid] = 0
	for sid in range(n):
		for dep in ds.derived_inputs_by_stat[sid]:
			indeg[sid] += 1

	var q: Array[int] = []
	for sid in range(n):
		if indeg[sid] == 0:
			q.append(sid)

	var order := PackedInt32Array()
	while not q.is_empty():
		var cur := int(q.pop_front())
		order.append(cur)
		for nxt in ds.derived_dependents_by_stat[cur]:
			indeg[int(nxt)] -= 1
			if indeg[int(nxt)] == 0:
				q.append(int(nxt))
	if order.size() != n:
		order = PackedInt32Array()
	ds.derived_topo_order = order

	var buff_defs: Array = sources.get("buff_defs", {}).get("buffs", [])
	for i in range(buff_defs.size()):
		var b: Dictionary = buff_defs[i]
		ds.buff_id_to_int[String(b["id"])] = i
		ds.buff_defs.append(b)

	var skill_defs: Array = sources.get("skill_defs", {}).get("skills", [])
	for i in range(skill_defs.size()):
		var sk: Dictionary = skill_defs[i]
		ds.skill_id_to_int[String(sk.get("id", ""))] = i
		ds.skill_defs.append(sk)

	var equip_raw = sources.get("equipment", [])
	var equip_rows: Array = []
	if not equip_raw is Array:
		equip_raw = []
	if equip_raw.size() > 0:
		var first = equip_raw[0]
		if first is OmniCsv.Row:
			var header: PackedStringArray = first.cols
			for ri in range(1, equip_raw.size()):
				var row: OmniCsv.Row = equip_raw[ri]
				var d := {}
				for ci in range(header.size()):
					if ci < row.cols.size():
						d[String(header[ci])] = String(row.cols[ci])
				equip_rows.append(d)
		else:
			equip_rows = equip_raw
	for i in range(equip_rows.size()):
		var eq: Dictionary = equip_rows[i]
		var eid := String(eq.get("id", ""))
		if eid != "":
			ds.equipment_id_to_int[eid] = i
		ds.equipment_defs.append(eq)

	var sb_obj: Dictionary = sources.get("set_bonus", {})
	var sets: Array = sb_obj.get("sets", [])
	for i in range(sets.size()):
		ds.set_bonus_defs.append(sets[i])

	var pipe_obj: Dictionary = sources.get("damage_pipeline", {})
	var stages: Array = pipe_obj.get("pipeline", [])
	for i in range(stages.size()):
		ds.pipeline_stages.append(stages[i])

	ds.fingerprint = _compute_fingerprint(sources)

	return ds


static func _compute_fingerprint(sources: Dictionary) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	var keys: Array = sources.keys()
	keys.sort()
	for k in keys:
		var v = sources[k]
		var json_str := JSON.stringify(v, "", false)
		hasher.update(json_str.to_utf8_buffer())
	var digest := hasher.finish()
	return digest.hex_encode()
