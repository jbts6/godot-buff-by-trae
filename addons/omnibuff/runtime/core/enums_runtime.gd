class_name OmniEnumsRuntime
extends RefCounted

var enum_tables: Dictionary = {} # name -> {str:int}
var tag_code_by_id: Dictionary = {} # tag_id -> int (bit index)
var tag_mask_by_id: Dictionary = {} # tag_id -> int mask (1<<code)

static func from_enums_json(enums_obj: Dictionary) -> OmniEnumsRuntime:
	var rt := OmniEnumsRuntime.new()

	var enums := enums_obj.get("enums", {})
	for k in enums.keys():
		var arr: Array = enums[k]
		var map := {}
		for i in range(arr.size()):
			map[String(arr[i])] = i
		rt.enum_tables[k] = map

	var tags: Array = enums_obj.get("tags", [])
	for t in tags:
		var id := String(t.get("id", ""))
		var code := int(t.get("code", -1))
		rt.tag_code_by_id[id] = code
		rt.tag_mask_by_id[id] = (1 << code)

	return rt

func enum_int(enum_name: String, value: String) -> int:
	var m: Dictionary = enum_tables.get(enum_name, {})
	return int(m.get(value, -1))

func enum_count(enum_name: String) -> int:
	var m: Dictionary = enum_tables.get(enum_name, {})
	return m.size()

func tag_mask(tags: Array) -> int:
	var m := 0
	for t in tags:
		m |= int(tag_mask_by_id.get(String(t), 0))
	return m
