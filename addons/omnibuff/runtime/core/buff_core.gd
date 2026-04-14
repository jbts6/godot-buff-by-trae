class_name OmniBuffCore
extends RefCounted

## Buff核心（最小可用版）
##
## 设计原则（本项目硬约束）：
## - **禁止**在一次伤害结算里遍历“攻击者全部Buff + 防守者全部Buff”
## - 属性型影响：Buff变动时，把 modifier 注入 StatsCore 的 per-stat 聚合列表，并标脏对应 stat
## - 事件型影响：Buff变动时，把 trigger 注册到 EventIndex；事件触发时只遍历 listeners[key] 子集
##
## 当前实现范围（为了先跑通闭环）：
## - effects 仅支持：kind=modifier 且 op=ADD 且 phase=FLAT（平铺加成）
## - triggers 仅支持：
##   - filters.tag_mask_any（可选）
##   - action.kind="ADD_BASE_DAMAGE"（在 BEFORE_DEAL 等阶段修改 ctx.base_damage）
##   - action.kind="APPLY_BUFF"（在事件阶段给某个目标施加 buff）
##   - action.kind="CHANCE_APPLY_BUFF"（带概率的 APPLY_BUFF）
## - DOT 仅支持：
##   - buff_defs.json 中存在 `dot` 字段即视为DOT型buff
##   - DOT实例按来源独立（每次施加创建一个 DotInstance）
##   - tick 时动态读取来源 StatCache（禁止遍历来源buff）

class OmniModifierRef:
	## 目标 stat（编译后 int 索引）
	var stat_id: int
	## modifier op（如 "ADD"/"MUL"）
	var op: String = ""
	## modifier phase（如 "FLAT"/"PERCENT"）
	var phase: String = ""
	## modifier 原始值（与配置 value 一致；例如 20.0 / 0.05）
	var value: float = 0.0
	## 兼容字段：平铺加成值（旧实现只读取 add_value）
	## - 当 op=ADD 且 phase=FLAT 时，add_value=value
	## - 其他组合下为 0（避免旧逻辑误用）
	var add_value: float = 0.0
	## 来源 BuffInstance 的 inst_id（用于追帧/撤销/调试）
	var source_inst_id: int

class BuffInst:
	## 实例唯一ID（运行时递增）
	var inst_id: int
	## buff_def_id（编译后 int 索引）
	var buff_def_id: int
	## buff_type（配置层字符串：EXPLICIT/IMPLICIT/PASSIVE/AURA），用于驱散语义
	var buff_type: String
	## tag_mask（bitmask），用于按Tag驱散与 filters
	var tag_mask: int
	## 是否不可驱散（true表示任何驱散操作都应跳过）
	var undispellable: bool = false
	## 来源实体（用于归因/驱散；当前版本仅存 entity_id）
	var source_entity_id: int
	## 层数（当前版本未实现叠加策略，仅占位）
	var stacks: int
	## 剩余回合数（当前版本未实现tick/到期，仅占位）
	var remaining_turns: int
	## 该实例注入到 StatsCore 的 modifier 引用（用于将来撤销/重建聚合视图）
	var modifier_refs: Array[OmniModifierRef] = []

class DotInstance:
	extends RefCounted
	## DOT实例ID（运行时递增，用于稳定排序/追帧）
	var dot_inst_id: int
	## 该DOT归属的 buff inst_id（便于追溯来源buff实例）
	var owner_buff_inst_id: int
	## 目标实体ID（DOT挂在谁身上）
	var target_entity_id: int
	## 来源实体ID（谁施加的DOT；每跳读取其StatCache）
	var source_entity_id: int
	## 剩余回合数（每次tick扣减，到0移除）
	var remaining_turns: int
	## tick阶段：字符串 "TURN_START"/"TURN_END"（本demo仅用TURN_END）
	var tick_phase: String
	## DOT基础系数：damage = source_stat * base_ratio
	var base_ratio: float
	## DOT读取的来源属性（字符串，如 "ATK"）
	var read_source_stat: String
	## 事件tag掩码（用于 filters 与追帧；通常包含 DOT + 元素等）
	var tags_mask: int

