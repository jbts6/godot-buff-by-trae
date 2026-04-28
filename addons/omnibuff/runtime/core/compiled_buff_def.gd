extends RefCounted

class EffectCompiled:
	extends RefCounted
	var stat_int: int = -1
	var op_int: int = 0
	var op_str: String = ""
	var phase_int: int = 0
	var phase_str: String = ""
	var value: float = 0.0
	var layer: int = 0
	var priority: int = 0

class FilterCompiled:
	extends RefCounted
	var tag_mask: int = 0
	var require_hit: bool = false
	var require_crit: bool = false
	var skill_id: int = -1
	var damage_type_mask: int = 0
	var element_mask: int = 0
	var require_shield_absorbed: bool = false
	var min_absorbed_shield: float = 0.0
	var min_final_damage: float = 0.0
	var require_not_bonus_damage: bool = false
	var command_kind_mask: int = 0
	var item_id: int = -1
	var actor_id: int = -1
	var source_id: int = -1
	var stat_threshold_scope: String = ""
	var stat_threshold_stat_int: int = -1
	var stat_threshold_op: String = ""
	var stat_threshold_value: float = 0.0

class ActionCompiled:
	extends RefCounted
	var kind_int: int = 0
	var value: float = 0.0
	var ratio: float = 0.0
	var buff_def_id: int = -1
	var add_stacks: int = 1
	var chance: float = 1.0
	var stat_int: int = -1
	var dispel_mode_int: int = 0
	var dispel_tag_mask: int = 0
	var dispel_buff_type_int: int = 0
	var dispel_source_scope: String = ""
	var include_implicit: bool = false
	var dot_buff_def_id: int = -1
	var dot_tag_mask: int = 0
	var bonus_tags_mask: int = 0
	var bonus_scope: String = "TARGET"
	var bonus_min_damage: float = 0.0
	var bonus_max_damage: float = 0.0
	var bonus_round_mode: String = ""
	var expr: String = ""
	var delta: int = 0
	var min_stack: int = 0
	var max_stack: int = 0

class TriggerCompiled:
	extends RefCounted
	var event_type_int: int = -1
	var event_phase_int: int = -1
	var scope_str: String = "SELF"
	var filters: RefCounted = null
	var action: RefCounted = null

class ConditionCompiled:
	extends RefCounted
	var type_int: int = 0
	var stat_int: int = -1
	var op: String = "LE"
	var value: float = 0.0
	var set_id: String = ""
	var count: int = 0
	var tag_mask: int = 0

class DotCompiled:
	extends RefCounted
	var tick_phase_int: int = 0
	var element_int: int = 0
	var base_ratio: float = 0.0
	var read_source_stat_int: int = 0

class BuffDefCompiled:
	extends RefCounted
	var buff_id_str: String = ""
	var buff_type_int: int = 0
	var tag_mask: int = 0
	var duration_type_int: int = 0
	var duration_turns: int = -1
	var tick_phase_int: int = 0
	var stack_mode_int: int = 0
	var stack_max: int = 1
	var ownership_mode_int: int = 0
	var refresh_policy_int: int = 0
	var undispellable: bool = false
	var effects: Array = []
	var triggers: Array = []
	var conditions: Array = []
	var dot: RefCounted = null
