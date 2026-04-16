class_name OmniDamagePipeline
extends RefCounted

class DamageContext:
	extends RefCounted
	## 攻击者实体ID（用于追帧/事件过滤；逻辑中不依赖场景树）
	var attacker_id: int
	## 防守者实体ID
	var defender_id: int
	## 技能ID（编译后 int 索引；当前 demo 未用，先占位）
	var skill_id: int
	## 伤害类型（物理/魔法/真实等；当前 demo 未用，先占位）
	var damage_type: int
	## 元素类型（火/冰/雷等；当前 demo 未用，先占位）
	var element: int
	## 事件Tag（bitmask），用于 EventIndex filters（例如 DOT/FIRE 等）
	var tags_mask: int
	## 是否命中（当前 demo 未实现命中判定，先默认 true）
	var hit: bool = true
	## 是否暴击（当前 demo 未实现暴击判定，先默认 false）
	var crit: bool = false
	## 基础伤害（会被 BEFORE_DEAL 等阶段的事件修改）
	var base_damage: float = 0.0
	## 最终伤害（resolve后得到，apply阶段用于扣血/护盾）
	var final_damage: float = 0.0

const _U32_MASK := 0xFFFFFFFF
const _HIT_SALT := 0xA1B2C3D4
const _CRIT_SALT := 0xC3D4E5F6

static func _xorshift32(x: int) -> int:
	# 32-bit xorshift（确定性；跨平台一致性依赖显式 &0xFFFFFFFF）
	x = int(x) & _U32_MASK
	x = int(x ^ ((x << 13) & _U32_MASK)) & _U32_MASK
	x = int(x ^ ((x >> 17) & _U32_MASK)) & _U32_MASK
	x = int(x ^ ((x << 5) & _U32_MASK)) & _U32_MASK
	return x & _U32_MASK

static func _make_seed(turn_index: int, roll_key: int, attacker_id: int, defender_id: int, salt: int) -> int:
	# 将 turn_index / roll_key / attacker_id / defender_id 组合成一个 32-bit seed，并用 salt 扰动
	# 注意：避免 seed=0（xorshift32(0)=0，导致 roll 恒为0）
	var x := 0x9E3779B9
	x = int((x + (turn_index * 1103515245)) & _U32_MASK)
	x = int((x ^ (roll_key * 2246822519)) & _U32_MASK)
	x = int((x ^ (attacker_id * 2654435761)) & _U32_MASK)
	x = int((x + (defender_id * 374761393)) & _U32_MASK)
	x = int((x ^ salt) & _U32_MASK)
	if x == 0:
		x = 1
	return x

static func _roll01(turn_index: int, roll_key: int, attacker_id: int, defender_id: int, salt: int) -> float:
	var seed := _make_seed(turn_index, roll_key, attacker_id, defender_id, salt)
	var u := _xorshift32(seed)
	# [0, 1)（除以 2^32）
	return float(u) / 4294967296.0

