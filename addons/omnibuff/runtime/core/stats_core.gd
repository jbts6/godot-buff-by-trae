class_name OmniStatsCore
extends RefCounted

var ds: OmniCompiledDataset
var base_values: PackedFloat32Array
var final_values: PackedFloat32Array
var dirty: PackedByteArray

# 后续 Task 6 会把“stat->modifier列表”注入这里（本Task先做base-only）
var modifiers_by_stat: Array = []

func _init(dataset: OmniCompiledDataset) -> void:
	ds = dataset
	var n := ds.stat_defs.size()
	base_values = PackedFloat32Array()
	base_values.resize(n)
	final_values = PackedFloat32Array()
	final_values.resize(n)
	dirty = PackedByteArray()
	dirty.resize(n)
	modifiers_by_stat.resize(n)
	for i in range(n):
		base_values[i] = float(ds.stat_defs[i].get("default", 0.0))
		final_values[i] = base_values[i]
		dirty[i] = 0
		modifiers_by_stat[i] = []

func set_base(stat_id: int, v: float) -> void:
	base_values[stat_id] = v
	dirty[stat_id] = 1

func add_base(stat_id: int, dv: float) -> void:
	base_values[stat_id] += dv
	dirty[stat_id] = 1

func mark_dirty(stat_id: int) -> void:
	dirty[stat_id] = 1

func recompute(stat_id: int) -> void:
	var v := base_values[stat_id]
	for m in modifiers_by_stat[stat_id]:
		v += float(m.add_value)
	final_values[stat_id] = v

func get_final(stat_id: int) -> float:
	if dirty[stat_id] == 1:
		recompute(stat_id)
		dirty[stat_id] = 0
	return final_values[stat_id]
