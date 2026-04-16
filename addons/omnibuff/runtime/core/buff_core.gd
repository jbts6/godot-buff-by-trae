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
	## percent layers：当 op=MUL 且 phase=PERCENT 时生效；用于 (base+flat)*Π(1+pct_layer)
	## - 默认 0（兼容旧数据）
	## - 值越大越靠后乘（运行时按 layer 升序执行）
	var layer: int = 0
	## modifier priority（用于 OVERRIDE 等冲突裁决；数值越大越靠后/越优先）
	var priority: int = 0
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
	## ownership_key（用于 REPLACE/ADD_STACK 的查找/替换/叠层；MULTI_INSTANCE 为 -1）
	var ownership_key: int = -1
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
	## A4：while-condition 路线A（挂起/恢复）
	## - active=true：该实例生效（modifiers/triggers 已注册）
	## - active=false：该实例挂起（撤销 modifiers/监听；但实例仍存在，可到期/可被驱散）
	var active: bool = true

class DotInstance:
	extends RefCounted
	## DOT实例ID（运行时递增，用于稳定排序/追帧）
	var dot_inst_id: int
	## DOT对应的 buff_def_id（用于复用查找：buff_def_id + source_entity_id + tick_phase）
	var buff_def_id: int
	## 该DOT归属的 buff inst_id（便于追溯来源buff实例）
	var owner_buff_inst_id: int
	## 目标实体ID（DOT挂在谁身上）
	var target_entity_id: int
	## 来源实体ID（谁施加的DOT；每跳读取其StatCache）
	var source_entity_id: int
	## DOT层数（用于 DOT 伤害缩放：base_damage = source_stat * base_ratio * stacks）
	var stacks: int = 1
	## 剩余回合数（每次tick扣减，到0移除）
	var remaining_turns: int
	## tick阶段：字符串 "TURN_START"/"TURN_END"（本demo仅用TURN_END）
	var tick_phase: String
	## DOT基础系数：damage = source_stat * base_ratio * stacks
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

## ownership_key -> inst_id（用于 REPLACE/ADD_STACK 的快速定位；MULTI_INSTANCE 不入表）
var inst_id_by_ownership: Dictionary = {}

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

static func _ownership_key(bdid: int, ownership_mode: String, source_entity_id: int) -> int:
	# 说明：最小实现使用 int key；若未来 entity_id 可能超过 65535，可改为 String key。
	var k := 0
	if ownership_mode == "BY_SOURCE_INSTANCE":
		k = source_entity_id
	return (bdid << 16) ^ (k & 0xffff)

func apply_buff(stats: OmniStatsComponent, buff_id_str: String, source_entity_id: int) -> int:
	## 施加一个 buff（生命周期 A1：叠加/归属）
	## - stack.mode: REPLACE / ADD_STACK / MULTI_INSTANCE
	## - stack.ownership_mode: GLOBAL / BY_SOURCE_INSTANCE
	var bdid := ds.buff_id(buff_id_str)
	if bdid < 0:
		push_error("[Buff] unknown buff_id=" + buff_id_str)
		return -1

	var def: Dictionary = ds.buff_defs[bdid]
	var stack: Dictionary = def.get("stack", {})
	var mode := String(stack.get("mode", "REPLACE"))
	var max_stack := int(stack.get("max_stack", 1))
	var ownership_mode := String(stack.get("ownership_mode", "GLOBAL"))

	var dot_def: Dictionary = def.get("dot", {})
	var duration_turns := int(def.get("duration", {}).get("turns", -1))
	var target_entity_id := int(stats.entity_id)
	var dot_tick_phase := String(dot_def.get("tick_phase", "TURN_END"))

	# 兼容：旧实现中 DOT（缺失 stack 配置）默认 MULTI_INSTANCE；
	# 现在 DOT 本身会按 (buff_def_id, source, tick_phase) 复用，因此仍保留该默认值，仅影响 buff 实例数量。
	if (not dot_def.is_empty()) and stack.is_empty():
		mode = "MULTI_INSTANCE"
		ownership_mode = "BY_SOURCE_INSTANCE"

	# 先按 stack.mode 处理 buff 实例（A1/A2），再按新规则 upsert DOT 实例。
	var result_inst_id := -1

	if mode == "MULTI_INSTANCE":
		result_inst_id = _create_new_instance(stats, bdid, source_entity_id, -1)
		if not dot_def.is_empty():
			_upsert_dot_for_apply(target_entity_id, bdid, source_entity_id, result_inst_id, dot_def, mode, max_stack, duration_turns, def.get("tags", []))
		return result_inst_id

	var key := _ownership_key(bdid, ownership_mode, source_entity_id)
	var old_inst_id := int(inst_id_by_ownership.get(key, -1))

	if old_inst_id < 0:
		# DOT（按来源实例）的规则：max_stack 表示“目标总上限（跨来源共享）”
		# 若总上限已满，则不为“新来源”创建 0-stack 的 buff 实例。
		if mode == "ADD_STACK" and (not dot_def.is_empty()) and ownership_mode == "BY_SOURCE_INSTANCE":
			var total_before: int = _dot_total_stacks(target_entity_id, bdid, dot_tick_phase)
			if total_before >= max_stack:
				# 新增语义：新来源无法创建实例，但仍刷新“其他来源”的 remaining_turns（本 buff 的 refresh_policy 控制）
				var refresh_policy := String(stack.get("refresh_policy", ""))
				if refresh_policy == "":
					refresh_policy = "RESET_TO_MAX"
				if refresh_policy == "RESET_TO_MAX":
					_refresh_dot_all_sources(target_entity_id, bdid, dot_tick_phase, duration_turns)
				return -1
		result_inst_id = _create_new_instance(stats, bdid, source_entity_id, key)
		inst_id_by_ownership[key] = result_inst_id
		if not dot_def.is_empty():
			_upsert_dot_for_apply(target_entity_id, bdid, source_entity_id, result_inst_id, dot_def, mode, max_stack, duration_turns, def.get("tags", []))
		return result_inst_id

	var old_inst: BuffInst = instances_by_id.get(old_inst_id, null)
	if old_inst == null:
		inst_id_by_ownership.erase(key)
		# 最小恢复：递归一次重新走创建逻辑
		return apply_buff(stats, buff_id_str, source_entity_id)

	if mode == "REPLACE":
		# E1：REPLACE 时若存在可复用的 DOT，则先暂时“解绑 owner_buff_inst_id”，避免 remove_by_instance 把它清掉。
		if not dot_def.is_empty():
			var reuse_dot := _find_dot_instance(target_entity_id, bdid, source_entity_id, dot_tick_phase)
			if reuse_dot != null:
				reuse_dot.owner_buff_inst_id = -1

		remove_by_instance(stats, old_inst_id, true)
		result_inst_id = _create_new_instance(stats, bdid, source_entity_id, key)
		inst_id_by_ownership[key] = result_inst_id

		if not dot_def.is_empty():
			_upsert_dot_for_apply(target_entity_id, bdid, source_entity_id, result_inst_id, dot_def, mode, max_stack, duration_turns, def.get("tags", []))
		return result_inst_id

	if mode == "ADD_STACK":
		# A2：ADD_STACK 命中已有实例时，是否刷新 remaining_turns 由 refresh_policy 驱动
		# - 缺失/空字符串：默认 RESET_TO_MAX（保持旧行为）
		# - RESET_TO_MAX：重置 remaining_turns=turns
		# - 其它值（例如 NONE）：不刷新 remaining_turns
		var refresh_policy := String(stack.get("refresh_policy", ""))
		if refresh_policy == "":
			refresh_policy = "RESET_TO_MAX"
		# stacks：对 DOT（按来源实例）而言，max_stack 表示“目标总上限（跨来源共享）”
		# - 若总上限未满：本来源 stacks +1
		# - 若总上限已满：本来源 stacks 不变（但仍刷新时长）
		if not dot_def.is_empty() and ownership_mode == "BY_SOURCE_INSTANCE":
			var total_before: int = _dot_total_stacks(target_entity_id, bdid, dot_tick_phase)
			if total_before < max_stack:
				old_inst.stacks = min(old_inst.stacks + 1, max_stack)
		else:
			old_inst.stacks = min(old_inst.stacks + 1, max_stack)
		if refresh_policy == "RESET_TO_MAX":
			old_inst.remaining_turns = duration_turns
		# 让 modifier 随 stacks 生效（线性：value * stacks）
		# A4：若该实例处于 inactive（while-condition 不满足），则不要重建 modifiers（避免“挂起但仍生效”）
		if old_inst.active:
			_rebuild_instance_modifiers(stats, old_inst_id)

		# E1：ADD_STACK 时 DOT 也应按 (buff_def_id, source, tick_phase) 复用并增加 stacks（capped），同时刷新 remaining_turns
		if not dot_def.is_empty():
			_upsert_dot_for_apply(target_entity_id, bdid, source_entity_id, old_inst_id, dot_def, mode, max_stack, duration_turns, def.get("tags", []))
		return old_inst_id

	# 未知 mode：退化为 MULTI_INSTANCE（避免“吃掉 buff”）
	result_inst_id = _create_new_instance(stats, bdid, source_entity_id, -1)
	if not dot_def.is_empty():
		_upsert_dot_for_apply(target_entity_id, bdid, source_entity_id, result_inst_id, dot_def, mode, max_stack, duration_turns, def.get("tags", []))
	return result_inst_id

