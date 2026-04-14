class_name OmniCompiledDataset
extends RefCounted

var fingerprint: String = ""

var stat_id_to_int: Dictionary = {}
var stat_defs: Array[Dictionary] = []

var buff_id_to_int: Dictionary = {}
var buff_defs: Array[Dictionary] = []

func stat_id(id_str: String) -> int:
	return int(stat_id_to_int.get(id_str, -1))

func buff_id(id_str: String) -> int:
	return int(buff_id_to_int.get(id_str, -1))