## 编译数据集（只读）
var ds: OmniCompiledDataset

## enums运行时映射（字符串枚举/Tag -> int/bitmask）
var enums_rt: OmniEnumsRuntime

## 事件索引：key(event_type+phase) -> listeners 子集
var event_index: OmniEventIndex

## 分配 inst_id 的自增计数器
var next_inst_id := 1

## 分配 dot_inst_id 的自增计数器（用于DOT按来源独立实例）
var next_dot_inst_id := 1

## 最近一次 emit_event 命中的 buff inst_id 列表（用于追帧/调试）
var _triggered_inst_ids_last_emit: PackedInt32Array = PackedInt32Array()

## DOT池：target_entity_id -> Array[DotInstance]
## 注意：本最小实现将DOT存放在“目标实体的 BuffCore”中（最贴近逻辑归属）。
var dots_by_target: Dictionary = {}

## Buff实例表（仅存放“挂在本 BuffCore.owner_entity_id 上的实例”）
## - instances_by_id：inst_id -> BuffInst
## - inst_ids：稳定遍历用（inst_id 升序；用于驱散/到期）
var instances_by_id: Dictionary = {}
var inst_ids: Array[int] = []

## inst_id -> listener_id[]（用于驱散/到期时注销事件监听）
var listener_ids_by_inst: Dictionary = {}

## 目标对“驱散”操作的免疫标签（bitmask）。
## - 若驱散请求的 tag_mask 与该 mask 有交集，则此次驱散直接失败（返回0）。
## - 这是“被驱散免疫”（例如某单位天生不可被驱散某类效果）的最小实现。
var target_dispel_immunity_mask: int = 0

## 该 BuffCore 的归属实体（目标实体）；
## 当前实现通过首次 apply_buff 的 stats.entity_id 自动绑定，用于tick阶段定位。
var owner_entity_id: int = -1

func _init(dataset: OmniCompiledDataset, enums_runtime: OmniEnumsRuntime = null) -> void:
	ds = dataset
	enums_rt = enums_runtime
	if enums_rt != null:
		var event_type_count := max(1, enums_rt.enum_count("event_type"))
		event_index = OmniEventIndex.new(event_type_count * OmniEventIndex.PHASE_COUNT)
	else:
		event_index = OmniEventIndex.new(1)

