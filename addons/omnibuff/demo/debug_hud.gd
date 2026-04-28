extends Window

## OmniBuff Debug HUD（Demo-only）
##
## - 仅用于 demo 场景（不接入主游戏）
## - HUD 不维护全局实体注册表；只接受 demo 传入 runtime：
##   runtime = { "stats_by_entity": {eid:StatsComponent}, "buff_by_entity": {eid:BuffCore} }

const DUMP_MAX_CHARS := 20000
const MAX_EVENT_TRACES := 500

@onready var entity_select: OptionButton = %EntitySelect
@onready var stats_box: RichTextLabel = %StatsBox
@onready var buffs_box: RichTextLabel = %BuffsBox
@onready var dots_box: RichTextLabel = %DotsBox
@onready var listeners_box: RichTextLabel = %ListenersBox
@onready var stat_mods_box: RichTextLabel = %StatModsBox
@onready var btn_copy_dump: Button = %BtnCopyDump
@onready var btn_close: Button = %BtnClose
@onready var stats_edit_area: GridContainer = %StatsEditArea
@onready var buff_id_input: LineEdit = %BuffIdInput
@onready var btn_apply_buff: Button = %BtnApplyBuff
@onready var inst_id_input: SpinBox = %InstIdInput
@onready var btn_remove_buff: Button = %BtnRemoveBuff
@onready var timeline_box: RichTextLabel = %TimelineBox
@onready var btn_clear_timeline: Button = %BtnClearTimeline
@onready var timeline_count: Label = %TimelineCount

var _runtime: Dictionary = {}
var _selected_eid: int = -1
var _preferred_attacker: int = -1
var _preferred_defender: int = -1
var _stat_spinboxes: Dictionary = {}
var _event_traces: Array = []


func _ready() -> void:
	btn_copy_dump.pressed.connect(_copy_dump)
	btn_close.pressed.connect(func(): hide())
	entity_select.item_selected.connect(func(_idx: int):
		var eid: int = int(entity_select.get_item_metadata(entity_select.selected))
		set_selected_entity(eid)
	)
	btn_apply_buff.pressed.connect(_on_apply_buff)
	btn_remove_buff.pressed.connect(_on_remove_buff)
	btn_clear_timeline.pressed.connect(_on_clear_timeline)


func clear() -> void:
	_runtime = {}
	_selected_eid = -1
	_preferred_attacker = -1
	_preferred_defender = -1
	entity_select.clear()
	stats_box.text = ""
	buffs_box.text = ""
	dots_box.text = ""
	listeners_box.text = ""
	stat_mods_box.text = ""
	_stat_spinboxes = {}
	for c in stats_edit_area.get_children():
		c.queue_free()
	_event_traces = []
	timeline_box.text = ""
	timeline_count.text = "0 events"


func set_preferred_entities(attacker_id: int, defender_id: int) -> void:
	_preferred_attacker = attacker_id
	_preferred_defender = defender_id
	if not _runtime.is_empty():
		_refresh_entity_list()


func set_runtime(runtime: Dictionary) -> void:
	_runtime = runtime
	_refresh_entity_list()
	_install_event_trace_hooks()


func set_selected_entity(entity_id: int) -> void:
	_selected_eid = entity_id
	_rebuild_stat_spinboxes()
	_refresh_views()


func apply_buff_by_id(buff_id_str: String, source_entity_id: int) -> void:
	if _runtime.is_empty() or _selected_eid < 0:
		return
	var ds = _runtime.get("ds", null)
	var buffs_by_entity: Dictionary = _runtime.get("buff_by_entity", {})
	var stats_by_entity: Dictionary = _runtime.get("stats_by_entity", {})
	var buffs = buffs_by_entity.get(_selected_eid, null)
	var stats = stats_by_entity.get(_selected_eid, null)
	if buffs == null or stats == null or ds == null:
		return
	if not ds.has_method("buff_id"):
		return
	buffs.apply_buff(stats, buff_id_str, source_entity_id)
	_refresh_views()


