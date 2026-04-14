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
var enums_rt: OmniEnumsRuntime
var event_index: OmniEventIndex
var next_inst_id := 1
var _triggered_inst_ids_last_emit: PackedInt32Array = PackedInt32Array()

func _init(dataset: OmniCompiledDataset, enums_runtime: OmniEnumsRuntime = null) -> void:
	ds = dataset
	enums_rt = enums_runtime
	if enums_rt != null:
		var event_type_count := max(1, enums_rt.enum_count("event_type"))
		event_index = OmniEventIndex.new(event_type_count * OmniEventIndex.PHASE_COUNT)
	else:
		event_index = OmniEventIndex.new(1)

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

	# triggers -> EventIndex
	if enums_rt != null:
		var triggers: Array = ds.buff_defs[bdid].get("triggers", [])
		for t in triggers:
			var et_str := String(t.get("event_type", ""))
			var ph_str := String(t.get("event_phase", ""))
			var et := enums_rt.enum_int("event_type", et_str)
			var ph := enums_rt.enum_int("event_phase", ph_str)
			if et < 0 or ph < 0:
				continue
			var key := et * OmniEventIndex.PHASE_COUNT + ph

			var filters: Dictionary = t.get("filters", {})
			var tag_any: Array = filters.get("tag_mask_any", [])
			var filter_mask := enums_rt.tag_mask(tag_any)

			var action: Dictionary = t.get("action", {})
			var l := OmniEventIndex.Listener.new()
			l.inst_id = inst.inst_id
			l.filter_tag_mask = filter_mask
			l.action_kind = String(action.get("kind", ""))
			l.action_value = float(action.get("value", 0.0))
			event_index.register_listener(key, l)

	return inst.inst_id

func emit_event(event_type: String, phase: String, ctx: RefCounted) -> void:
	_triggered_inst_ids_last_emit = PackedInt32Array()
	if enums_rt == null:
		return
	var et := enums_rt.enum_int("event_type", event_type)
	var ph := enums_rt.enum_int("event_phase", phase)
	if et < 0 or ph < 0:
		return
	var key := et * OmniEventIndex.PHASE_COUNT + ph
	var arr := event_index.get_listeners_for(key)
	for lid in arr:
		var l := event_index.listener_data[lid]
		if l.filter_tag_mask != 0:
			if (int(ctx.tags_mask) & l.filter_tag_mask) == 0:
				continue
		_triggered_inst_ids_last_emit.append(l.inst_id)
		match l.action_kind:
			"ADD_BASE_DAMAGE":
				ctx.base_damage += l.action_value
			_:
				pass

func get_triggered_inst_ids_last_emit() -> PackedInt32Array:
	return _triggered_inst_ids_last_emit