func apply_buff(stats: OmniStatsComponent, buff_id_str: String, source_entity_id: int) -> int:
	## 施加一个 buff（最小可用版）
	## - stats：目标实体的 StatsComponent
	## - buff_id_str：配置层字符串ID（内部映射到 buff_def_id）
	## - source_entity_id：来源实体ID（归因/驱散占位）
	## 返回：inst_id（用于追帧/未来撤销）
	var bdid := ds.buff_id(buff_id_str)
	if bdid < 0:
		push_error("[Buff] unknown buff_id=" + buff_id_str)
		return -1

	var inst := BuffInst.new()
	inst.inst_id = next_inst_id
	next_inst_id += 1
	inst.buff_def_id = bdid
	inst.buff_type = String(ds.buff_defs[bdid].get("buff_type", ""))
	inst.source_entity_id = source_entity_id
	inst.stacks = 1
	inst.remaining_turns = int(ds.buff_defs[bdid].get("duration", {}).get("turns", -1))
	# tags -> bitmask（用于驱散与 filters）
	if enums_rt != null:
		inst.tag_mask = enums_rt.tag_mask(ds.buff_defs[bdid].get("tags", []))
	else:
		inst.tag_mask = 0

	# dispel语义（最小实现）：
	# - 若配置存在 dispel.dispellable=false，则视为不可驱散
	var dispel_def: Dictionary = ds.buff_defs[bdid].get("dispel", {})
	if not dispel_def.is_empty():
		inst.undispellable = (bool(dispel_def.get("dispellable", true)) == false)

	# 绑定 BuffCore 的归属实体（用于 tick）
	if owner_entity_id < 0:
		owner_entity_id = stats.entity_id
	elif owner_entity_id != stats.entity_id:
		push_warning("[Buff] owner_entity_id mismatch. expected=%s got=%s" % [owner_entity_id, stats.entity_id])

	# 保存实例（用于驱散/到期等管理；稳定顺序按 inst_id 升序）
	instances_by_id[inst.inst_id] = inst
	inst_ids.append(inst.inst_id)
	inst_ids.sort()

	# === effects -> StatsCore（属性型：变动时维护聚合视图）===
	var effects: Array = ds.buff_defs[bdid].get("effects", [])
	for e in effects:
		if String(e.get("kind", "")) != "modifier":
			continue
		var op := String(e.get("op", ""))
		var phase := String(e.get("phase", ""))
		# 当前运行时支持：
		# - ADD/FLAT（平铺加成）
		# - MUL/PERCENT（百分比加成：最终值按 (base+flat)*(1+pct) 计算）
		var supported := (op == "ADD" and phase == "FLAT") or (op == "MUL" and phase == "PERCENT")
		if not supported:
			continue

		var stat_id := ds.stat_id(String(e.get("stat", "")))
		if stat_id < 0:
			push_error("[Buff] unknown stat in effect: " + str(e))
			continue
		var v := float(e.get("value", 0.0))

		var mr := OmniModifierRef.new()
		mr.stat_id = stat_id
		mr.op = op
		mr.phase = phase
		mr.value = v
		if op == "ADD" and phase == "FLAT":
			mr.add_value = v
		else:
			mr.add_value = 0.0
		mr.source_inst_id = inst.inst_id

		inst.modifier_refs.append(mr)
		stats.core.modifiers_by_stat[stat_id].append(mr)
		stats.core.mark_dirty(stat_id)

	# === triggers -> EventIndex（事件型：变动时注册监听）===
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
			# APPLY_BUFF / CHANCE_APPLY_BUFF 的 payload
			if action.has("buff_id"):
				l.action_buff_id = String(action.get("buff_id", ""))
			elif action.has("apply_buff_id"):
				l.action_buff_id = String(action.get("apply_buff_id", ""))
			l.action_chance = float(action.get("chance", 1.0))
			l.scope = String(t.get("scope", "SELF"))
			var lid := event_index.register_listener(key, l)
			if not listener_ids_by_inst.has(inst.inst_id):
				listener_ids_by_inst[inst.inst_id] = PackedInt32Array()
			(listener_ids_by_inst[inst.inst_id] as PackedInt32Array).append(lid)

	# === DOT实例（按来源独立）===
	# 规则：只要 buff_defs[bdid] 存在 dot 字段，则视为DOT型buff；每次施加创建新的 DotInstance
	var dot_def: Dictionary = ds.buff_defs[bdid].get("dot", {})
	if not dot_def.is_empty():
		var d := DotInstance.new()
		d.dot_inst_id = next_dot_inst_id
		next_dot_inst_id += 1
		d.owner_buff_inst_id = inst.inst_id
		d.target_entity_id = stats.entity_id
		d.source_entity_id = source_entity_id
		d.remaining_turns = int(ds.buff_defs[bdid].get("duration", {}).get("turns", 0))
		d.tick_phase = String(dot_def.get("tick_phase", "TURN_END"))
		d.base_ratio = float(dot_def.get("base_ratio", 0.0))
		d.read_source_stat = String(dot_def.get("read_source_stat", "ATK"))
		# DOT tags：默认使用 buff 自身 tags（例如 DOT/FIRE），映射为 bitmask
		if enums_rt != null:
			d.tags_mask = enums_rt.tag_mask(ds.buff_defs[bdid].get("tags", []))
		else:
			d.tags_mask = 0

		if not dots_by_target.has(stats.entity_id):
			dots_by_target[stats.entity_id] = []
		(dots_by_target[stats.entity_id] as Array).append(d)

	return inst.inst_id