func _find_dot_instance(target_entity_id: int, buff_def_id: int, source_entity_id: int, tick_phase: String) -> DotInstance:
	# 内部：按 (buff_def_id, source_entity_id, tick_phase) 查找可复用 DOT
	if not dots_by_target.has(target_entity_id):
		return null
	var dots: Array = dots_by_target[target_entity_id]
	for x in dots:
		var d: DotInstance = x
		if d == null:
			continue
		if int(d.buff_def_id) != buff_def_id:
			continue
		if int(d.source_entity_id) != source_entity_id:
			continue
		if String(d.tick_phase) != tick_phase:
			continue
		return d
	return null

func _dot_total_stacks(target_entity_id: int, buff_def_id: int, tick_phase: String) -> int:
	# 内部：统计同一 target 上，同一 DOT（buff_def_id + tick_phase）跨来源的总 stacks
	if not dots_by_target.has(target_entity_id):
		return 0
	var dots: Array = dots_by_target[target_entity_id]
	var total: int = 0
	for x in dots:
		var d: DotInstance = x
		if d == null:
			continue
		if int(d.buff_def_id) != buff_def_id:
			continue
		if String(d.tick_phase) != tick_phase:
			continue
		total += int(d.stacks)
	return total

func _refresh_dot_all_sources(target_entity_id: int, buff_def_id: int, tick_phase: String, duration_turns: int) -> void:
	# 内部：刷新该 target 上该 DOT（buff_def_id+tick_phase）所有来源实例的 remaining_turns
	# 语义：即使“新来源无法获得 stacks（remaining_global==0）”，也可以触发对现有来源的刷新（用于某些技能设计）。
	if not dots_by_target.has(target_entity_id):
		return
	var dots: Array = dots_by_target[target_entity_id]
	for x in dots:
		var d: DotInstance = x
		if d == null:
			continue
		if int(d.buff_def_id) != buff_def_id:
			continue
		if String(d.tick_phase) != tick_phase:
			continue
		d.remaining_turns = duration_turns
		# 同步刷新对应的 buff 实例 remaining_turns（若存在）
		var key := _ownership_key(buff_def_id, "BY_SOURCE_INSTANCE", int(d.source_entity_id))
		var inst_id := int(inst_id_by_ownership.get(key, -1))
		var inst: BuffInst = instances_by_id.get(inst_id, null)
		if inst != null:
			inst.remaining_turns = duration_turns

func _upsert_dot_for_apply(target_entity_id: int, buff_def_id: int, source_entity_id: int, owner_buff_inst_id: int, dot_def: Dictionary, stack_mode: String, max_stack: int, duration_turns: int, buff_tags: Array) -> void:
	# E1：施加/刷新 DOT：
	# - 复用 key = (buff_def_id, source_entity_id, tick_phase)
	# - 复用时 remaining_turns 重置为 turns
	# - 复用时按 stack_mode 更新 stacks：
	#   - ADD_STACK：+1 capped
	#   - REPLACE：1
	#   - 其它：1
	if dot_def.is_empty():
		return
	var tick_phase := String(dot_def.get("tick_phase", "TURN_END"))

	# 规则：对 DOT（按来源实例）而言，max_stack 表示“目标总上限（跨来源共享）”
	# remaining = max_stack - total_stacks(target, buff_def_id, tick_phase)
	var total_before: int = _dot_total_stacks(target_entity_id, buff_def_id, tick_phase)
	var remaining_global: int = max(0, max_stack - total_before)

	var d := _find_dot_instance(target_entity_id, buff_def_id, source_entity_id, tick_phase)
	var reused := (d != null)
	if d == null:
		# 新来源：若总上限已满，则不创建 0-stack 实例
		if stack_mode == "ADD_STACK" and remaining_global <= 0:
			return
		d = DotInstance.new()
		d.dot_inst_id = next_dot_inst_id
		next_dot_inst_id += 1
		d.buff_def_id = buff_def_id
		d.target_entity_id = target_entity_id
		d.source_entity_id = source_entity_id
		d.tick_phase = tick_phase
		d.stacks = 1
		if not dots_by_target.has(target_entity_id):
			dots_by_target[target_entity_id] = []
		(dots_by_target[target_entity_id] as Array).append(d)

	# 刷新公共字段（即使复用也更新，避免配置变更时出现“旧字段残留”）
	d.owner_buff_inst_id = owner_buff_inst_id
	d.remaining_turns = duration_turns
	d.base_ratio = float(dot_def.get("base_ratio", 0.0))
	d.read_source_stat = String(dot_def.get("read_source_stat", "ATK"))
	if enums_rt != null:
		d.tags_mask = enums_rt.tag_mask(buff_tags)
	else:
		d.tags_mask = 0

	# stacks 更新（仅复用时需要根据 stack_mode 变化；新建保持 1）
	if reused:
		if stack_mode == "ADD_STACK":
			# 同来源实例叠层：先看全局 remaining，再决定本次是否 +1
			if remaining_global > 0:
				d.stacks = int(d.stacks) + 1
			# 最终保证目标总上限不被突破（避免数据不一致）
			# 这里不尝试回收其它来源的 stacks（先来先占）
			# 若 remaining_global==0，则仅刷新 remaining_turns，不增加 stacks
		else:
			d.stacks = 1

