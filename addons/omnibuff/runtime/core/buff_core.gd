class_name OmniBuffCore
extends RefCounted

class OmniModifierRef:
	var stat_id: int
	var add_value: float
	var source_inst_id: int

class BuffInst:
	var inst_id: int
	var buff_def_id: int
	var source_entity_id: int
	var stacks: int
	var remaining_turns: int
	var modifier_refs: Array[OmniModifierRef] = []

var ds: OmniCompiledDataset
var next_inst_id := 1

func _init(dataset: OmniCompiledDataset) -> void:
	ds = dataset

func apply_buff(stats: OmniStatsComponent, buff_id_str: String, source_entity_id: int) -> int:
	var bdid := ds.buff_id(buff_id_str)
	if bdid < 0:
		push_error("[Buff] unknown buff_id=" + buff_id_str)
		return -1

	var inst := BuffInst.new()
	inst.inst_id = next_inst_id
	next_inst_id += 1
	inst.buff_def_id = bdid
	inst.source_entity_id = source_entity_id
	inst.stacks = 1
	inst.remaining_turns = int(ds.buff_defs[bdid].get("duration", {}).get("turns", -1))

	var effects: Array = ds.buff_defs[bdid].get("effects", [])
	for e in effects:
		if String(e.get("kind", "")) != "modifier":
			continue
		if String(e.get("op", "")) != "ADD":
			continue
		if String(e.get("phase", "")) != "FLAT":
			continue

		var stat_id := ds.stat_id(String(e.get("stat", "")))
		if stat_id < 0:
			push_error("[Buff] unknown stat in effect: " + str(e))
			continue
		var v := float(e.get("value", 0.0))

		var mr := OmniModifierRef.new()
		mr.stat_id = stat_id
		mr.add_value = v
		mr.source_inst_id = inst.inst_id

		inst.modifier_refs.append(mr)
		stats.core.modifiers_by_stat[stat_id].append(mr)
		stats.core.mark_dirty(stat_id)

	return inst.inst_id