func set_target_dispel_immunity_tags(tags: Array) -> void:
	## 设置“驱散免疫”标签集合（bitmask）
	## 语义：若驱散请求的 tag_mask 与该 mask 有交集，则本次驱散直接不生效（返回0）。
	if enums_rt == null:
		target_dispel_immunity_mask = 0
		return
	target_dispel_immunity_mask = enums_rt.tag_mask(tags)

func remove_by_instance(stats: OmniStatsComponent, inst_id: int, force: bool = false) -> bool:
	## 移除一个 buff 实例（用于驱散/到期/脚本主动移除）
	## - force=false：遵守不可驱散（undispellable）规则
	## - force=true：强制移除（系统清理/调试）
	var inst: BuffInst = instances_by_id.get(inst_id, null)
	if inst == null:
		return false
	if (not force) and inst.undispellable:
		return false

	# 1) 从 StatsCore 聚合视图中撤销 modifier
	for mr in inst.modifier_refs:
		var stat_id := int(mr.stat_id)
		var list: Array = stats.core.modifiers_by_stat[stat_id]
		var kept: Array = []
		for x in list:
			if int(x.source_inst_id) != inst_id:
				kept.append(x)
		stats.core.modifiers_by_stat[stat_id] = kept
		stats.core.mark_dirty(stat_id)

	# 2) 注销事件监听（从 listeners[key] 列表中移除 + 标记 inactive）
	_unregister_listeners_for_inst(inst_id)

	# 2.5) 移除该 buff 实例对应的 DOT 实例（否则会出现“驱散了 debuff 但 DOT 仍在跳”的问题）
	# 说明：
	# - DOT 实例在 apply_buff 时创建，并记录 owner_buff_inst_id
	# - DOT 存放在目标实体的 BuffCore.dots_by_target 中
	# - 驱散/到期/主动移除都应清理对应 DOT
	if owner_entity_id >= 0 and dots_by_target.has(owner_entity_id):
		var dots: Array = dots_by_target[owner_entity_id]
		var kept_dots: Array = []
		for d in dots:
			if int(d.owner_buff_inst_id) != inst_id:
				kept_dots.append(d)
		dots_by_target[owner_entity_id] = kept_dots

	# 3) 从实例表移除
	instances_by_id.erase(inst_id)
	var new_ids: Array[int] = []
	for id in inst_ids:
		if id != inst_id:
			new_ids.append(id)
	inst_ids = new_ids
	listener_ids_by_inst.erase(inst_id)
	return true

func dispel_by_tag(stats: OmniStatsComponent, tag_id: String, include_implicit: bool = false) -> int:
	## 按 Tag 驱散（M7）
	## - include_implicit=false：默认不驱散 IMPLICIT/PASSIVE（符合“装备/加点/套装不应被常规驱散”）
	if enums_rt == null:
		return 0
	var tag_mask := enums_rt.tag_mask([tag_id])
	if tag_mask == 0:
		return 0
	if (target_dispel_immunity_mask & tag_mask) != 0:
		return 0

	var removed := 0
	# 注意：remove_by_instance 会修改 inst_ids，因此这里用副本遍历，避免跳过元素
	for id in inst_ids.duplicate():
		var inst: BuffInst = instances_by_id.get(id, null)
		if inst == null:
			continue
		if (not include_implicit) and (inst.buff_type == "IMPLICIT" or inst.buff_type == "PASSIVE"):
			continue
		if inst.undispellable:
			continue
		if (inst.tag_mask & tag_mask) != 0:
			if remove_by_instance(stats, inst.inst_id, true):
				removed += 1
	return removed

func dispel_by_source(stats: OmniStatsComponent, source_entity_id: int, include_implicit: bool = false) -> int:
	## 按来源实体驱散（M7）
	var removed := 0
	for id in inst_ids.duplicate():
		var inst: BuffInst = instances_by_id.get(id, null)
		if inst == null:
			continue
		if (not include_implicit) and (inst.buff_type == "IMPLICIT" or inst.buff_type == "PASSIVE"):
			continue
		if inst.undispellable:
			continue
		if inst.source_entity_id == source_entity_id:
			if remove_by_instance(stats, inst.inst_id, true):
				removed += 1
	return removed