func _create_new_instance(stats: OmniStatsComponent, bdid: int, source_entity_id: int, ownership_key: int = -1) -> int:
	# 内部：创建实例 + 注入 modifiers + 注册 triggers + 生成 DOT（保持旧行为）
	var inst := BuffInst.new()
	inst.inst_id = next_inst_id
	next_inst_id += 1
	inst.ownership_key = ownership_key
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
	_rebuild_instance_modifiers(stats, inst.inst_id)

	# === triggers -> EventIndex（事件型：变动时注册监听）===
	_register_triggers_for_instance(inst, ds.buff_defs[bdid])

	# A4：创建后立即评估 while-condition；不满足则 deactivate（但保留实例 + DOT实例）
	var def: Dictionary = ds.buff_defs[bdid]
	if not _conditions_satisfied(stats, def):
		_deactivate_instance(stats, inst)

	return inst.inst_id

func _conditions_satisfied(stats: OmniStatsComponent, def: Dictionary) -> bool:
	# A4 v1：仅实现 STAT_THRESHOLD
	var conds: Array = def.get("conditions", [])
	if conds.is_empty():
		return true
	for c in conds:
		if String(c.get("condition_type", "")) != "STAT_THRESHOLD":
			# v1：未知条件类型先忽略（避免“吃掉 buff”）
			continue
		var stat_id := ds.stat_id(String(c.get("stat", "")))
		if stat_id < 0:
			continue
		var op := String(c.get("op", "LE"))
		var rhs := float(c.get("value", 0.0))
		var lhs := float(stats.get_final(stat_id))
		var ok := true
		match op:
			"LE": ok = lhs <= rhs
			"LT": ok = lhs < rhs
			"GE": ok = lhs >= rhs
			"GT": ok = lhs > rhs
			_: ok = true
		if not ok:
			return false
	return true

func _deactivate_instance(stats: OmniStatsComponent, inst: BuffInst) -> void:
	# A4：撤销 modifiers + 注销 triggers，保留实例（用于到期/驱散）
	if inst == null:
		return
	_remove_modifiers_for_inst(stats, inst)
	_unregister_listeners_for_inst(int(inst.inst_id))
	# 避免 active/inactive 来回切时 listener id 列表无限增长
	listener_ids_by_inst[int(inst.inst_id)] = PackedInt32Array()
	inst.active = false

func _activate_instance(stats: OmniStatsComponent, inst: BuffInst, def: Dictionary) -> void:
	# A4：恢复 modifiers + triggers
	if inst == null:
		return
	_rebuild_instance_modifiers(stats, int(inst.inst_id))
	_register_triggers_for_instance(inst, def)
	inst.active = true

func _register_triggers_for_instance(inst: BuffInst, def: Dictionary) -> void:
	# 内部：从 buff_def 注册 triggers（供 create/activate 复用）
	if inst == null:
		return
	if enums_rt == null:
		return
	var triggers: Array = def.get("triggers", [])
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
		l.inst_id = int(inst.inst_id)
		l.filter_tag_mask = filter_mask
		# D：额外 filters
		l.filter_require_hit = bool(filters.get("require_hit", false))
		l.filter_require_crit = bool(filters.get("require_crit", false))
		# skill_id：-1 表示不过滤
		if filters.has("skill_id"):
			l.filter_skill_id = int(filters.get("skill_id", -1))
		# damage_type_any / element_any：映射为 bitmask
		if filters.has("damage_type_any"):
			var arr_dt: Array = filters.get("damage_type_any", [])
			var m_dt := 0
			for s in arr_dt:
				var code := int(enums_rt.enum_int("damage_type", String(s)))
				if code >= 0:
					m_dt |= (1 << code)
			l.filter_damage_type_mask_any = m_dt
		if filters.has("element_any"):
			var arr_el: Array = filters.get("element_any", [])
			var m_el := 0
			for s in arr_el:
				var code := int(enums_rt.enum_int("element", String(s)))
				if code >= 0:
					m_el |= (1 << code)
			l.filter_element_mask_any = m_el
		l.filter_require_shield_absorbed = bool(filters.get("require_shield_absorbed", false))
		if filters.has("min_absorbed_shield"):
			l.filter_min_absorbed_shield = float(filters.get("min_absorbed_shield", 0.0))
		if filters.has("min_final_damage"):
			l.filter_min_final_damage = float(filters.get("min_final_damage", 0.0))
		var st: Variant = filters.get("stat_threshold", null)
		if typeof(st) == TYPE_DICTIONARY:
			var std: Dictionary = st
			l.filter_stat_scope = String(std.get("scope", ""))
			l.filter_stat = String(std.get("stat", ""))
			l.filter_stat_op = String(std.get("op", ""))
			l.filter_stat_value = float(std.get("value", 0.0))

		l.action_kind = String(action.get("kind", ""))
		l.action_value = float(action.get("value", 0.0))
		# Phase 1 actions：payload
		# - LIFESTEAL / REFLECT_DAMAGE
		if action.has("ratio"):
			l.action_ratio = float(action.get("ratio", 0.0))
		# - DISPEL
		if action.has("mode"):
			l.action_dispel_mode = String(action.get("mode", ""))
		if action.has("tag"):
			l.action_dispel_tag = String(action.get("tag", ""))
		if action.has("buff_type"):
			l.action_dispel_buff_type = String(action.get("buff_type", ""))
		if action.has("source"):
			l.action_dispel_source_scope = String(action.get("source", ""))
		if action.has("include_implicit"):
			l.action_include_implicit = bool(action.get("include_implicit", false))
		# D：SET_STAT_FINAL payload
		if l.action_kind == "SET_STAT_FINAL":
			l.action_stat = String(action.get("stat", ""))
		# APPLY_BUFF / CHANCE_APPLY_BUFF 的 payload
		if action.has("buff_id"):
			l.action_buff_id = String(action.get("buff_id", ""))
		elif action.has("apply_buff_id"):
			l.action_buff_id = String(action.get("apply_buff_id", ""))
		# 可选：额外叠层（默认 1）
		if action.has("add_stacks"):
			l.action_add_stacks = int(action.get("add_stacks", 1))
		l.action_chance = float(action.get("chance", 1.0))
		# DOT_* payload
		if action.has("dot_buff_id"):
			l.action_dot_buff_id = String(action.get("dot_buff_id", ""))
		if action.has("dot_tags_mask_any"):
			var arr: Array = action.get("dot_tags_mask_any", [])
			l.action_dot_tag_mask_any = int(enums_rt.tag_mask(arr))
		l.scope = String(t.get("scope", "SELF"))
		var lid := event_index.register_listener(key, l)
		if not listener_ids_by_inst.has(int(inst.inst_id)):
			listener_ids_by_inst[int(inst.inst_id)] = PackedInt32Array()
		(listener_ids_by_inst[int(inst.inst_id)] as PackedInt32Array).append(lid)