func remove_buff_by_inst_id(inst_id: int) -> void:
	if _runtime.is_empty() or _selected_eid < 0:
		return
	var ds = _runtime.get("ds", null)
	var buffs_by_entity: Dictionary = _runtime.get("buff_by_entity", {})
	var stats_by_entity: Dictionary = _runtime.get("stats_by_entity", {})
	var buffs = buffs_by_entity.get(_selected_eid, null)
	var stats = stats_by_entity.get(_selected_eid, null)
	if buffs == null or stats == null or ds == null:
		return
	var inst = buffs.instances_by_id.get(inst_id, null)
	if inst == null:
		return
	buffs.remove_buff(stats, inst_id)
	_refresh_views()


func set_stat_base(stat_name: String, value: float) -> void:
	if _runtime.is_empty() or _selected_eid < 0:
		return
	var ds = _runtime.get("ds", null)
	var stats_by_entity: Dictionary = _runtime.get("stats_by_entity", {})
	var stats = stats_by_entity.get(_selected_eid, null)
	if stats == null or ds == null:
		return
	if not ds.has_method("stat_id"):
		return
	var sid: int = ds.stat_id(stat_name)
	if sid < 0:
		return
	stats.core.set_base(sid, value)
	_refresh_views()


func _install_event_trace_hooks() -> void:
	var buffs_by_entity: Dictionary = _runtime.get("buff_by_entity", {})
	for eid in buffs_by_entity:
		var buffs = buffs_by_entity.get(eid, null)
		if buffs != null and buffs.has_method("set"):
			buffs.event_trace_fn = _on_event_trace.bind(eid)


func _on_event_trace(event_type: String, phase: String, hit_inst_ids: PackedInt32Array, entity_id: int) -> void:
	var trace = {
		"entity_id": entity_id,
		"event_type": event_type,
		"phase": phase,
		"hit_inst_ids": hit_inst_ids,
	}
	_event_traces.append(trace)
	if _event_traces.size() > MAX_EVENT_TRACES:
		_event_traces = _event_traces.slice(_event_traces.size() - MAX_EVENT_TRACES)
	timeline_count.text = "%d events" % _event_traces.size()
	_refresh_timeline()


func _on_clear_timeline() -> void:
	_event_traces = []
	timeline_box.text = ""
	timeline_count.text = "0 events"


func _refresh_timeline() -> void:
	var lines: Array[String] = []
	var enums_rt: Variant = _runtime.get("enums_rt", null)
	for i in range(_event_traces.size()):
		var t = _event_traces[i]
		var et_name: String = String(t.get("event_type", "?"))
		var ph_name: String = String(t.get("phase", "?"))
		var eid: int = int(t.get("entity_id", -1))
		var hit_ids: PackedInt32Array = t.get("hit_inst_ids", PackedInt32Array())
		var hit_str := str(hit_ids)
		if enums_rt != null and enums_rt is OmniEnumsRuntime:
			var et_int: int = int(enums_rt.enum_int("event_type", et_name))
			var ph_int: int = int(enums_rt.enum_int("event_phase", ph_name))
			if et_int >= 0:
				et_name = enums_rt.reverse_name("event_type", et_int)
			if ph_int >= 0:
				ph_name = enums_rt.reverse_name("event_phase", ph_int)
		var action_summaries: Array[String] = []
		var ds = _runtime.get("ds", null)
		var buffs_by_entity: Dictionary = _runtime.get("buff_by_entity", {})
		var buffs = buffs_by_entity.get(eid, null)
		if buffs != null and ds != null and ds.has_method("buff_id"):
			for iid in hit_ids:
				var inst = buffs.instances_by_id.get(int(iid), null)
				if inst != null:
					var bdid: int = int(inst.buff_def_id)
					if bdid >= 0 and bdid < ds.buff_defs.size():
						var def: Dictionary = ds.buff_defs[bdid]
						action_summaries.append(String(def.get("id", "?")))
		var actions_str := ""
		if not action_summaries.is_empty():
			actions_str = " actions=" + str(action_summaries)
		lines.append("[%s] eid=%s %s/%s hit=%s%s" % [
			i + 1, eid, et_name, ph_name, hit_str, actions_str
		])
	timeline_box.text = "\n".join(lines)


