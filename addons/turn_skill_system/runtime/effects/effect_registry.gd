extends RefCounted
class_name EffectRegistry

const DamageEffect := preload("res://addons/turn_skill_system/runtime/effects/damage_effect.gd")
const ApplyBuffEffect := preload("res://addons/turn_skill_system/runtime/effects/apply_buff_effect.gd")
const RemoveBuffEffect := preload("res://addons/turn_skill_system/runtime/effects/remove_buff_effect.gd")
const HealEffect := preload("res://addons/turn_skill_system/runtime/effects/heal_effect.gd")

var _handlers: Dictionary = {} # kind -> handler

func register_defaults() -> void:
	_handlers["damage"] = DamageEffect.new()
	_handlers["apply_buff"] = ApplyBuffEffect.new()
	_handlers["remove_buff"] = RemoveBuffEffect.new()
	_handlers["heal"] = HealEffect.new()

func apply_effect(effect: Dictionary, ctx: Dictionary, simulation: bool) -> Dictionary:
	var kind := String(effect.get("kind", ""))
	if kind == "" or not _handlers.has(kind):
		return {"ok": false, "error": "unknown_effect_kind:%s" % kind}
	return _handlers[kind].apply(effect, ctx, simulation)