func _remove_modifiers_for_inst(stats: OmniStatsComponent, inst: BuffInst) -> void:
	# 内部：仅撤销一个实例注入到 StatsCore 的 modifiers（不移除实例本身）
	if inst == null:
		return
	var inst_id := int(inst.inst_id)
	for mr in inst.modifier_refs:
		var stat_id := int(mr.stat_id)
		var list: Array = stats.core.modifiers_by_stat[stat_id]
		var kept: Array = []
		for x in list:
			if int(x.source_inst_id) != inst_id:
				kept.append(x)
		stats.core.modifiers_by_stat[stat_id] = kept
		stats.core.mark_dirty(stat_id)
	inst.modifier_refs = []

func _rebuild_instance_modifiers(stats: OmniStatsComponent, inst_id: int) -> void:
	# 内部：按当前 stacks 重建该实例注入的 modifiers（线性叠加：value * stacks）
	var inst: BuffInst = instances_by_id.get(inst_id, null)
	if inst == null:
		return
	_remove_modifiers_for_inst(stats, inst)

	var bdid := int(inst.buff_def_id)
	var def: Dictionary = ds.buff_defs[bdid]
	var effects: Array = def.get("effects", [])
	for e in effects:
		if String(e.get("kind", "")) != "modifier":
			continue
		var op := String(e.get("op", ""))
		var phase := String(e.get("phase", ""))
		# 当前运行时支持（C plan Task4）：
		# - ADD/FLAT（平铺加成）
		# - MUL/PERCENT（百分比加成：最终值按 (base+flat)*(1+pct) 计算）
		# - ADD/FINAL（最终加成：在 OVERRIDE 裁决后再叠加）
		# - OVERRIDE/FINAL（最终覆盖：按 priority/后施加胜）
		var supported := (op == "ADD" and (phase == "FLAT" or phase == "FINAL")) \
			or (op == "MUL" and phase == "PERCENT") \
			or (op == "OVERRIDE" and phase == "FINAL")
		if not supported:
			continue

		var stat_id := ds.stat_id(String(e.get("stat", "")))
		if stat_id < 0:
			push_error("[Buff] unknown stat in effect: " + str(e))
			continue
		var base_v := float(e.get("value", 0.0))
		var v := base_v * float(max(1, int(inst.stacks)))

		var mr := OmniModifierRef.new()
		mr.stat_id = stat_id
		mr.op = op
		mr.phase = phase
		mr.layer = int(e.get("layer", 0))
		mr.priority = int(e.get("priority", 0))
		mr.value = v
		if op == "ADD" and phase == "FLAT":
			mr.add_value = v
		else:
			mr.add_value = 0.0
		mr.source_inst_id = inst.inst_id

		inst.modifier_refs.append(mr)
		stats.core.modifiers_by_stat[stat_id].append(mr)
		stats.core.mark_dirty(stat_id)

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

	# 0) 同步维护 ownership lookup（避免 remove 后 apply_buff 仍命中旧 inst_id）
	if inst.ownership_key != -1:
		var k := int(inst.ownership_key)
		if inst_id_by_ownership.has(k) and int(inst_id_by_ownership[k]) == inst_id:
			inst_id_by_ownership.erase(k)

	# 1) 从 StatsCore 聚合视图中撤销 modifier
	_remove_modifiers_for_inst(stats, inst)

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

func remove_by_buff_id(stats: OmniStatsComponent, buff_id_str: String, scope: String = "ALL", source_entity_id: int = -1, include_implicit: bool = false, force: bool = false) -> int:
	## A5：按 buff_id 主动移除（与 dispel_* 语义区分：remove_* 不检查“驱散免疫”）
	## - scope: "ALL" | "FIRST"
	## - source_entity_id>=0: 仅移除来自该 source 的实例
	## - include_implicit=false: 默认不移除 IMPLICIT/PASSIVE（保持与 dispel 默认一致）
	## - force=true: 强制移除（无视 undispellable）
	var bdid: int = int(ds.buff_id(buff_id_str))
	if bdid < 0:
		return 0

	var removed: int = 0
	for inst_id in inst_ids.duplicate():
		var inst: BuffInst = instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		if int(inst.buff_def_id) != bdid:
			continue
		if source_entity_id >= 0 and int(inst.source_entity_id) != source_entity_id:
			continue
		if (not include_implicit) and (inst.buff_type == "IMPLICIT" or inst.buff_type == "PASSIVE"):
			continue
		if (not force) and inst.undispellable:
			continue
		if remove_by_instance(stats, int(inst.inst_id), true):
			removed += 1
			if scope == "FIRST":
				break
	return removed

func remove_by_tag(stats: OmniStatsComponent, tag_id: String, scope: String = "ALL", source_entity_id: int = -1, include_implicit: bool = false, force: bool = false) -> int:
	## A5：按 tag 主动移除（不检查“驱散免疫”）
	if enums_rt == null:
		return 0
	var tag_mask: int = int(enums_rt.tag_mask([tag_id]))
	if tag_mask == 0:
		return 0

	var removed: int = 0
	for inst_id in inst_ids.duplicate():
		var inst: BuffInst = instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		if source_entity_id >= 0 and int(inst.source_entity_id) != source_entity_id:
			continue
		if (not include_implicit) and (inst.buff_type == "IMPLICIT" or inst.buff_type == "PASSIVE"):
			continue
		if (not force) and inst.undispellable:
			continue
		if (int(inst.tag_mask) & tag_mask) == 0:
			continue
		if remove_by_instance(stats, int(inst.inst_id), true):
			removed += 1
			if scope == "FIRST":
				break
	return removed

