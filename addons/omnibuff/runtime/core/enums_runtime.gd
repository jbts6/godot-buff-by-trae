class_name OmniEnumsRuntime
extends RefCounted

## enums.json 的运行时映射（Schema治理关键）
##
## 配置层使用字符串枚举/Tag（便于MOD可读），运行时核心只使用 int/bitmask（性能与一致性）
##
## 注意：
## - 核心枚举集合视为“插件契约”，默认不允许 mod 新增（仅允许新增 tags）
## - tags.code 只增不复用（发布后不可复用旧码语义）

## 枚举表：enum_name -> { "VALUE_STR": int_code }
var enum_tables: Dictionary = {}

## Tag编码：tag_id -> int_code（bit index）
var tag_code_by_id: Dictionary = {}

## Tag位掩码：tag_id -> (1<<code)
var tag_mask_by_id: Dictionary = {}

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
	# 将字符串枚举映射为 int code；找不到返回 -1（交给校验器在加载期处理）
	var m: Dictionary = enum_tables.get(enum_name, {})
	return int(m.get(value, -1))

func enum_count(enum_name: String) -> int:
	# 返回某枚举集合的大小（用于分配 EventIndex 等结构）
	var m: Dictionary = enum_tables.get(enum_name, {})
	return m.size()

func tag_mask(tags: Array) -> int:
	# 将 tags:["DOT","FIRE"] 映射为 bitmask；未知tag返回0位（加载期应校验）
	var m := 0
	for t in tags:
		m |= int(tag_mask_by_id.get(String(t), 0))
	return m

func tags_from_mask(mask: int) -> Array[String]:
	# 将 bitmask 反解为 tags:["DOT","FIRE"]；按 code 升序稳定输出（用于追溯/断言）
	var pairs: Array = []
	for id in tag_code_by_id.keys():
		pairs.append([int(tag_code_by_id[id]), String(id)])
	pairs.sort_custom(func(a, b): return int(a[0]) < int(b[0]))

	var out: Array[String] = []
	for p in pairs:
		var code := int(p[0])
		var id := String(p[1])
		if (mask & (1 << code)) != 0:
			out.append(id)
	return out