func _rebuild_stat_spinboxes() -> void:
	for c in stats_edit_area.get_children():
		c.queue_free()
	_stat_spinboxes = {}
	if _runtime.is_empty() or _selected_eid < 0:
		return
	var ds = _runtime.get("ds", null)
	var stats_by_entity: Dictionary = _runtime.get("stats_by_entity", {})
	var stats = stats_by_entity.get(_selected_eid, null)
	if stats == null or ds == null or not ds.has_method("stat_id"):
		return
	var names := ["ATK", "DEF", "HP", "SHIELD", "HIT_RATE", "EVADE", "CRIT_RATE", "CRIT_DMG", "DMG_REDUCE"]
	for n in names:
		var sid: int = ds.stat_id(String(n))
		if sid < 0:
			continue
		var lbl = Label.new()
		lbl.text = String(n)
		stats_edit_area.add_child(lbl)
		var spin = SpinBox.new()
		spin.min_value = -99999.0
		spin.max_value = 99999.0
		spin.step = 1.0
		spin.value = float(stats.core.base_values[sid])
		spin.suffix = " (base)"
		spin.custom_minimum_size = Vector2(120, 0)
		var stat_name := String(n)
		spin.value_changed.connect(func(val: float):
			set_stat_base(stat_name, val)
		)
		stats_edit_area.add_child(spin)
		_stat_spinboxes[n] = spin


func _on_apply_buff() -> void:
	var bid := buff_id_input.text.strip_edges()
	if bid == "":
		return
	var ds = _runtime.get("ds", null)
	if ds == null or not ds.has_method("buff_id"):
		return
	if ds.buff_id(bid) < 0:
		buffs_box.text = "[Error] buff_id '%s' not found in dataset" % bid
		return
	apply_buff_by_id(bid, _selected_eid)


func _on_remove_buff() -> void:
	var iid: int = int(inst_id_input.value)
	if iid < 0:
		return
	remove_buff_by_inst_id(iid)


func _refresh_entity_list() -> void:
	entity_select.clear()
	if _runtime.is_empty():
		return
	var stats_by_entity: Dictionary = _runtime.get("stats_by_entity", {})
	var ids: Array = stats_by_entity.keys()
	ids.sort()
	for i in range(ids.size()):
		var eid: int = int(ids[i])
		entity_select.add_item(str(eid))
		entity_select.set_item_metadata(entity_select.item_count - 1, eid)

	var default_eid: int = -1
	if _preferred_attacker >= 0 and stats_by_entity.has(_preferred_attacker):
		default_eid = _preferred_attacker
	elif ids.size() > 0:
		default_eid = int(ids[0])

	if default_eid >= 0:
		for idx in range(entity_select.item_count):
			if int(entity_select.get_item_metadata(idx)) == default_eid:
				entity_select.select(idx)
				set_selected_entity(default_eid)
				break


func _refresh_views() -> void:
	stats_box.text = _format_stats()
	buffs_box.text = _format_buffs()
	dots_box.text = _format_dots()
	listeners_box.text = _format_listeners()
	stat_mods_box.text = _format_stat_mods()


