extends RefCounted
class_name JsonIO

## JSON 读写工具：
## - 读取：返回 {ok,data,error}
## - 写入：稳定缩进 + 稳定字段顺序（尽量手改友好）

static func read_json(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "open_failed", "path": path}
	var txt = f.get_as_text()
	var parsed = JSON.parse_string(txt)
	if parsed == null:
		return {"ok": false, "error": "parse_failed", "path": path}
	return {"ok": true, "data": parsed, "path": path}


static func write_json_stable(path: String, data, preferred_order: Array[String] = []) -> Dictionary:
	var sorted = _sort_value(data, preferred_order)
	var txt = JSON.stringify(sorted, "  ")
	if not txt.ends_with("\n"):
		txt += "\n"

	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "open_failed", "path": path}
	f.store_string(txt)
	return {"ok": true, "path": path}


static func _sort_value(v, preferred_order: Array[String]):
	var t = typeof(v)
	if t == TYPE_DICTIONARY:
		return _sort_dict(v, preferred_order)
	if t == TYPE_ARRAY:
		var out: Array = []
		out.resize(v.size())
		for i in range(v.size()):
			out[i] = _sort_value(v[i], preferred_order)
		return out
	return v


static func _sort_dict(d: Dictionary, preferred_order: Array[String]) -> Dictionary:
	var out = {}

	# 1) 优先字段（按指定顺序）
	for k in preferred_order:
		if d.has(k):
			out[k] = _sort_value(d[k], preferred_order)

	# 2) unknown 字段（按字母序）
	var keys: Array[String] = []
	for k in d.keys():
		var ks = String(k)
		if preferred_order.has(ks):
			continue
		keys.append(ks)
	keys.sort()
	for ks in keys:
		out[ks] = _sort_value(d[ks], preferred_order)

	return out
