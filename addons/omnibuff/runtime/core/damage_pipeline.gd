class_name OmniDamagePipeline
extends RefCounted

class DamageContext:
	extends RefCounted
	var attacker_id: int
	var defender_id: int
	var skill_id: int
	var damage_type: int
	var element: int
	var tags_mask: int
	var hit: bool = true
	var crit: bool = false
	var base_damage: float = 0.0
	var final_damage: float = 0.0

func deal_damage(attacker: OmniStatsComponent, defender: OmniStatsComponent, buff_attacker: OmniBuffCore, buff_defender: OmniBuffCore, ds: OmniCompiledDataset, base_damage: float) -> DamageContext:
	var ctx := DamageContext.new()
	ctx.attacker_id = attacker.entity_id
	ctx.defender_id = defender.entity_id
	ctx.base_damage = base_damage
	ctx.tags_mask = 0

	# build
	buff_attacker.emit_event("DAMAGE", "BUILD", ctx)

	# before_deal
	buff_attacker.emit_event("DAMAGE", "BEFORE_DEAL", ctx)

	# before_take
	buff_defender.emit_event("DAMAGE", "BEFORE_TAKE", ctx)

	# resolve
	var atk := attacker.get_final(ds.stat_id("ATK"))
	var def := defender.get_final(ds.stat_id("DEF"))
	ctx.final_damage = max(0.0, ctx.base_damage + atk - def)

	# apply
	buff_attacker.emit_event("DAMAGE", "APPLY", ctx)
	buff_defender.emit_event("DAMAGE", "APPLY", ctx)
	defender.add_base(ds.stat_id("HP"), -ctx.final_damage)

	# after_deal / after_take (reserved)
	buff_attacker.emit_event("DAMAGE", "AFTER_DEAL", ctx)
	buff_defender.emit_event("DAMAGE", "AFTER_TAKE", ctx)
	return ctx