func _format_stats() -> String:
	if _runtime.is_empty() or _selected_eid < 0:
		return ""
	var stats_by_entity: Dictionary = _runtime.get("stats_by_entity", {})
	var ds = _runtime.get("ds", null)
	var stats = stats_by_entity.get(_selected_eid, null)
	if stats == null:
		return ""

	var names := ["ATK", "DEF", "HP", "SHIELD", "HIT_RATE", "EVADE", "CRIT_RATE", "CRIT_DMG", "DMG_REDUCE"]
	var lines: Array[String] = []
	lines.append("[Stats] entity_id=%s" % [_selected_eid])
	for n in names:
		var sid: int = -1
		if ds != null and ds.has_method("stat_id"):
			sid = int(ds.stat_id(String(n)))
			if sid < 0:
				continue
		else:
			continue
		var base_v := float(stats.core.base_values[sid])
		var final_v := float(stats.get_final(sid))
		lines.append("%s = %s  (base=%s)" % [String(n), final_v, base_v])
	return "\n".join(lines)


func _format_buffs() -> String:
	if _runtime.is_empty() or _selected_eid < 0:
		return ""
	var buffs_by_entity: Dictionary = _runtime.get("buff_by_entity", {})
	var ds = _runtime.get("ds", null)
	var buffs = buffs_by_entity.get(_selected_eid, null)
	if buffs == null:
		return ""

	var lines: Array[String] = []
	lines.append("[Buffs] count=%s" % [int(buffs.inst_ids.size())])
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		var buff_id_str := "?"
		var buff_type := String(inst.buff_type)
		var tags := []
		if ds != null and ds.has_method("buff_id"):
			var bdid: int = int(inst.buff_def_id)
			if bdid >= 0 and bdid < ds.buff_defs.size():
				var def: Dictionary = ds.buff_defs[bdid]
				buff_id_str = String(def.get("id", buff_id_str))
				tags = def.get("tags", [])
		var turns_str := str(int(inst.remaining_turns))
		if ds != null and ds.has_method("buff_id"):
			var bdid: int = int(inst.buff_def_id)
			if bdid >= 0 and bdid < ds.buff_defs.size():
				var def2: Dictionary = ds.buff_defs[bdid]
				var dot_def: Dictionary = def2.get("dot", {})
				if not dot_def.is_empty():
					turns_str = "N/A(DOT)"

		lines.append("- inst=%s %s type=%s src=%s stacks=%s turns=%s active=%s tags=%s" % [
			int(inst.inst_id),
			buff_id_str,
			buff_type,
			int(inst.source_entity_id),
			int(inst.stacks),
			turns_str,
			bool(inst.active),
			str(tags)
		])
	return "\n".join(lines)

func _format_dots() -> String:
	if _runtime.is_empty() or _selected_eid < 0:
		return ""
	var buffs_by_entity: Dictionary = _runtime.get("buff_by_entity", {})
	var ds = _runtime.get("ds", null)
	var buffs = buffs_by_entity.get(_selected_eid, null)
	if buffs == null:
		return ""

	var dots_any: Variant = buffs.dots_by_target.get(_selected_eid, null)
	if dots_any == null:
		return "[Dots] none"
	var dots: Array = dots_any
	if dots.is_empty():
		return "[Dots] none"

	var lines: Array[String] = []
	lines.append("[Dots] count=%s (DotInstance is authoritative for DOT turns/stacks)" % [dots.size()])
	dots.sort_custom(func(a, b): return int(a.dot_inst_id) < int(b.dot_inst_id))
	for x in dots:
		var d = x
		if d == null:
			continue
		var buff_id_str := "?"
		if ds != null and ds.has_method("buff_id"):
			var bdid: int = int(d.buff_def_id)
			if bdid >= 0 and bdid < ds.buff_defs.size():
				var def: Dictionary = ds.buff_defs[bdid]
				buff_id_str = String(def.get("id", buff_id_str))
		lines.append("- %s dot_id=%s src=%s stacks=%s turns=%s tick=%s tags_mask=%s owner_inst=%s" % [
			buff_id_str,
			int(d.dot_inst_id),
			int(d.source_entity_id),
			int(d.stacks),
			int(d.remaining_turns),
			String(d.tick_phase),
			int(d.tags_mask),
			int(d.owner_buff_inst_id),
		])
	return "\n".join(lines)

