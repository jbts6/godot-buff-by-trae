class_name OmniBattleExecutor
extends RefCounted

## 回合制 BattleExecutor（最小可用版）
##
## 职责：
## - 执行 OmniCommandContext（ATTACK/CAST_SKILL/USE_ITEM/DEFEND/ESCAPE）
## - 在执行前后触发 COMMAND 事件（允许 CANCEL_COMMAND 等干预）
## - 对攻击/技能通过 DamagePipeline 走 DAMAGE 事件链

class ExecuteResult:
	extends RefCounted
	var canceled: bool = false
	var escaped: bool = false
	var last_damage_ctx: RefCounted = null


func execute_command(
	turn_index: int,
	ctx: RefCounted,
	runtime: Dictionary,
	ds: OmniCompiledDataset,
	enums_rt: OmniEnumsRuntime,
	pipeline: OmniDamagePipeline,
	sources: Dictionary,
	replay: RefCounted = null
) -> ExecuteResult:
	var res := ExecuteResult.new()
	if ctx == null:
		res.canceled = true
		return res
	if runtime.is_empty():
		res.canceled = true
		return res

	# runtime 约定：{stats_by_entity, buff_by_entity}
	var stats_by_entity: Dictionary = runtime.get("stats_by_entity", {})
	var buff_by_entity: Dictionary = runtime.get("buff_by_entity", {})

	var actor_id_v: Variant = ctx.get("actor_id")
	var actor_id := -1
	if actor_id_v != null:
		actor_id = int(actor_id_v)
	if actor_id < 0:
		res.canceled = true
		return res

	var actor_stats: OmniStatsComponent = stats_by_entity.get(actor_id, null)
	var actor_buffs: OmniBuffCore = buff_by_entity.get(actor_id, null)
	if actor_stats == null or actor_buffs == null:
		res.canceled = true
		return res

	# 给 BuffCore actions 提供 runtime 入口
	var runtime2 := {
		"stats_by_entity": stats_by_entity,
		"buff_by_entity": buff_by_entity,
		"pipeline": pipeline,
		"ds": ds,
		"enums_rt": enums_rt,
		"turn_index": turn_index,
		"replay": replay
	}
	ctx.set_meta("runtime", runtime2)

	# === COMMAND/CMD_BEFORE ===
	actor_buffs.emit_event("COMMAND", "CMD_BEFORE", ctx)
	var cancel_v: Variant = ctx.get("cancel")
	if cancel_v != null and bool(cancel_v):
		res.canceled = true
		return res

	var kind := String(ctx.get("command_kind")).to_upper()
	match kind:
		"ATTACK", "CAST_SKILL":
			_execute_skill(turn_index, ctx, actor_id, actor_stats, actor_buffs, stats_by_entity, buff_by_entity, ds, enums_rt, pipeline, sources, replay, res)
		"USE_ITEM":
			_execute_item(ctx, actor_id, actor_stats, actor_buffs, stats_by_entity, ds)
		"DEFEND":
			# 最小：挂一个 1 回合防御 buff
			actor_buffs.apply_buff(actor_stats, "buff_defend_1t", actor_id)
		"ESCAPE":
			res.escaped = true
		_:
			# 未知指令：视为 no-op（不 cancel）
			pass

	# === COMMAND/CMD_AFTER（仅在未 cancel 时触发）===
	actor_buffs.emit_event("COMMAND", "CMD_AFTER", ctx)
	return res


func _execute_item(ctx: RefCounted, actor_id: int, actor_stats: OmniStatsComponent, actor_buffs: OmniBuffCore, stats_by_entity: Dictionary, ds: OmniCompiledDataset) -> void:
	var item_id_v: Variant = ctx.get("item_id")
	var item_id := -1
	if item_id_v != null:
		item_id = int(item_id_v)

	# 默认目标：SELF；若提供 targets[0] 则为 targets[0]
	var target_id := actor_id
	var tv: Variant = ctx.get("targets")
	if tv != null and typeof(tv) == TYPE_PACKED_INT32_ARRAY:
		var t: PackedInt32Array = tv
		if t.size() > 0:
			target_id = int(t[0])

	var target_stats: OmniStatsComponent = stats_by_entity.get(target_id, null)
	if target_stats == null:
		return

	if item_id == 2001:
		# 小治疗
		var hp_id := ds.stat_id("HP")
		if hp_id >= 0:
			target_stats.add_base(hp_id, 30.0)
	elif item_id == 2002:
		# 小护盾
		var shield_id := ds.stat_id("SHIELD")
		if shield_id >= 0:
			target_stats.add_base(shield_id, 50.0)
	else:
		pass


