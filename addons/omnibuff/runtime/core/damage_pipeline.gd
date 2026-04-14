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

func deal_damage(attacker: OmniStatsComponent, defender: OmniStatsComponent, buff_attacker: OmniBuffCore, buff_defender: OmniBuffCore, ds: OmniCompiledDataset, base_damage: float) -> DamageContext:
	## 固定阶段 DamagePipeline 骨架（最小可用版）
	##
	## 性能约束：
	## - 读取属性只允许通过 StatsComponent.get_final（StatCache）
	## - 事件响应只允许通过 BuffCore.emit_event（EventIndex 子集遍历）
	var ctx := DamageContext.new()
	ctx.attacker_id = attacker.entity_id
	ctx.defender_id = defender.entity_id
	ctx.base_damage = base_damage
	# 默认无tag；调用方（例如DOT tick）可在创建后覆盖
	ctx.tags_mask = 0

	# === build ===
	buff_attacker.emit_event("DAMAGE", "BUILD", ctx)

	# === before_deal（攻击方）===
	buff_attacker.emit_event("DAMAGE", "BEFORE_DEAL", ctx)

	# === before_take（防守方）===
	buff_defender.emit_event("DAMAGE", "BEFORE_TAKE", ctx)

	# === resolve（命中/暴击/公式）===
	# 注意：这里读取 ATK/DEF 只走 StatCache，不遍历buff列表
	var atk := attacker.get_final(ds.stat_id("ATK"))
	var def := defender.get_final(ds.stat_id("DEF"))
	ctx.final_damage = max(0.0, ctx.base_damage + atk - def)

	# === apply（护盾/扣血）===
	buff_attacker.emit_event("DAMAGE", "APPLY", ctx)
	buff_defender.emit_event("DAMAGE", "APPLY", ctx)
	defender.add_base(ds.stat_id("HP"), -ctx.final_damage)

	# === after_deal / after_take ===
	buff_attacker.emit_event("DAMAGE", "AFTER_DEAL", ctx)
	buff_defender.emit_event("DAMAGE", "AFTER_TAKE", ctx)
	return ctx

func deal_damage_with_tags(attacker: OmniStatsComponent, defender: OmniStatsComponent, buff_attacker: OmniBuffCore, buff_defender: OmniBuffCore, ds: OmniCompiledDataset, base_damage: float, tags_mask: int) -> DamageContext:
	## 与 deal_damage 相同，但允许外部指定 ctx.tags_mask（用于 filters 与追帧）
	##
	## 注意：tags_mask 必须在 BUILD/BEFORE_DEAL/BEFORE_TAKE 阶段之前写入，
	## 否则 filters.tag_mask_any 在事件触发时将无法命中。
	var ctx := DamageContext.new()
	ctx.attacker_id = attacker.entity_id
	ctx.defender_id = defender.entity_id
	ctx.base_damage = base_damage
	ctx.tags_mask = tags_mask

	# === build ===
	buff_attacker.emit_event("DAMAGE", "BUILD", ctx)

	# === before_deal（攻击方）===
	buff_attacker.emit_event("DAMAGE", "BEFORE_DEAL", ctx)

	# === before_take（防守方）===
	buff_defender.emit_event("DAMAGE", "BEFORE_TAKE", ctx)

	# === resolve（命中/暴击/公式）===
	var atk := attacker.get_final(ds.stat_id("ATK"))
	var def := defender.get_final(ds.stat_id("DEF"))
	ctx.final_damage = max(0.0, ctx.base_damage + atk - def)

	# === apply（护盾/扣血）===
	buff_attacker.emit_event("DAMAGE", "APPLY", ctx)
	buff_defender.emit_event("DAMAGE", "APPLY", ctx)
	defender.add_base(ds.stat_id("HP"), -ctx.final_damage)

	# === after_deal / after_take ===
	buff_attacker.emit_event("DAMAGE", "AFTER_DEAL", ctx)
	buff_defender.emit_event("DAMAGE", "AFTER_TAKE", ctx)
	return ctx