func deal_damage(attacker: OmniStatsComponent, defender: OmniStatsComponent, buff_attacker: OmniBuffCore, buff_defender: OmniBuffCore, ds: OmniCompiledDataset, base_damage: float, replay: RefCounted = null, turn_index: int = 0, tags_mask: int = 0, runtime: Dictionary = {}, roll_key: int = 0, skill_id: int = -1, damage_type: int = 0, element: int = 0, is_bonus_damage: bool = false) -> DamageContext:
	## 固定阶段 DamagePipeline 骨架（最小可用版）
	##
	## 性能约束：
	## - 读取属性只允许通过 StatsComponent.get_final（StatCache）
	## - 事件响应只允许通过 BuffCore.emit_event（EventIndex 子集遍历）
	## PERF(J2)：禁止遍历全实体 keys（例如 runtime.stats_by_entity.keys()/buff_by_entity.keys()），
	## 事件只允许遍历 listeners 子集；DOT 只允许结算“当前 target 的 DOT 池”（由 BuffCore._tick_dots 驱动）。
	var ctx := DamageContext.new()
	ctx.attacker_id = attacker.entity_id
	ctx.defender_id = defender.entity_id
	ctx.skill_id = skill_id
	ctx.damage_type = damage_type
	ctx.element = element
	ctx.base_damage = base_damage
	# tags_mask 必须在事件触发前写入，供 filters 使用
	ctx.tags_mask = tags_mask
	# 通过 meta 传递运行时信息，避免对 DamageContext 增加强耦合字段
	ctx.set_meta("turn_index", turn_index)
	ctx.set_meta("runtime", runtime)
	ctx.set_meta("roll_key", roll_key)
	ctx.set_meta("is_bonus_damage", is_bonus_damage)

	# === precompute（命中/暴击）===
	# 目的：让 BEFORE_DEAL / BEFORE_TAKE 等早期阶段也能使用 filters.require_hit / require_crit 等条件。
	# 注意：这里仅确定 hit/crit 布尔值；最终伤害仍在 resolve 阶段根据（可能已被修改的）ctx.base_damage 重新计算。
	var hit_id := ds.stat_id("HIT_RATE")
	var evade_id := ds.stat_id("EVADE")
	if hit_id < 0 and evade_id < 0:
		ctx.hit = true
		ctx.crit = false
	else:
		# 命中判定
		var hit_rate := 1.0
		var evade := 0.0
		if hit_id >= 0:
			hit_rate = float(attacker.get_final(hit_id))
		if evade_id >= 0:
			evade = float(defender.get_final(evade_id))
		var hit_chance := clamp(hit_rate - evade, 0.0, 1.0)
		var hit_roll := _roll01(turn_index, roll_key, ctx.attacker_id, ctx.defender_id, _HIT_SALT)
		if hit_roll >= hit_chance:
			ctx.hit = false
			ctx.crit = false
		else:
			ctx.hit = true
			# 暴击判定
			var crit_rate := 0.0
			var crit_rate_id := ds.stat_id("CRIT_RATE")
			if crit_rate_id >= 0:
				crit_rate = float(attacker.get_final(crit_rate_id))
			var crit_roll := _roll01(turn_index, roll_key, ctx.attacker_id, ctx.defender_id, _CRIT_SALT)
			ctx.crit = (crit_roll < crit_rate)

	# 追帧：收集每个阶段命中的 inst_id 列表（稳定顺序：按阶段追加）
	var stage_triggers: Dictionary = {}
	var triggered_all := PackedInt32Array()

	# === build ===
	buff_attacker.emit_event("DAMAGE", "BUILD", ctx)
	if replay != null and replay.has_method("trace_damage"):
		var a := buff_attacker.get_triggered_inst_ids_last_emit()
		stage_triggers["BUILD"] = a.duplicate()
		for x in a:
			triggered_all.append(x)

	# === before_deal（攻击方）===
	buff_attacker.emit_event("DAMAGE", "BEFORE_DEAL", ctx)
	if replay != null and replay.has_method("trace_damage"):
		var b := buff_attacker.get_triggered_inst_ids_last_emit()
		stage_triggers["BEFORE_DEAL"] = b.duplicate()
		for x in b:
			triggered_all.append(x)

	# === before_take（防守方）===
	buff_defender.emit_event("DAMAGE", "BEFORE_TAKE", ctx)
	if replay != null and replay.has_method("trace_damage"):
		var c := buff_defender.get_triggered_inst_ids_last_emit()
		stage_triggers["BEFORE_TAKE"] = c.duplicate()
		for x in c:
			triggered_all.append(x)

	# === resolve（命中/暴击/公式）===
	# 注意：这里读取 ATK/DEF 只走 StatCache，不遍历buff列表
	var atk := attacker.get_final(ds.stat_id("ATK"))
	var def := defender.get_final(ds.stat_id("DEF"))
	var raw := max(0.0, ctx.base_damage + atk - def)

	# 兼容旧数据集（base_demo）：
	# - 若数据集中不包含 HIT_RATE/EVADE，则视为“未启用命中/暴击系统”
	# - 这样不会因为未来预留的 CRIT_RATE/CRIT_DMG 出现在 stat_defs 就改变旧用例的期望数值
	if hit_id < 0 and evade_id < 0:
		ctx.hit = true
		ctx.crit = false
		ctx.final_damage = raw
	else:
		if not ctx.hit:
			ctx.final_damage = 0.0
		else:
			ctx.final_damage = raw
			# 暴击倍伤（crit 布尔值在 precompute 中已确定）
			if ctx.crit:
				var crit_dmg := 0.0
				var crit_dmg_id := ds.stat_id("CRIT_DMG")
				if crit_dmg_id >= 0:
					crit_dmg = float(attacker.get_final(crit_dmg_id))
				ctx.final_damage = ctx.final_damage * (1.0 + crit_dmg)

	# === defender damage reduction（减伤）===
	# 约定：DMG_REDUCE 表示“受到伤害减少比例”，在 resolve 后、APPLY（护盾/扣血）前生效。
	# clamp 0..0.95（避免出现 100% 免伤导致后续数值/追帧边界问题）
	var reduce_id := ds.stat_id("DMG_REDUCE")
	if reduce_id >= 0:
		var r := clamp(float(defender.get_final(reduce_id)), 0.0, 0.95)
		if r > 0.0 and ctx.final_damage > 0.0:
			ctx.set_meta("dmg_reduce_ratio", r)
			ctx.final_damage = ctx.final_damage * (1.0 - r)

	# === apply（护盾/扣血）===
	buff_attacker.emit_event("DAMAGE", "APPLY", ctx)
	buff_defender.emit_event("DAMAGE", "APPLY", ctx)
	if replay != null and replay.has_method("trace_damage"):
		var d1 := buff_attacker.get_triggered_inst_ids_last_emit()
		var d2 := buff_defender.get_triggered_inst_ids_last_emit()
		stage_triggers["APPLY_ATK"] = d1.duplicate()
		stage_triggers["APPLY_DEF"] = d2.duplicate()
		for x in d1:
			triggered_all.append(x)
		for x in d2:
			triggered_all.append(x)

	# 先消耗护盾（SHIELD），再扣 HP
	var remaining := float(ctx.final_damage)
	var shield_id := ds.stat_id("SHIELD")
	if shield_id >= 0 and remaining > 0.0:
		var shield := float(defender.get_final(shield_id))
		if shield > 0.0:
			var absorbed := min(shield, remaining)
			# 通过减少 base 值来消耗护盾：
			# - 即使护盾来自 modifier（例如 +50），base 也可以被扣到负数，
			#   最终护盾值依然会按 base+modifiers 计算并正确下降到 0。
			# - 这样避免在这里反推公式/访问 modifier 细节，保持实现简单稳定。
			defender.add_base(shield_id, -absorbed)
			remaining -= absorbed
			# ctx.final_damage 语义：用于扣血/回放/后续阶段，应为“吸收后剩余伤害”
			ctx.set_meta("absorbed_shield", absorbed)

	ctx.final_damage = remaining
	defender.add_base(ds.stat_id("HP"), -remaining)

	# === after_deal / after_take ===
	buff_attacker.emit_event("DAMAGE", "AFTER_DEAL", ctx)
	buff_defender.emit_event("DAMAGE", "AFTER_TAKE", ctx)
	if replay != null and replay.has_method("trace_damage"):
		var e1 := buff_attacker.get_triggered_inst_ids_last_emit()
		var e2 := buff_defender.get_triggered_inst_ids_last_emit()
		stage_triggers["AFTER_DEAL"] = e1.duplicate()
		stage_triggers["AFTER_TAKE"] = e2.duplicate()
		for x in e1:
			triggered_all.append(x)
		for x in e2:
			triggered_all.append(x)

		replay.trace_damage(turn_index, ctx, triggered_all, stage_triggers)
	return ctx

func deal_damage_with_tags(attacker: OmniStatsComponent, defender: OmniStatsComponent, buff_attacker: OmniBuffCore, buff_defender: OmniBuffCore, ds: OmniCompiledDataset, base_damage: float, tags_mask: int, replay: RefCounted = null, turn_index: int = 0, skill_id: int = -1, damage_type: int = 0, element: int = 0) -> DamageContext:
	## 与 deal_damage 相同，但允许外部指定 ctx.tags_mask（用于 filters 与追帧）
	##
	## 注意：tags_mask 必须在 BUILD/BEFORE_DEAL/BEFORE_TAKE 阶段之前写入，
	## 否则 filters.tag_mask_any 在事件触发时将无法命中。
	# 复用主流程：把 tags_mask 作为参数传入，确保在 BUILD 之前就可用于 filters
	return deal_damage(attacker, defender, buff_attacker, buff_defender, ds, base_damage, replay, turn_index, tags_mask, {}, 0, skill_id, damage_type, element)
