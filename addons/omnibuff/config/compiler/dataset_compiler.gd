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
	ds.derived_from_int = PackedInt32Array()
	ds.derived_from_int.resize(n)
	ds.derived_ratio = PackedFloat32Array()
	ds.derived_ratio.resize(n)
	for i in range(n):
		ds.derived_defs_by_stat[i] = {}
		ds.derived_inputs_by_stat[i] = PackedInt32Array()
		ds.derived_dependents_by_stat[i] = PackedInt32Array()
		ds.derived_from_int[i] = -1
		ds.derived_ratio[i] = 0.0

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
			ds.derived_from_int[sid] = from_id
			ds.derived_ratio[sid] = float(d.get("ratio", 0.0))
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
		ds.buff_defs_compiled.append(_compile_buff_def(b, i, ds, enums_rt))

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


const CBD = preload("res://addons/omnibuff/runtime/core/compiled_buff_def.gd")

static func _compile_buff_def(b: Dictionary, idx: int, ds: OmniCompiledDataset, enums_rt: OmniEnumsRuntime) -> RefCounted:
	var c = CBD.BuffDefCompiled.new()
	c.buff_id_str = String(b.get("id", ""))
	c.buff_type_int = int(enums_rt.enum_int("buff_type", String(b.get("buff_type", ""))))
	c.tag_mask = int(enums_rt.tag_mask(b.get("tags", [])))

	var dur: Dictionary = b.get("duration", {})
	c.duration_type_int = int(enums_rt.enum_int("duration_type", String(dur.get("type", ""))))
	c.duration_turns = int(dur.get("turns", -1))
	c.tick_phase_int = int(enums_rt.enum_int("event_phase", String(dur.get("tick_phase", "TURN_END"))))

	var stk: Dictionary = b.get("stack", {})
	c.stack_mode_int = int(enums_rt.enum_int("stack_mode", String(stk.get("mode", "REPLACE"))))
	c.stack_max = int(stk.get("max_stack", 1))
	c.ownership_mode_int = int(enums_rt.enum_int("ownership_mode", String(stk.get("ownership_mode", "GLOBAL"))))
	c.refresh_policy_int = int(enums_rt.enum_int("refresh_policy", String(stk.get("refresh_policy", ""))))

	var disp: Dictionary = b.get("dispel", {})
	c.undispellable = (bool(disp.get("dispellable", true)) == false)

	for e in b.get("effects", []):
		var ed: Dictionary = e
		var ce = CBD.EffectCompiled.new()
		var op_s := String(ed.get("op", ""))
		var phase_s := String(ed.get("phase", ""))
		ce.stat_int = int(ds.stat_id(String(ed.get("stat", ""))))
		ce.op_int = int(enums_rt.enum_int("op_type", op_s))
		ce.op_str = op_s
		ce.phase_int = int(enums_rt.enum_int("apply_phase", phase_s))
		ce.phase_str = phase_s
		ce.value = float(ed.get("value", 0.0))
		ce.layer = int(ed.get("layer", 0))
		ce.priority = int(ed.get("priority", 0))
		c.effects.append(ce)

	for t in b.get("triggers", []):
		var td: Dictionary = t
		var ct = CBD.TriggerCompiled.new()
		ct.event_type_int = int(enums_rt.enum_int("event_type", String(td.get("event_type", ""))))
		ct.event_phase_int = int(enums_rt.enum_int("event_phase", String(td.get("event_phase", ""))))
		ct.scope_str = String(td.get("scope", "SELF"))
		ct.filters = _compile_filters(td.get("filters", {}), enums_rt, ds)
		ct.action = _compile_action(td.get("action", {}), enums_rt, ds)
		c.triggers.append(ct)

	for cond in b.get("conditions", []):
		var cd: Dictionary = cond
		var cc = CBD.ConditionCompiled.new()
		cc.type_int = int(enums_rt.enum_int("condition_type", String(cd.get("condition_type", ""))))
		cc.stat_int = int(ds.stat_id(String(cd.get("stat", ""))))
		cc.op = String(cd.get("op", "LE"))
		cc.value = float(cd.get("value", 0.0))
		cc.set_id = String(cd.get("set_id", ""))
		cc.count = int(cd.get("count", 0))
		cc.tag_mask = int(enums_rt.tag_mask(cd.get("tag", []) if cd.get("tag", []) is Array else [cd.get("tag", "")]))
		c.conditions.append(cc)

	var dot_def: Dictionary = b.get("dot", {})
	if not dot_def.is_empty():
		var cdot = CBD.DotCompiled.new()
		cdot.tick_phase_int = int(enums_rt.enum_int("event_phase", String(dot_def.get("tick_phase", "TURN_END"))))
		cdot.element_int = int(enums_rt.enum_int("element", String(dot_def.get("element", "NONE"))))
		cdot.base_ratio = float(dot_def.get("base_ratio", 0.0))
		cdot.read_source_stat_int = int(ds.stat_id(String(dot_def.get("read_source_stat", "ATK"))))
		c.dot = cdot

	return c