func _execute_skill(
	turn_index: int,
	ctx: RefCounted,
	actor_id: int,
	actor_stats: OmniStatsComponent,
	actor_buffs: OmniBuffCore,
	stats_by_entity: Dictionary,
	buff_by_entity: Dictionary,
	ds: OmniCompiledDataset,
	enums_rt: OmniEnumsRuntime,
	pipeline: OmniDamagePipeline,
	sources: Dictionary,
	replay: RefCounted,
	out_res: ExecuteResult
) -> void:
	var tv: Variant = ctx.get("targets")
	if tv == null or typeof(tv) != TYPE_PACKED_INT32_ARRAY:
		return
	var targets: PackedInt32Array = tv
	if targets.is_empty():
		return

	# 最小实现：skill_id 作为 skill_defs.skills 的索引
	var skill_idx_v: Variant = ctx.get("skill_id")
	var skill_idx := -1
	if skill_idx_v != null:
		skill_idx = int(skill_idx_v)

	var skill_id_str := ""
	var tags: Array = []
	var base_damage := 10.0
	var hit_count := 1
	var hit_base_damage: Array = []
	var targeting := "FIRST"
	var dmg_type := 0
	var element := 0

	var skills: Array = sources.get("skill_defs", {}).get("skills", [])
	if skill_idx >= 0 and skill_idx < skills.size():
		var skill: Dictionary = skills[skill_idx]
		skill_id_str = String(skill.get("id", ""))
		tags = skill.get("tags", [])
		if skill.has("base_damage"):
			base_damage = float(skill.get("base_damage", 10.0))
		if skill.has("hit_count"):
			hit_count = int(skill.get("hit_count", 1))
		if skill.has("hit_base_damage"):
			hit_base_damage = skill.get("hit_base_damage", [])
		if skill.has("targeting"):
			targeting = String(skill.get("targeting", "FIRST")).to_upper()
		var dt_str := String(skill.get("damage_type", "PHYSICAL"))
		var el_str := String(skill.get("element", "NONE"))
		dmg_type = int(enums_rt.enum_int("damage_type", dt_str))
		element = int(enums_rt.enum_int("element", el_str))

	# tags_mask：供 COMMAND 与 DAMAGE filters 使用（例如 BASIC_ATTACK）
	var tags_mask := int(enums_rt.tag_mask(tags))
	ctx.set("tags_mask", tags_mask)

	# 回放：最小仅记录“cast skill”
	if replay != null and replay.has_method("record_cast_skill"):
		replay.record_cast_skill(turn_index, actor_id, skill_id_str, targets, 0)

	if hit_count < 1:
		hit_count = 1

	# 目标列表：FIRST = targets[0]；ALL = targets 全部（稳定排序）
	var targets_sorted := PackedInt32Array()
	if targeting == "ALL":
		targets_sorted = targets.duplicate()
		targets_sorted.sort()
	else:
		targets_sorted = PackedInt32Array([int(targets[0])])

	var roll_key := 0
	for tid in targets_sorted:
		var target_id := int(tid)
		var target_stats: OmniStatsComponent = stats_by_entity.get(target_id, null)
		var target_buffs: OmniBuffCore = buff_by_entity.get(target_id, null)
		if target_stats == null or target_buffs == null:
			continue

		for hi in range(hit_count):
			var bd := base_damage
			if not hit_base_damage.is_empty():
				if hit_base_damage.size() == 1:
					bd = float(hit_base_damage[0])
				elif hi < hit_base_damage.size():
					bd = float(hit_base_damage[hi])

			var dmg_ctx = pipeline.deal_damage(
				actor_stats,
				target_stats,
				actor_buffs,
				target_buffs,
				ds,
				bd,
				replay,
				turn_index,
				tags_mask,
				{"stats_by_entity": stats_by_entity, "buff_by_entity": buff_by_entity},
				roll_key,
				skill_idx,
				dmg_type,
				element
			)
			out_res.last_damage_ctx = dmg_ctx
			roll_key += 1
