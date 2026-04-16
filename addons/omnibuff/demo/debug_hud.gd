extends Window

## OmniBuff Debug HUD（Demo-only）
##
## - 仅用于 demo 场景（不接入主游戏）
## - HUD 不维护全局实体注册表；只接受 demo 传入 runtime：
##   runtime = { "stats_by_entity": {eid:StatsComponent}, "buff_by_entity": {eid:BuffCore} }

@onready var entity_select: OptionButton = %EntitySelect
@onready var stats_box: RichTextLabel = %StatsBox
@onready var buffs_box: RichTextLabel = %BuffsBox
@onready var dots_box: RichTextLabel = %DotsBox
@onready var btn_copy_dump: Button = %BtnCopyDump
@onready var btn_close: Button = %BtnClose

var _runtime: Dictionary = {}
var _selected_eid: int = -1
var _preferred_attacker: int = -1
var _preferred_defender: int = -1


func _ready() -> void:
	btn_copy_dump.pressed.connect(_copy_dump)
	btn_close.pressed.connect(func(): hide())
	entity_select.item_selected.connect(func(_idx: int):
		var eid: int = int(entity_select.get_item_metadata(entity_select.selected))
		set_selected_entity(eid)
	)


func clear() -> void:
	_runtime = {}
	_selected_eid = -1
	_preferred_attacker = -1
	_preferred_defender = -1
	entity_select.clear()
	stats_box.text = ""
	buffs_box.text = ""
	dots_box.text = ""


func set_preferred_entities(attacker_id: int, defender_id: int) -> void:
	_preferred_attacker = attacker_id
	_preferred_defender = defender_id


func set_runtime(runtime: Dictionary) -> void:
	_runtime = runtime
	_refresh_entity_list()


func set_selected_entity(entity_id: int) -> void:
	_selected_eid = entity_id
	_refresh_views()


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

	# 默认选中：preferred_attacker > 最小 id
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


func _format_stats() -> String:
	if _runtime.is_empty() or _selected_eid < 0:
		return ""
	var stats_by_entity: Dictionary = _runtime.get("stats_by_entity", {})
	var ds = _runtime.get("ds", null) # optional
	var stats = stats_by_entity.get(_selected_eid, null)
	if stats == null:
		return ""

	# 仅展示常用 stat；若 ds 提供则用 stat_id 判断是否存在
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
			# 无 ds 时退化：直接跳过
			continue
		lines.append("%s = %s" % [String(n), float(stats.get_final(sid))])
	return "\n".join(lines)


func _format_buffs() -> String:
	if _runtime.is_empty() or _selected_eid < 0:
		return ""
	var buffs_by_entity: Dictionary = _runtime.get("buff_by_entity", {})
	var ds = _runtime.get("ds", null) # optional
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
		# ds 为 OmniCompiledDataset（RefCounted）；不能用 Dictionary.has。
		# 只要提供 ds（且包含 buff_defs 数组），就反查 buff_id/tags 以便显示。
		if ds != null and ds.has_method("buff_id"):
			var bdid: int = int(inst.buff_def_id)
			if bdid >= 0 and bdid < ds.buff_defs.size():
				var def: Dictionary = ds.buff_defs[bdid]
				buff_id_str = String(def.get("id", buff_id_str))
				tags = def.get("tags", [])
		# 注意：DOT 的 remaining_turns/stacks 以 DotInstance 为准；这里显示的是 BuffInst.remaining_turns（对 DOT 不权威）
		var turns_str := str(int(inst.remaining_turns))
		if ds != null and ds.has_method("buff_id"):
			var bdid: int = int(inst.buff_def_id)
			if bdid >= 0 and bdid < ds.buff_defs.size():
				var def2: Dictionary = ds.buff_defs[bdid]
				var dot_def: Dictionary = def2.get("dot", {})
				if not dot_def.is_empty():
					turns_str = "N/A(DOT)"

		lines.append("- %s type=%s src=%s stacks=%s turns=%s active=%s tags=%s" % [
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
	var ds = _runtime.get("ds", null) # optional
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
	# 稳定输出：dot_inst_id 升序
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


func _make_dump() -> String:
	var parts: Array[String] = []
	parts.append("[OmniBuffDebugHUD]")
	parts.append(_format_stats())
	parts.append("")
	parts.append(_format_buffs())
	parts.append("")
	parts.append(_format_dots())
	return "\n".join(parts).strip_edges()


func _copy_dump() -> void:
	var dump := _make_dump()
	DisplayServer.clipboard_set(dump)
	title = "Debug HUD（已复制 %s 字符）" % [dump.length()]