func remove_by_source(stats: OmniStatsComponent, source_entity_id: int, scope: String = "ALL", include_implicit: bool = false, force: bool = false) -> int:
	## A5：按来源实体主动移除（不检查“驱散免疫”）
	var removed: int = 0
	for inst_id in inst_ids.duplicate():
		var inst: BuffInst = instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		if int(inst.source_entity_id) != source_entity_id:
			continue
		if (not include_implicit) and (inst.buff_type == "IMPLICIT" or inst.buff_type == "PASSIVE"):
			continue
		if (not force) and inst.undispellable:
			continue
		if remove_by_instance(stats, int(inst.inst_id), true):
			removed += 1
			if scope == "FIRST":
				break
	return removed

func dispel_by_tag(stats: OmniStatsComponent, tag_id: String, include_implicit: bool = false) -> int:
	## 按 Tag 驱散（M7）
	## - include_implicit=false：默认不驱散 IMPLICIT/PASSIVE（符合“装备/加点/套装不应被常规驱散”）
	if enums_rt == null:
		return 0
	# B5：驱散免疫（按约定影响全部 dispel_*；只要 mask 非 0 就阻止驱散）
	if target_dispel_immunity_mask != 0:
		return 0
	var tag_mask := enums_rt.tag_mask([tag_id])
	if tag_mask == 0:
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
	# B5：驱散免疫（按约定影响全部 dispel_*）
	if target_dispel_immunity_mask != 0:
		return 0
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
	# B5：驱散免疫（按约定影响全部 dispel_*）
	if target_dispel_immunity_mask != 0:
		return 0
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
	var lids := PackedInt32Array()
	if listener_ids_by_inst.has(inst_id):
		lids = listener_ids_by_inst[inst_id]

	# 正常路径：通过 listener_ids_by_inst 精确移除
	for lid in lids:
		var l = event_index.listener_data[lid]
		if l != null and l.active:
			l.active = false
			var key: int = int(l.key)
			# 从 listeners[key] 中移除该 lid（最小实现：重建数组）
			var arr := event_index.listeners[key]
			var out := PackedInt32Array()
			for x in arr:
				if x != lid:
					out.append(x)
			event_index.listeners[key] = out

	# 兜底路径：若 listener_ids_by_inst 丢失/为空（例如历史 bug，或 active/inactive 切换导致记录被清空），
	# 则扫描 listener_data，按 inst_id 匹配并移除。
	for lid in range(event_index.listener_data.size()):
		var l2 = event_index.listener_data[lid]
		if l2 == null or (not l2.active):
			continue
		if int(l2.inst_id) != inst_id:
			continue
		l2.active = false
		var key2: int = int(l2.key)
		var arr2 := event_index.listeners[key2]
		var out2 := PackedInt32Array()
		for x2 in arr2:
			if int(x2) != int(lid):
				out2.append(x2)
		event_index.listeners[key2] = out2

	# 清理记录，避免后续误用
	if listener_ids_by_inst.has(inst_id):
		listener_ids_by_inst.erase(inst_id)

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
	# PERF(J2)：禁止遍历全实体 keys（例如 stats_by_entity.keys()/buff_by_entity.keys()），
	# 只允许遍历“当前 target(owner_entity_id) 的 DOT 池”这一子集（dots_by_target[owner_entity_id]）。
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

	# E1：两段式 DOT tick：
	# 1) 逐 DOT 计算 base_damage_i = source_stat * base_ratio * stacks，并记录 dot_trace 输入
	# 2) 按 tags_mask 汇总 sum_base_damage_by_tags，并对每个 tags_mask 调一次 pipeline.deal_damage_with_tags
	#    - replay.damage_traces 增量 == tags_mask 分组数
	var kept: Array = []
	var groups: Dictionary = {} # tags_mask(int) -> {sum_base: float, items: Array, attacker_stats, attacker_buff}
	var ticked_items_all: Array = [] # 用于稳定输出 dot_traces（dot_inst_id 升序）

	for x in dots:
		var d: DotInstance = x
		if d == null:
			continue
		# 仅处理匹配 tick_phase 的DOT；其它DOT保持不动
		if String(d.tick_phase) != tick_phase:
			kept.append(d)
			continue
		if int(d.remaining_turns) <= 0:
			continue

		# A4：若该DOT归属的 buff 实例处于 inactive，则暂停 tick 且不递减 remaining_turns
		var owner_inst: BuffInst = instances_by_id.get(int(d.owner_buff_inst_id), null)
		if owner_inst == null or (not owner_inst.active):
			kept.append(d)
			continue

		var source_stats: OmniStatsComponent = stats_by_entity.get(int(d.source_entity_id), null)
		var source_buff: OmniBuffCore = buff_by_entity.get(int(d.source_entity_id), null)
		if source_stats == null or source_buff == null:
			# 来源不存在：直接丢弃该DOT（避免僵尸引用）
			continue

		# 动态读取施法者当前属性：必须走 StatCache（禁止遍历来源Buff）
		var read_stat_id: int = dataset.stat_id(String(d.read_source_stat))
		var src_v: float = source_stats.get_final(read_stat_id)

		# E1：base_damage_i 乘 stacks
		var stacks_f := float(max(1, int(d.stacks)))
		var base_damage_i: float = src_v * float(d.base_ratio) * stacks_f

		var tm := int(d.tags_mask)
		if not groups.has(tm):
			groups[tm] = {
				"sum_base": 0.0,
				"items": [],
				# 聚合结算需要一个 attacker/buff 入口；此处取该 tags_mask 组内第一个 DOT 的来源
				"attacker_stats": source_stats,
				"attacker_buff": source_buff,
			}
		var g: Dictionary = groups[tm]
		g["sum_base"] = float(g.get("sum_base", 0.0)) + base_damage_i

		var item := {
			"dot": d,
			"source_stat_value": src_v,
			"base_damage": base_damage_i,
			"final_damage": 0.0,
		}
		(g["items"] as Array).append(item)
		ticked_items_all.append(item)
		groups[tm] = g

	# 先按 tags_mask 分组结算一次伤害（damage_traces 分段=分组数），再回填每个 DOT 的 final_damage（按 base_damage 占比分摊）
	var masks: Array = groups.keys()
	masks.sort()
	for m in masks:
		var g: Dictionary = groups[int(m)]
		var sum_base: float = float(g.get("sum_base", 0.0))
		var attacker_stats: OmniStatsComponent = g.get("attacker_stats", null)
		var attacker_buff: OmniBuffCore = g.get("attacker_buff", null)
		if attacker_stats == null or attacker_buff == null:
			continue

		var ctx := pipeline.deal_damage_with_tags(attacker_stats, target_stats, attacker_buff, target_buff, dataset, sum_base, int(m), replay, turn_index)
		var group_final := float(ctx.final_damage)

		var items: Array = g.get("items", [])
		var allocated := 0.0
		for i in range(items.size()):
			var it: Dictionary = items[i]
			var bd := float(it.get("base_damage", 0.0))
			var fd := 0.0
			if i == items.size() - 1:
				# 最后一段吃掉浮点误差，保证 sum(dot_final)==group_final
				fd = group_final - allocated
			else:
				if sum_base > 0.0:
					fd = group_final * (bd / sum_base)
				else:
					fd = 0.0
				allocated += fd
			it["final_damage"] = fd
			items[i] = it
		g["items"] = items
		groups[int(m)] = g

	# 追帧：按 dot_inst_id 升序输出每个 DOT 的 dot_trace（每 DOT 一条）
	ticked_items_all.sort_custom(func(a, b):
		var da: DotInstance = a.get("dot", null)
		var db: DotInstance = b.get("dot", null)
		if da == null or db == null:
			return false
		return int(da.dot_inst_id) < int(db.dot_inst_id)
	)
	for it in ticked_items_all:
		var d: DotInstance = it.get("dot", null)
		if d == null:
			continue
		var src_v := float(it.get("source_stat_value", 0.0))
		var base_damage_i := float(it.get("base_damage", 0.0))
		var final_damage_i := float(it.get("final_damage", 0.0))
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
				float(base_damage_i),
				float(final_damage_i),
				int(d.tags_mask)
			)

		# 到期递减（保持 A4 inactive 暂停逻辑：inactive 时前面已 continue，不会走到这里）
		d.remaining_turns -= 1
		if int(d.remaining_turns) > 0:
			kept.append(d)

	# 回写（移除到期DOT）
	dots_by_target[owner_entity_id] = kept