func _enum_name_from_int(enums_rt: Variant, enum_name: String, code: int) -> String:
	if enums_rt == null:
		return str(code)
	if not (enums_rt is OmniEnumsRuntime):
		return str(code)
	var name := enums_rt.reverse_name(enum_name, code)
	if name != "":
		return name
	return str(code)

func _enum_names_from_mask(enums_rt: Variant, enum_name: String, mask: int) -> Array[String]:
	var out: Array[String] = []
	if mask == 0:
		return out
	if enums_rt == null or not (enums_rt is OmniEnumsRuntime):
		return out
	var table: Dictionary = enums_rt.enum_tables.get(enum_name, {})
	for k in table.keys():
		var code := int(table.get(k, -99999))
		if code >= 0 and ((mask & (1 << code)) != 0):
			out.append(String(k))
	out.sort()
	return out


func _format_listeners() -> String:
	if _runtime.is_empty() or _selected_eid < 0:
		return ""
	var buffs_by_entity: Dictionary = _runtime.get("buff_by_entity", {})
	var ds = _runtime.get("ds", null)
	var buffs = buffs_by_entity.get(_selected_eid, null)
	if buffs == null:
		return "[Listeners] none"

	var out: Array[String] = []
	var last_ids := PackedInt32Array()
	if buffs.has_method("get_triggered_inst_ids_last_emit"):
		last_ids = buffs.get_triggered_inst_ids_last_emit()
	out.append("[LastTriggered] inst_ids=" + str(last_ids))

	var ei = buffs.event_index
	if ei == null:
		out.append("")
		out.append("[Listeners] none")
		return "\n".join(out)

	var enums_rt: Variant = _runtime.get("enums_rt", null)

	var phase_count: int = 16
	phase_count = int(OmniEventIndex.PHASE_COUNT)

	out.append("")
	out.append("[Listeners] entity_id=%s" % [_selected_eid])

	for key in range(ei.listeners.size()):
		var lids: PackedInt32Array = ei.listeners[key]
		if lids.is_empty():
			continue
		var et_i: int = int(key / phase_count)
		var ph_i: int = int(key % phase_count)
		var et_name := _enum_name_from_int(enums_rt, "event_type", et_i)
		var ph_name := _enum_name_from_int(enums_rt, "event_phase", ph_i)
		out.append("")
		out.append("== %s / %s (key=%s) ==" % [et_name, ph_name, key])
		for lid in lids:
			var l = ei.listener_data[int(lid)]
			out.append(_format_one_listener(buffs, ds, enums_rt, l))

	return "\n".join(out)