func dispel_by_type(stats: OmniStatsComponent, buff_type: String) -> int:
	## 按 Buff 类型驱散（M7）
	## buff_type 示例："EXPLICIT"（常用：只驱散战斗中获得的显式buff/debuff）
	var removed := 0
	for id in inst_ids.duplicate():
		var inst: BuffInst = instances_by_id.get(id, null)
		if inst == null:
			continue
		if inst.undispellable:
			continue
		if inst.buff_type == buff_type:
			if remove_by_instance(stats, inst.inst_id, true):
				removed += 1
	return removed

func _unregister_listeners_for_inst(inst_id: int) -> void:
	# 内部：注销一个实例注册过的 listener
	if not listener_ids_by_inst.has(inst_id):
		return
	var lids: PackedInt32Array = listener_ids_by_inst[inst_id]
	for lid in lids:
		var l = event_index.listener_data[lid]
		if l != null:
			l.active = false
			var key: int = int(l.key)
			# 从 listeners[key] 中移除该 lid（最小实现：重建数组）
			var arr := event_index.listeners[key]
			var out := PackedInt32Array()
			for x in arr:
				if x != lid:
					out.append(x)
			event_index.listeners[key] = out

func debug_dump_instances() -> String:
	## 调试：打印当前目标身上的 BuffInstance 列表（用于验证驱散/到期是否正确）
	## 输出字段：
	## - inst_id
	## - buff_def_id -> buff_id（从 compiled defs 反查）
	## - buff_type / source_entity_id / undispellable / tag_mask
	var lines: Array[String] = []
	lines.append("[BuffDump] owner=%s count=%s" % [owner_entity_id, inst_ids.size()])
	for id in inst_ids:
		var inst: BuffInst = instances_by_id.get(id, null)
		if inst == null:
			continue
		var def: Dictionary = ds.buff_defs[inst.buff_def_id]
		var buff_id_str := String(def.get("id", ""))
		lines.append("  inst_id=%s buff_id=%s type=%s src=%s undisp=%s tag_mask=%s" % [
			inst.inst_id,
			buff_id_str,
			inst.buff_type,
			inst.source_entity_id,
			inst.undispellable,
			inst.tag_mask
		])
	return "\n".join(lines)

func debug_dump_stat_modifiers(stats: OmniStatsComponent, stat_id: int) -> String:
	## 调试：打印某个 stat 的 modifier 列表（聚合视图），确认撤销是否正确。
	## 输出字段：
	## - op/phase/value
	## - source_inst_id
	var lines: Array[String] = []
	lines.append("[StatMods] entity=%s stat_id=%s count=%s" % [stats.entity_id, stat_id, (stats.core.modifiers_by_stat[stat_id] as Array).size()])
	for m in stats.core.modifiers_by_stat[stat_id]:
		if m == null or typeof(m) != TYPE_OBJECT:
			continue
		lines.append("  %s/%s %s (from inst_id=%s)" % [String(m.op), String(m.phase), float(m.value), int(m.source_inst_id)])
	return "\n".join(lines)

