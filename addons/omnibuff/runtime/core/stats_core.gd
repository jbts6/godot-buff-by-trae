class_name OmniStatsCore
extends RefCounted

var ds: OmniCompiledDataset

var base_values: PackedFloat32Array
var computed_base: PackedFloat32Array
var final_values: PackedFloat32Array
var dirty: PackedByteArray
var modifiers_by_stat: Array = []

func _init(dataset: OmniCompiledDataset) -> void:
	ds = dataset
	var n := ds.stat_defs.size()
	base_values = PackedFloat32Array()
	base_values.resize(n)
	final_values = PackedFloat32Array()
	final_values.resize(n)
	computed_base = PackedFloat32Array()
	computed_base.resize(n)
	dirty = PackedByteArray()
	dirty.resize(n)
	modifiers_by_stat.resize(n)
	for i in range(n):
		base_values[i] = float(ds.stat_defs[i].get("default", 0.0))
		computed_base[i] = 0.0
		final_values[i] = base_values[i]
		dirty[i] = 0
		modifiers_by_stat[i] = []

func set_base(stat_id: int, v: float) -> void:
	base_values[stat_id] = v
	mark_dirty(stat_id)

func add_base(stat_id: int, dv: float) -> void:
	base_values[stat_id] += dv
	mark_dirty(stat_id)

func mark_dirty(stat_id: int) -> void:
	dirty[stat_id] = 1
	if ds == null:
		return
	if ds.derived_dependents_by_stat.size() == 0:
		return
	if stat_id < 0 or stat_id >= ds.derived_dependents_by_stat.size():
		return
	var deps: PackedInt32Array = ds.derived_dependents_by_stat[stat_id]
	for sid in deps:
		dirty[int(sid)] = 1


func _recompute_computed_base_for(stat_id: int) -> void:
	if ds == null:
		computed_base[stat_id] = 0.0
		return
	if ds.derived_from_int.size() == 0:
		computed_base[stat_id] = 0.0
		return
	if stat_id < 0 or stat_id >= ds.derived_from_int.size():
		computed_base[stat_id] = 0.0
		return
	var from_id: int = int(ds.derived_from_int[stat_id])
	var ratio: float = float(ds.derived_ratio[stat_id])
	if from_id >= 0 and ratio != 0.0:
		computed_base[stat_id] = get_final(from_id) * ratio
		return
	computed_base[stat_id] = 0.0

func recompute(stat_id: int) -> void:
	_recompute_computed_base_for(stat_id)
	var base := base_values[stat_id] + computed_base[stat_id]
	var flat := 0.0
	var pct_by_layer: Dictionary = {}
	var final_add := 0.0
	var has_override := false
	var override_v := 0.0
	var override_pri := -2147483648
	var override_src := -2147483648
	for m in modifiers_by_stat[stat_id]:
		if m == null or typeof(m) != TYPE_OBJECT:
			continue
		var op_i: int = int(m.op_int)
		var ph_i: int = int(m.phase_int)
		var val := float(m.value)
		if op_i == 0 and ph_i == 2:
			flat += val
		elif op_i == 1 and ph_i == 3:
			var layer: int = int(m.layer)
			if not pct_by_layer.has(layer):
				pct_by_layer[layer] = 0.0
			pct_by_layer[layer] = float(pct_by_layer[layer]) + val
		elif op_i == 0 and ph_i == 4:
			final_add += val
		elif op_i == 2 and ph_i == 4:
			var pri := int(m.priority)
			var src := int(m.source_inst_id)
			if (not has_override) or (pri > override_pri) or (pri == override_pri and src > override_src):
				has_override = true
				override_pri = pri
				override_src = src
				override_v = val

	var v := (base + flat)
	if not pct_by_layer.is_empty():
		var layers: Array = pct_by_layer.keys()
		layers.sort()
		for l in layers:
			v *= (1.0 + float(pct_by_layer[l]))
	if has_override:
		v = override_v
	v += final_add

	v = _apply_curve(stat_id, v)

	var def: Dictionary = ds.stat_defs[stat_id]
	if bool(def.get("clamp", false)):
		v = clamp(v, float(def.get("min", v)), float(def.get("max", v)))
	final_values[stat_id] = v


func _apply_curve(stat_id: int, v: float) -> float:
	var def: Dictionary = ds.stat_defs[stat_id]
	if not def.has("curve"):
		return v
	var c: Dictionary = def.get("curve", {})
	if typeof(c) != TYPE_DICTIONARY:
		return v
	var apply_at := String(c.get("apply_at", "POST_FINAL")).to_upper()
	if apply_at != "" and apply_at != "POST_FINAL":
		return v
	var ct := String(c.get("type", "")).to_upper()
	if ct == "" or ct == "NONE":
		return v
	if ct == "DR_SOFTCAP":
		var k := float(c.get("k", 0.0))
		if k <= 0.0:
			return v
		return v / (v + k)
	if ct == "EXP":
		var a := float(c.get("a", 1.0))
		var b := float(c.get("b", 1.0))
		var cc := float(c.get("c", 0.0))
		return a * exp(b * v) + cc
	if ct == "LOG":
		var a2 := float(c.get("a", 1.0))
		var b2 := float(c.get("b", 1.0))
		var c2 := float(c.get("c", 0.0))
		var d2 := float(c.get("d", 0.0))
		var x := b2 * v + c2
		if x <= 0.0:
			return v
		return a2 * log(x) + d2
	return v

func get_final(stat_id: int) -> float:
	if dirty[stat_id] == 1:
		recompute(stat_id)
		dirty[stat_id] = 0
	return final_values[stat_id]


func get_breakdown(stat_id: int) -> Dictionary:
	var final_v := get_final(stat_id)
	var base_v := float(base_values[stat_id])
	if computed_base.size() > 0:
		base_v += float(computed_base[stat_id])
	return {"base": base_v, "bonus": final_v - base_v, "final": final_v}
