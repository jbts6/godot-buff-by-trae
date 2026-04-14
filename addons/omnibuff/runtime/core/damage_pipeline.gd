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

func deal_damage(attacker: OmniStatsComponent, defender: OmniStatsComponent, ds: OmniCompiledDataset, base_damage: float) -> DamageContext:
	var ctx := DamageContext.new()
	ctx.attacker_id = attacker.entity_id
	ctx.defender_id = defender.entity_id
	ctx.base_damage = base_damage

	# build
	# before_deal (reserved)
	# before_take (reserved)

	# resolve
	var atk := attacker.get_final(ds.stat_id("ATK"))
	var def := defender.get_final(ds.stat_id("DEF"))
	ctx.final_damage = max(0.0, base_damage + atk - def)

	# apply
	defender.add_base(ds.stat_id("HP"), -ctx.final_damage)

	# after_deal / after_take (reserved)
	return ctx