func _tick_dots(turn_index: int, tick_phase: String, stats_by_entity: Dictionary, buff_by_entity: Dictionary, pipeline: OmniDamagePipeline, dataset: OmniCompiledDataset, replay: RefCounted) -> void:
	# 内部：DOT结算（支持 TURN_START / TURN_END）
	# 注意：这里不能遍历“所有buff实例”，只能遍历已建索引的数据结构（DOT池/事件索引等）
	if owner_entity_id < 0:
		return
	if pipeline == null or dataset == null:
		return
	if not dots_by_target.has(owner_entity_id):
		return

	var dots: Array = dots_by_target[owner_entity_id]
	# 稳定顺序：dot_inst_id 升序
	dots.sort_custom(func(a, b): return a.dot_inst_id < b.dot_inst_id)

	var target_stats: OmniStatsComponent = stats_by_entity.get(owner_entity_id, null)
	if target_stats == null:
		return
	var target_buff: OmniBuffCore = buff_by_entity.get(owner_entity_id, null)
	if target_buff == null:
		return

	var kept: Array = []
	for d in dots:
		# 仅处理匹配 tick_phase 的DOT；其它DOT保持不动
		if d.tick_phase != tick_phase:
			kept.append(d)
			continue
		if d.remaining_turns <= 0:
			continue

		var source_stats: OmniStatsComponent = stats_by_entity.get(d.source_entity_id, null)
		var source_buff: OmniBuffCore = buff_by_entity.get(d.source_entity_id, null)
		if source_stats == null or source_buff == null:
			# 来源不存在：直接丢弃该DOT（避免僵尸引用）
			continue

		# 动态读取施法者当前属性：必须走 StatCache（禁止遍历来源Buff）
		# 注意：dots 是未类型化的 Array，for-in 得到的 d 在编译期会被视作 Variant，
		# 因此这里显式标注类型，避免 Godot 4 的类型推断失败。
		var read_stat_id: int = dataset.stat_id(d.read_source_stat)
		var src_v: float = source_stats.get_final(read_stat_id)

		# base_damage 必须是 float：显式转换 d.base_ratio（Variant->float），避免推断错误
		var base_damage: float = src_v * float(d.base_ratio)
		var ctx := pipeline.deal_damage_with_tags(source_stats, target_stats, source_buff, target_buff, dataset, base_damage, d.tags_mask, replay, turn_index)

		# 追帧：记录 DOT 每跳的“来源属性快照”与最终伤害（用于证明走StatCache）
		if replay != null and replay.has_method("trace_dot_tick"):
			replay.trace_dot_tick(
				turn_index,
				int(d.dot_inst_id),
				int(d.owner_buff_inst_id),
				int(d.source_entity_id),
				int(d.target_entity_id),
				String(d.read_source_stat),
				float(src_v),
				float(d.base_ratio),
				float(base_damage),
				float(ctx.final_damage),
				int(d.tags_mask)
			)

		d.remaining_turns -= 1
		if d.remaining_turns > 0:
			kept.append(d)

	# 回写（移除到期DOT）
	dots_by_target[owner_entity_id] = kept

func on_turn_start(turn_index: int, stats_by_entity: Dictionary = {}, buff_by_entity: Dictionary = {}, pipeline: OmniDamagePipeline = null, dataset: OmniCompiledDataset = null, replay: RefCounted = null) -> void:
	# TurnStart tick（DOT结算）
	# 兼容：允许旧调用只传 turn_index，此时不会触发DOT结算
	if pipeline == null or dataset == null:
		return
	_tick_dots(turn_index, "TURN_START", stats_by_entity, buff_by_entity, pipeline, dataset, replay)

func on_turn_end(turn_index: int, stats_by_entity: Dictionary, buff_by_entity: Dictionary, pipeline: OmniDamagePipeline, dataset: OmniCompiledDataset, replay: RefCounted = null) -> void:
	# TurnEnd tick（DOT结算）
	_tick_dots(turn_index, "TURN_END", stats_by_entity, buff_by_entity, pipeline, dataset, replay)

func emit_event(event_type: String, phase: String, ctx: RefCounted) -> void:
	## 触发事件（最小可用版）
	## 重要：此函数只遍历 listeners[key]（监听该事件的子集），满足“禁止遍历全部Buff”的性能约束。
	##
	## ctx 约定字段（当前版本）：
	## - ctx.tags_mask : int（用于 filters.tag_mask_any）
	## - ctx.base_damage : float（用于 action.ADD_BASE_DAMAGE）
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
		if l == null or l.active == false:
			continue
		if l.filter_tag_mask != 0:
			if (int(ctx.tags_mask) & l.filter_tag_mask) == 0:
				continue
		_triggered_inst_ids_last_emit.append(l.inst_id)
		match l.action_kind:
			"ADD_BASE_DAMAGE":
				ctx.base_damage += l.action_value
			"APPLY_BUFF":
				_apply_buff_from_event(l, ctx, false)
			"CHANCE_APPLY_BUFF":
				_apply_buff_from_event(l, ctx, true)
			_:
				pass