static func _compile_filters(f: Dictionary, enums_rt: OmniEnumsRuntime, ds: OmniCompiledDataset) -> RefCounted:
	var cf = CBD.FilterCompiled.new()
	cf.tag_mask = int(enums_rt.tag_mask(f.get("tag_mask_any", [])))
	cf.require_hit = bool(f.get("require_hit", false))
	cf.require_crit = bool(f.get("require_crit", false))
	cf.skill_id = int(f.get("skill_id", -1))
	var dt_any: Array = f.get("damage_type_any", [])
	if not dt_any.is_empty():
		var m := 0
		for dt in dt_any:
			var code: int = int(enums_rt.enum_int("damage_type", String(dt)))
			if code >= 0:
				m |= (1 << code)
		cf.damage_type_mask = m
	var el_any: Array = f.get("element_any", [])
	if not el_any.is_empty():
		var m2 := 0
		for el in el_any:
			var code2: int = int(enums_rt.enum_int("element", String(el)))
			if code2 >= 0:
				m2 |= (1 << code2)
		cf.element_mask = m2
	cf.require_shield_absorbed = bool(f.get("require_shield_absorbed", false))
	cf.min_absorbed_shield = float(f.get("min_absorbed_shield", 0.0))
	cf.min_final_damage = float(f.get("min_final_damage", 0.0))
	cf.require_not_bonus_damage = bool(f.get("require_not_bonus_damage", false))
	var ck_any: Array = f.get("command_kind_any", [])
	if not ck_any.is_empty():
		var m3 := 0
		for ck in ck_any:
			var code3: int = int(enums_rt.enum_int("command_kind", String(ck)))
			if code3 >= 0:
				m3 |= (1 << code3)
		cf.command_kind_mask = m3
	cf.item_id = int(f.get("item_id", -1))
	cf.actor_id = int(f.get("actor_id", -1))
	cf.source_id = int(f.get("source_id", -1))
	var std: Dictionary = f.get("stat_threshold", {})
	if not std.is_empty():
		cf.stat_threshold_scope = String(std.get("scope", ""))
		cf.stat_threshold_stat_int = int(ds.stat_id(String(std.get("stat", ""))))
		cf.stat_threshold_op = String(std.get("op", ""))
		cf.stat_threshold_value = float(std.get("value", 0.0))
	return cf


static func _compile_action(a: Dictionary, enums_rt: OmniEnumsRuntime, ds: OmniCompiledDataset) -> RefCounted:
	var ca = CBD.ActionCompiled.new()
	ca.kind_int = int(enums_rt.enum_int("action_kind", String(a.get("kind", ""))))
	ca.value = float(a.get("value", 0.0))
	ca.ratio = float(a.get("ratio", 0.0))
	var bid_str := String(a.get("buff_id", ""))
	if bid_str == "":
		bid_str = String(a.get("apply_buff_id", ""))
	ca.buff_def_id = int(ds.buff_id(bid_str))
	ca.add_stacks = int(a.get("add_stacks", 1))
	ca.chance = float(a.get("chance", 1.0))
	ca.stat_int = int(ds.stat_id(String(a.get("stat", ""))))
	ca.dispel_mode_int = int(enums_rt.enum_int("dispel_scope", String(a.get("mode", ""))))
	ca.dispel_tag_mask = int(enums_rt.tag_mask([a.get("tag", "")] if a.get("tag", "") != "" else []))
	ca.dispel_buff_type_int = int(enums_rt.enum_int("buff_type", String(a.get("buff_type", ""))))
	ca.dispel_source_scope = String(a.get("source", ""))
	ca.include_implicit = bool(a.get("include_implicit", false))
	var dot_bid := String(a.get("dot_buff_id", ""))
	ca.dot_buff_def_id = int(ds.buff_id(dot_bid))
	var dot_tags: Array = a.get("dot_tags_mask_any", [])
	ca.dot_tag_mask = int(enums_rt.tag_mask(dot_tags))
	var bonus_tags: Array = a.get("tags_mask_any", [])
	ca.bonus_tags_mask = int(enums_rt.tag_mask(bonus_tags))
	ca.bonus_scope = String(a.get("scope", "TARGET"))
	ca.bonus_min_damage = float(a.get("min_damage", 0.0))
	ca.bonus_max_damage = float(a.get("max_damage", 0.0))
	ca.bonus_round_mode = String(a.get("round_mode", ""))
	ca.expr = String(a.get("expr", ""))
	ca.delta = int(a.get("delta", 0))
	ca.min_stack = int(a.get("min_stack", 0))
	ca.max_stack = int(a.get("max_stack", 0))
	return ca
