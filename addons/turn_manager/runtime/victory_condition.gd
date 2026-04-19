class_name VictoryCondition
extends RefCounted

var ally_camp: String = "ally"
var enemy_camp: String = "enemy"

func _init(p_ally_camp: String = "ally", p_enemy_camp: String = "enemy") -> void:
	ally_camp = p_ally_camp
	enemy_camp = p_enemy_camp

func check(units: Array[Node], turn_manager: Node) -> Dictionary:
	var ally_alive = 0
	var enemy_alive = 0
	
	for unit in units:
		if not is_instance_valid(unit) or turn_manager.is_dead(unit):
			continue
		
		if unit.get("camp") == ally_camp:
			ally_alive += 1
		elif unit.get("camp") == enemy_camp:
			enemy_alive += 1
	
	if ally_alive == 0 and enemy_alive == 0:
		return {"ended": true, "winner": "draw", "reason": "all_dead"}
	elif ally_alive == 0:
		return {"ended": true, "winner": enemy_camp, "reason": "ally_wiped_out"}
	elif enemy_alive == 0:
		return {"ended": true, "winner": ally_camp, "reason": "enemy_wiped_out"}
	
	return {"ended": false, "winner": "", "reason": ""}