func on_turn_start(turn_index: int, stats_by_entity: Dictionary = {}, buff_by_entity: Dictionary = {}, pipeline: OmniDamagePipeline = null, dataset: OmniCompiledDataset = null, replay: RefCounted = null) -> void:
	# TurnStart tick（DOT结算）
	# 兼容：允许旧调用只传 turn_index，此时不会触发DOT结算
	if pipeline == null or dataset == null:
		return
	_eval_while_conditions_and_toggle_active(stats_by_entity)
	_tick_dots(turn_index, "TURN_START", stats_by_entity, buff_by_entity, pipeline, dataset, replay)
	_tick_non_dot_turns("TURN_START", stats_by_entity)

func on_turn_end(turn_index: int, stats_by_entity: Dictionary, buff_by_entity: Dictionary, pipeline: OmniDamagePipeline, dataset: OmniCompiledDataset, replay: RefCounted = null) -> void:
	# TurnEnd tick（DOT结算）
	_eval_while_conditions_and_toggle_active(stats_by_entity)
	_tick_dots(turn_index, "TURN_END", stats_by_entity, buff_by_entity, pipeline, dataset, replay)
	_tick_non_dot_turns("TURN_END", stats_by_entity)

func _eval_while_conditions_and_toggle_active(stats_by_entity: Dictionary) -> void:
	# A4：在 TurnStart/TurnEnd tick 中评估 while-condition，并切换 active 状态（挂起/恢复）
	if owner_entity_id < 0:
		return
	if stats_by_entity.is_empty():
		return
	var owner_stats: OmniStatsComponent = stats_by_entity.get(owner_entity_id, null)
	if owner_stats == null:
		return

	for inst_id in inst_ids.duplicate():
		var inst: BuffInst = instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		var def: Dictionary = ds.buff_defs[int(inst.buff_def_id)]
		var want_active := _conditions_satisfied(owner_stats, def)
		if want_active == inst.active:
			continue
		if want_active:
			_activate_instance(owner_stats, inst, def)
		else:
			_deactivate_instance(owner_stats, inst)

func _tick_non_dot_turns(tick_phase: String, stats_by_entity: Dictionary) -> void:
	# 内部：非 DOT 的 TURNS buff 到期递减与移除（按 duration.tick_phase）
	if owner_entity_id < 0:
		return
	if stats_by_entity.is_empty():
		return
	var owner_stats: OmniStatsComponent = stats_by_entity.get(owner_entity_id, null)
	if owner_stats == null:
		return

	# 注意：remove_by_instance 会修改 inst_ids，因此这里用副本遍历，避免跳过元素
	for inst_id in inst_ids.duplicate():
		var inst: BuffInst = instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		var def: Dictionary = ds.buff_defs[int(inst.buff_def_id)]

		# 非 DOT 才走这里（DOT 生命周期由 DotInstance 管理）
		var dot_def: Dictionary = def.get("dot", {})
		if not dot_def.is_empty():
			continue

		var duration: Dictionary = def.get("duration", {})
		if String(duration.get("type", "")) != "TURNS":
			continue
		var turns := int(duration.get("turns", -1))
		if turns <= 0:
			continue
		var ph := String(duration.get("tick_phase", "TURN_END"))
		if ph != tick_phase:
			continue

		inst.remaining_turns -= 1
		if inst.remaining_turns <= 0:
			remove_by_instance(owner_stats, int(inst_id), true)