func _format_one_listener(buffs: Variant, ds: Variant, enums_rt: Variant, l: Variant) -> String:
	if l == null:
		return "- <null listener>"
	var inst_id: int = int(l.inst_id)
	var active: bool = bool(l.active)
	var scope: String = String(l.scope)

	var buff_id_str := "?"
	if ds != null and ds.has_method("buff_id"):
		var inst = buffs.instances_by_id.get(inst_id, null)
		if inst != null:
			var bdid: int = int(inst.buff_def_id)
			if bdid >= 0 and bdid < ds.buff_defs.size():
				buff_id_str = String((ds.buff_defs[bdid] as Dictionary).get("id", buff_id_str))

	var filter_parts: Array[String] = []
	var mask: int = int(l.filter_tag_mask)
	if mask != 0:
		if enums_rt != null and enums_rt.has_method("tags_from_mask"):
			filter_parts.append("tag_any=" + str(enums_rt.tags_from_mask(mask)))
		else:
			filter_parts.append("tag_mask=0x%X" % [mask])
	if bool(l.filter_require_hit):
		filter_parts.append("require_hit=true")
	if bool(l.filter_require_crit):
		filter_parts.append("require_crit=true")
	if int(l.filter_skill_id) >= 0:
		filter_parts.append("skill_id=" + str(int(l.filter_skill_id)))
	var dt_mask: int = int(l.filter_damage_type_mask_any)
	if dt_mask != 0:
		var names := _enum_names_from_mask(enums_rt, "damage_type", dt_mask)
		if names.is_empty():
			filter_parts.append("damage_type_mask=0x%X" % [dt_mask])
		else:
			filter_parts.append("damage_type_any=" + str(names))
	var el_mask: int = int(l.filter_element_mask_any)
	if el_mask != 0:
		var names2 := _enum_names_from_mask(enums_rt, "element", el_mask)
		if names2.is_empty():
			filter_parts.append("element_mask=0x%X" % [el_mask])
		else:
			filter_parts.append("element_any=" + str(names2))
	if bool(l.filter_require_shield_absorbed):
		filter_parts.append("shield_absorbed=true")
	if float(l.filter_min_absorbed_shield) > 0.0:
		filter_parts.append("min_absorbed>=" + str(float(l.filter_min_absorbed_shield)))
	if float(l.filter_min_final_damage) > 0.0:
		filter_parts.append("min_final>=" + str(float(l.filter_min_final_damage)))
	if String(l.filter_stat) != "":
		filter_parts.append("stat_threshold(%s.%s %s %s)" % [
			String(l.filter_stat_scope),
			String(l.filter_stat),
			String(l.filter_stat_op),
			str(float(l.filter_stat_value)),
		])
	var filters_str := "none"
	if not filter_parts.is_empty():
		filters_str = ", ".join(filter_parts)

	var ak := String(l.action_kind)
	var action_str := ak
	match ak:
		"ADD_BASE_DAMAGE":
			action_str = "ADD_BASE_DAMAGE(%s)" % [str(float(l.action_value))]
		"APPLY_BUFF":
			action_str = "APPLY_BUFF(%s, add_stacks=%s)" % [String(l.action_buff_id), int(l.action_add_stacks)]
		"CHANCE_APPLY_BUFF":
			action_str = "CHANCE_APPLY_BUFF(%s, add_stacks=%s, chance=%s)" % [String(l.action_buff_id), int(l.action_add_stacks), str(float(l.action_chance))]
		"SET_STAT_FINAL":
			action_str = "SET_STAT_FINAL(%s=%s)" % [String(l.action_stat), str(float(l.action_value))]
		"SET_SHIELD_TO_FINAL_DAMAGE":
			action_str = "SET_SHIELD_TO_FINAL_DAMAGE(SHIELD=ctx.final_damage)"
		"ADD_SHIELD":
			action_str = "ADD_SHIELD(+%s)" % [str(float(l.action_value))]
		"HEAL":
			action_str = "HEAL(+%s)" % [str(float(l.action_value))]
		"LIFESTEAL":
			action_str = "LIFESTEAL(ratio=%s)" % [str(float(l.action_ratio))]
		"REFLECT_DAMAGE":
			action_str = "REFLECT_DAMAGE(ratio=%s)" % [str(float(l.action_ratio))]
		"DISPEL":
			action_str = "DISPEL(mode=%s, tag=%s, source=%s, buff_type=%s, include_implicit=%s)" % [
				String(l.action_dispel_mode),
				String(l.action_dispel_tag),
				String(l.action_dispel_source_scope),
				String(l.action_dispel_buff_type),
				str(bool(l.action_include_implicit)),
			]
		"CANCEL_COMMAND":
			action_str = "CANCEL_COMMAND(ctx.cancel=true)"
		"DOT_MUL_STACKS", "DOT_ADD_STACKS", "DOT_SET_STACKS":
			action_str = "%s(dot=%s, value=%s, tag_mask_any=%s)" % [
				ak,
				String(l.action_dot_buff_id),
				str(float(l.action_value)),
				str(int(l.action_dot_tag_mask_any)),
			]
		"DOT_CLEAR":
			action_str = "DOT_CLEAR(dot=%s, tag_mask_any=%s)" % [String(l.action_dot_buff_id), str(int(l.action_dot_tag_mask_any))]
		_:
			pass

	return "- inst=%s buff=%s active=%s scope=%s filters=%s action=%s" % [
		inst_id,
		buff_id_str,
		active,
		scope,
		filters_str,
		action_str,
	]


