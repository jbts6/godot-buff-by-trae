class_name OmniCompiledDataset
extends RefCounted

var fingerprint: String = ""

var stat_id_to_int: Dictionary = {}
var stat_defs: Array[Dictionary] = []

var buff_id_to_int: Dictionary = {}
var buff_defs: Array[Dictionary] = []
var buff_defs_compiled: Array = []

var skill_id_to_int: Dictionary = {}
var skill_defs: Array[Dictionary] = []

var equipment_id_to_int: Dictionary = {}
var equipment_defs: Array[Dictionary] = []

var set_bonus_defs: Array[Dictionary] = []

var pipeline_stages: Array[Dictionary] = []

var derived_defs_by_stat: Array[Dictionary] = []
var derived_inputs_by_stat: Array = []
var derived_dependents_by_stat: Array = []
var derived_topo_order: PackedInt32Array = PackedInt32Array()
var derived_from_int: PackedInt32Array = PackedInt32Array()
var derived_ratio: PackedFloat32Array = PackedFloat32Array()

func stat_id(id_str: String) -> int:
	return int(stat_id_to_int.get(id_str, -1))

func buff_id(id_str: String) -> int:
	return int(buff_id_to_int.get(id_str, -1))

func skill_id(id_str: String) -> int:
	return int(skill_id_to_int.get(id_str, -1))

func equipment_id(id_str: String) -> int:
	return int(equipment_id_to_int.get(id_str, -1))