func emit_event(event_type: String, phase: String, ctx: RefCounted) -> void:
	## 触发事件（最小可用版）
	## PERF(J2)：禁止遍历全实体 keys（例如“全场单位/全体Buff”的索引或 Dictionary.keys()），
	## 只允许遍历 listeners[key]（监听该事件的子集），满足“禁止遍历全部Buff”的性能约束。
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
		# D：require_hit
		if l.filter_require_hit and (not bool(ctx.hit)):
			continue
		# Phase 1：require_crit
		if l.filter_require_crit and (not bool(ctx.crit)):
			continue
		# Phase 1：skill_id
		if int(l.filter_skill_id) >= 0 and int(ctx.skill_id) != int(l.filter_skill_id):
			continue
		# Phase 1：damage_type_any / element_any
		if int(l.filter_damage_type_mask_any) != 0:
			var dt_bit := (1 << int(ctx.damage_type))
			if (int(l.filter_damage_type_mask_any) & dt_bit) == 0:
				continue
		if int(l.filter_element_mask_any) != 0:
			var el_bit := (1 << int(ctx.element))
			if (int(l.filter_element_mask_any) & el_bit) == 0:
				continue
		# Phase 1：shield absorbed / thresholds
		var absorbed := 0.0
		if ctx.has_meta("absorbed_shield"):
			absorbed = float(ctx.get_meta("absorbed_shield"))
		if l.filter_require_shield_absorbed and absorbed <= 0.0:
			continue
		if float(l.filter_min_absorbed_shield) > 0.0 and absorbed < float(l.filter_min_absorbed_shield):
			continue
		# Phase 1：min_final_damage（仅在 resolve/apply 后的 phase 才可能有意义）
		if float(l.filter_min_final_damage) > 0.0 and float(ctx.final_damage) < float(l.filter_min_final_damage):
			continue
		# D：stat_threshold
		if l.filter_stat != "":
			if not ctx.has_meta("runtime"):
				continue
			var rt: Variant = ctx.get_meta("runtime")
			if typeof(rt) != TYPE_DICTIONARY:
				continue
			var runtime: Dictionary = rt
			var stats_by_entity: Dictionary = runtime.get("stats_by_entity", {})
			var feid := _resolve_scope_entity_id(l.filter_stat_scope, ctx)
			if feid < 0:
				continue
			var fstats: OmniStatsComponent = stats_by_entity.get(feid, null)
			if fstats == null:
				continue
			var fsid := ds.stat_id(l.filter_stat)
			if fsid < 0:
				continue
			var lhs := float(fstats.get_final(fsid))
			var rhs := float(l.filter_stat_value)
			var ok := true
			match String(l.filter_stat_op).to_upper():
				"GT":
					ok = lhs > rhs
				"GE":
					ok = lhs >= rhs
				"LT":
					ok = lhs < rhs
				"LE":
					ok = lhs <= rhs
				_:
					ok = true
			if not ok:
				continue
		_triggered_inst_ids_last_emit.append(l.inst_id)
		match l.action_kind:
			"ADD_BASE_DAMAGE":
				ctx.base_damage += l.action_value
			"APPLY_BUFF":
				_apply_buff_from_event(l, ctx, false)
			"CHANCE_APPLY_BUFF":
				_apply_buff_from_event(l, ctx, true)
			"SET_STAT_FINAL":
				_set_stat_final_from_event(l, ctx)
			"SET_SHIELD_TO_FINAL_DAMAGE":
				_set_shield_to_final_damage_from_event(l, ctx)
			"ADD_SHIELD":
				_add_shield_from_event(l, ctx)
			"HEAL":
				_heal_from_event(l, ctx)
			"DISPEL":
				_dispel_from_event(l, ctx)
			"LIFESTEAL":
				_lifesteal_from_event(l, ctx)
			"REFLECT_DAMAGE":
				_reflect_damage_from_event(l, ctx)
			"DOT_MUL_STACKS", "DOT_ADD_STACKS", "DOT_SET_STACKS", "DOT_CLEAR":
				_apply_dot_action_from_event(l, ctx)
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
	# 可选：额外叠层（默认 1）。语义：同一来源+同一buff 的 apply，会合并并增加 stacks。
	var add_stacks: int = int(l.action_add_stacks)
	if add_stacks < 1:
		add_stacks = 1
	for _i in range(add_stacks):
		target_buff.apply_buff(target_stats, l.action_buff_id, source_eid)

func _apply_dot_action_from_event(l: OmniEventIndex.Listener, ctx: RefCounted) -> void:
	## 事件动作：对目标身上的 DOT 实例做 stacks 操作（E2）
	## - DOT_MUL_STACKS / DOT_ADD_STACKS / DOT_SET_STACKS / DOT_CLEAR
	## - 支持按 dot_buff_id / dot_tags_mask_any 过滤（两者都提供则需同时满足）
	##
	## 运行时依赖：ctx.meta["runtime"].buff_by_entity
	if not ctx.has_meta("runtime"):
		return
	var rt: Variant = ctx.get_meta("runtime")
	if typeof(rt) != TYPE_DICTIONARY:
		return
	var runtime: Dictionary = rt
	var buff_by_entity: Dictionary = runtime.get("buff_by_entity", {})

	# 解析目标实体ID（被操作 DOT 的承载者）
	var target_eid := _resolve_scope_entity_id(l.scope, ctx)
	if target_eid < 0:
		return
	var target_buff: OmniBuffCore = buff_by_entity.get(target_eid, null)
	if target_buff == null:
		return

	if not target_buff.dots_by_target.has(target_eid):
		return
	var dots: Array = target_buff.dots_by_target.get(target_eid, [])
	if dots.is_empty():
		return

	# 过滤条件：dot_buff_id（字符串 -> buff_def_id）
	var filter_bdid := -1
	if String(l.action_dot_buff_id) != "":
		filter_bdid = int(ds.buff_id(String(l.action_dot_buff_id)))
		# 配置给了未知 dot_buff_id：视为 no-op
		if filter_bdid < 0:
			return

	# 过滤条件：dot_tags_mask_any（bitmask；0 表示不做 tag 过滤）
	var filter_tags_mask_any := int(l.action_dot_tag_mask_any)

	var kept: Array = []
	for x in dots:
		var d: DotInstance = x
		if d == null:
			continue

		# 按 dot_buff_id 过滤
		if filter_bdid >= 0 and int(d.buff_def_id) != filter_bdid:
			kept.append(d)
			continue

		# 按 dot_tag_mask_any 过滤（要求命中任意 tag）
		if filter_tags_mask_any != 0 and (int(d.tags_mask) & filter_tags_mask_any) == 0:
			kept.append(d)
			continue

		var stacks := int(d.stacks)
		match String(l.action_kind):
			"DOT_MUL_STACKS":
				stacks = stacks * int(l.action_value)
			"DOT_ADD_STACKS":
				stacks = stacks + int(l.action_value)
			"DOT_SET_STACKS":
				stacks = int(l.action_value)
			"DOT_CLEAR":
				stacks = 0
			_:
				# 不属于 DOT action：保持不变
				kept.append(d)
				continue

		# <=0 视为清除该 DOT
		if stacks <= 0:
			continue

		# cap by max_stack（从 dot 对应 buff_def.stack.max_stack 读取）
		var def: Dictionary = ds.buff_defs[int(d.buff_def_id)]
		var max_stack := int(def.get("stack", {}).get("max_stack", 1))
		if max_stack <= 0:
			max_stack = 1
		stacks = min(stacks, max_stack)
		d.stacks = stacks

		# 操作后刷新 duration（remaining_turns 重置为 turns）
		var turns := int(def.get("duration", {}).get("turns", -1))
		d.remaining_turns = turns

		kept.append(d)

	target_buff.dots_by_target[target_eid] = kept