func _buff_id_from_inst_id(buffs: Variant, ds: Variant, inst_id: int) -> String:
	if buffs == null or ds == null or (not ds.has_method("buff_id")):
		return "?"
	var inst = buffs.instances_by_id.get(inst_id, null)
	if inst == null:
		return "?"
	var bdid: int = int(inst.buff_def_id)
	if bdid < 0 or bdid >= ds.buff_defs.size():
		return "?"
	return String((ds.buff_defs[bdid] as Dictionary).get("id", "?"))


func _format_stat_mods() -> String:
	if _runtime.is_empty() or _selected_eid < 0:
		return ""
	var stats_by_entity: Dictionary = _runtime.get("stats_by_entity", {})
	var buffs_by_entity: Dictionary = _runtime.get("buff_by_entity", {})
	var ds = _runtime.get("ds", null)
	var stats = stats_by_entity.get(_selected_eid, null)
	var buffs = buffs_by_entity.get(_selected_eid, null)
	if stats == null or ds == null:
		return "[StatMods] none"
	if not (ds.has_method("stat_id") and stats.has_method("get_final")):
		return "[StatMods] none"

	var core = stats.core
	if core == null:
		return "[StatMods] none"

	var names := ["ATK", "DEF", "HP", "SHIELD", "HIT_RATE", "EVADE", "CRIT_RATE", "CRIT_DMG", "DMG_REDUCE"]
	var out: Array[String] = []
	out.append("[StatMods] entity_id=%s" % [_selected_eid])

	for n in names:
		var sid: int = int(ds.stat_id(String(n)))
		if sid < 0:
			continue
		var base_v := float(core.base_values[sid])
		var final_v := float(stats.get_final(sid))
		var dirty_v := int(core.dirty[sid])
		out.append("")
		out.append("== %s (id=%s) ==" % [String(n), sid])
		out.append("base=%s final=%s dirty=%s" % [base_v, final_v, dirty_v])

		var mods: Array = core.modifiers_by_stat[sid]
		if mods.is_empty():
			out.append("- (no modifiers)")
			continue

		mods.sort_custom(func(a, b):
			if a == null or b == null:
				return false
			return int(a.source_inst_id) < int(b.source_inst_id)
		)

		for m in mods:
			if m == null or typeof(m) != TYPE_OBJECT:
				continue
			var op := String(m.op)
			var ph := String(m.phase)
			var val := float(m.value)
			var layer := int(m.layer)
			var pri := int(m.priority)
			var src_inst := int(m.source_inst_id)
			var buff_id_str := _buff_id_from_inst_id(buffs, ds, src_inst)
			out.append("- %s/%s %s layer=%s pri=%s inst=%s buff=%s" % [
				op, ph, val, layer, pri, src_inst, buff_id_str
			])
	return "\n".join(out)


func _join_sections(sections: Array[String]) -> String:
	var s := "\n\n".join(sections).strip_edges()
	if s.length() > DUMP_MAX_CHARS:
		return s.substr(0, DUMP_MAX_CHARS) + "\n\n...(truncated)"
	return s

func _make_dump() -> String:
	var parts: Array[String] = []
	var sections: Array[String] = []
	sections.append("[OmniBuffDebugHUD]")
	sections.append(_format_stats())
	sections.append(_format_stat_mods())
	sections.append(_format_buffs())
	sections.append(_format_dots())
	sections.append(_format_listeners())
	return _join_sections(sections)

func _copy_dump() -> void:
	var dump := _make_dump()
	DisplayServer.clipboard_set(dump)
	title = "Debug HUD（已复制 %s 字符）" % [dump.length()]
	var suffix := ""
	if dump.contains("...(truncated)"):
		suffix = "，已截断"
	title = "Debug HUD（已复制 %s 字符%s）" % [dump.length(), suffix]