func get_triggered_inst_ids_last_emit() -> PackedInt32Array:
	## 返回最近一次 emit_event 命中的 buff inst_id 列表（按触发顺序）
	return _triggered_inst_ids_last_emit

func _apply_buff_from_event(l: OmniEventIndex.Listener, ctx: RefCounted, use_chance: bool) -> void:
	## 事件动作：对某个目标 apply buff（最小可用版）
	##
	## 运行时依赖：
	## - 为避免跨模块强耦合，事件动作通过 ctx.meta["runtime"] 获取运行时环境字典：
	##   runtime = { "stats_by_entity": Dictionary, "buff_by_entity": Dictionary }
	##
	## 说明：
	## - 真实项目可以把 runtime 抽象为专门的 BattleRuntime 对象，这里用 Dictionary 先跑通闭环。
	if l.action_buff_id == "":
		return

	if use_chance:
		var ch := clamp(l.action_chance, 0.0, 1.0)
		if ch <= 0.0:
			return
		if ch < 1.0:
			var seed := _event_seed(ctx, l.inst_id)
			if _roll01(seed) >= ch:
				return

	# 从 ctx meta 中取 runtime
	if not ctx.has_meta("runtime"):
		return
	var rt: Variant = ctx.get_meta("runtime")
	if typeof(rt) != TYPE_DICTIONARY:
		return
	var runtime: Dictionary = rt

	var stats_by_entity: Dictionary = runtime.get("stats_by_entity", {})
	var buff_by_entity: Dictionary = runtime.get("buff_by_entity", {})

	# 解析目标实体ID
	var target_eid := _resolve_scope_entity_id(l.scope, ctx)
	if target_eid < 0:
		return

	var target_stats: OmniStatsComponent = stats_by_entity.get(target_eid, null)
	var target_buff: OmniBuffCore = buff_by_entity.get(target_eid, null)
	if target_stats == null or target_buff == null:
		return

	# 约定：事件施加的来源实体为 ctx.attacker_id（最贴近“施法者/攻击者”）
	var source_eid := int(ctx.attacker_id)
	target_buff.apply_buff(target_stats, l.action_buff_id, source_eid)

func _resolve_scope_entity_id(scope: String, ctx: RefCounted) -> int:
	## 将 scope 映射为实体ID（最小约定）
	## - SELF：本 BuffCore owner_entity（事件接收者）
	## - SOURCE/ATTACKER：ctx.attacker_id
	## - TARGET/DEFENDER：ctx.defender_id
	var s := scope.to_upper()
	if s == "" or s == "SELF":
		return owner_entity_id
	if s == "SOURCE" or s == "ATTACKER":
		return int(ctx.attacker_id)
	if s == "TARGET" or s == "DEFENDER":
		return int(ctx.defender_id)
	return -1

func _event_seed(ctx: RefCounted, inst_id: int) -> int:
	## 生成一个稳定 seed（用于 CHANCE_APPLY_BUFF 的伪随机）
	## 注意：仅要求“同版本同设备可复盘”，因此这里用简单 hash 组合即可。
	var turn_index := 0
	if ctx.has_meta("turn_index"):
		turn_index = int(ctx.get_meta("turn_index"))
	var a := int(ctx.attacker_id)
	var d := int(ctx.defender_id)
	return int(turn_index * 73856093) ^ int(a * 19349663) ^ int(d * 83492791) ^ int(inst_id * 2654435761)

func _roll01(seed: int) -> float:
	## 简单 xorshift32，返回 [0,1) 浮点（用于概率判定）
	var x := seed & 0xffffffff
	x ^= (x << 13) & 0xffffffff
	x ^= (x >> 17) & 0xffffffff
	x ^= (x << 5) & 0xffffffff
	# 取低24位映射到 [0,1)
	var m := x & 0x00ffffff
	return float(m) / float(0x01000000)