func _set_stat_final_from_event(l: OmniEventIndex.Listener, ctx: RefCounted) -> void:
	## 事件动作：将某 stat 的最终值设为指定值（通过调整 base 实现）
	## 依赖 ctx.meta["runtime"] 的 stats_by_entity
	if l.action_stat == "":
		return
	if not ctx.has_meta("runtime"):
		return
	var rt: Variant = ctx.get_meta("runtime")
	if typeof(rt) != TYPE_DICTIONARY:
		return
	var runtime: Dictionary = rt
	var stats_by_entity: Dictionary = runtime.get("stats_by_entity", {})
	var target_eid := _resolve_scope_entity_id(l.scope, ctx)
	if target_eid < 0:
		return
	var target_stats: OmniStatsComponent = stats_by_entity.get(target_eid, null)
	if target_stats == null:
		return
	var sid := ds.stat_id(l.action_stat)
	if sid < 0:
		return
	var desired := float(l.action_value)
	var cur := float(target_stats.get_final(sid))
	target_stats.add_base(sid, desired - cur)


func _set_shield_to_final_damage_from_event(l: OmniEventIndex.Listener, ctx: RefCounted) -> void:
	# 事件动作（Phase 1）：在 APPLY 阶段将 SHIELD 设置为本次 ctx.final_damage，用于“免疫=完全吸收”
	# - 不引入超大数值残留
	# - 依赖：ctx.final_damage 已在 RESOLVE 阶段计算完成
	if not ctx.has_meta("runtime"):
		return
	var runtime: Dictionary = ctx.get_meta("runtime")
	if runtime.is_empty():
		return
	var target_eid := _resolve_scope_entity_id(l.scope, ctx)
	if target_eid < 0:
		return
	var stats_by_entity: Dictionary = runtime.get("stats_by_entity", {})
	var target_stats: OmniStatsComponent = stats_by_entity.get(target_eid, null)
	if target_stats == null:
		return
	var sid := ds.stat_id("SHIELD")
	if sid < 0:
		return
	var desired := float(ctx.final_damage)
	var cur := float(target_stats.get_final(sid))
	target_stats.add_base(sid, desired - cur)


func _add_shield_from_event(l: OmniEventIndex.Listener, ctx: RefCounted) -> void:
	# 事件动作：对目标追加护盾（SHIELD += value）
	if not ctx.has_meta("runtime"):
		return
	var runtime: Dictionary = ctx.get_meta("runtime")
	var target_eid := _resolve_scope_entity_id(l.scope, ctx)
	if target_eid < 0:
		return
	var stats_by_entity: Dictionary = runtime.get("stats_by_entity", {})
	var target_stats: OmniStatsComponent = stats_by_entity.get(target_eid, null)
	if target_stats == null:
		return
	var sid := ds.stat_id("SHIELD")
	if sid < 0:
		return
	var v := float(l.action_value)
	if v <= 0.0:
		return
	target_stats.add_base(sid, v)


func _heal_from_event(l: OmniEventIndex.Listener, ctx: RefCounted) -> void:
	# 事件动作：对目标治疗（HP += value）
	if not ctx.has_meta("runtime"):
		return
	var runtime: Dictionary = ctx.get_meta("runtime")
	var target_eid := _resolve_scope_entity_id(l.scope, ctx)
	if target_eid < 0:
		return
	var stats_by_entity: Dictionary = runtime.get("stats_by_entity", {})
	var target_stats: OmniStatsComponent = stats_by_entity.get(target_eid, null)
	if target_stats == null:
		return
	var sid := ds.stat_id("HP")
	if sid < 0:
		return
	var v := float(l.action_value)
	if v <= 0.0:
		return
	target_stats.add_base(sid, v)


func _dispel_from_event(l: OmniEventIndex.Listener, ctx: RefCounted) -> void:
	# 事件动作：驱散（复用现有 dispel_by_*）
	if not ctx.has_meta("runtime"):
		return
	var runtime: Dictionary = ctx.get_meta("runtime")
	var target_eid := _resolve_scope_entity_id(l.scope, ctx)
	if target_eid < 0:
		return
	var stats_by_entity: Dictionary = runtime.get("stats_by_entity", {})
	var buff_by_entity: Dictionary = runtime.get("buff_by_entity", {})
	var target_stats: OmniStatsComponent = stats_by_entity.get(target_eid, null)
	var target_buffs: OmniBuffCore = buff_by_entity.get(target_eid, null)
	if target_stats == null or target_buffs == null:
		return

	var mode := String(l.action_dispel_mode).to_upper()
	var include_implicit := bool(l.action_include_implicit)
	match mode:
		"BY_TAG":
			if String(l.action_dispel_tag) != "":
				target_buffs.dispel_by_tag(target_stats, String(l.action_dispel_tag), include_implicit)
		"BY_SOURCE":
			var se := _resolve_scope_entity_id(String(l.action_dispel_source_scope), ctx)
			if se >= 0:
				target_buffs.dispel_by_source(target_stats, se, include_implicit)
		"BY_TYPE":
			if String(l.action_dispel_buff_type) != "":
				target_buffs.dispel_by_type(target_stats, String(l.action_dispel_buff_type))
		_:
			pass


func _lifesteal_from_event(l: OmniEventIndex.Listener, ctx: RefCounted) -> void:
	# 事件动作：吸血（heal = ctx.final_damage * ratio；建议 scope=SOURCE）
	if not ctx.has_meta("runtime"):
		return
	var runtime: Dictionary = ctx.get_meta("runtime")
	var target_eid := _resolve_scope_entity_id(l.scope, ctx)
	if target_eid < 0:
		return
	var stats_by_entity: Dictionary = runtime.get("stats_by_entity", {})
	var target_stats: OmniStatsComponent = stats_by_entity.get(target_eid, null)
	if target_stats == null:
		return
	var ratio: float = clampf(float(l.action_ratio), 0.0, 1.0)
	var heal: float = float(ctx.final_damage) * ratio
	if heal <= 0.0:
		return
	var sid := ds.stat_id("HP")
	if sid < 0:
		return
	target_stats.add_base(sid, heal)


func _reflect_damage_from_event(l: OmniEventIndex.Listener, ctx: RefCounted) -> void:
	# 事件动作：反伤（HP -= ctx.final_damage * ratio；不走 pipeline，避免递归）
	if not ctx.has_meta("runtime"):
		return
	var runtime: Dictionary = ctx.get_meta("runtime")
	var target_eid := _resolve_scope_entity_id(l.scope, ctx)
	if target_eid < 0:
		return
	var stats_by_entity: Dictionary = runtime.get("stats_by_entity", {})
	var target_stats: OmniStatsComponent = stats_by_entity.get(target_eid, null)
	if target_stats == null:
		return
	var ratio: float = clampf(float(l.action_ratio), 0.0, 1.0)
	var dmg: float = float(ctx.final_damage) * ratio
	if dmg <= 0.0:
		return
	var sid := ds.stat_id("HP")
	if sid < 0:
		return
	target_stats.add_base(sid, -dmg)

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
