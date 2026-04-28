extends RefCounted
class_name Formula

## 公式求值（Expression）：
## - 支持 a.ATK / t.DEF 形式
## - 默认取整策略：floor
## - 返回：{ok,value,resolved:{expr,vars,result},error}

static func eval_expr(expr: String, ctx: Dictionary, rounding := "floor") -> Dictionary:
	var vars = _collect_vars(expr, ctx)
	var rewritten = _rewrite_expr(expr)

	var e = Expression.new()
	var parse_err = e.parse(rewritten, vars.keys())
	if parse_err != OK:
		return {"ok": false, "error": "expr_parse_failed:%s" % e.get_error_text(), "resolved": {"expr": expr, "vars": vars, "result": null}}

	var inputs: Array = []
	for k in vars.keys():
		inputs.append(vars[k])

	var value = e.execute(inputs, null, true)
	if e.has_execute_failed():
		return {"ok": false, "error": "expr_exec_failed:%s" % e.get_error_text(), "resolved": {"expr": expr, "vars": vars, "result": null}}

	var num = float(value)
	var out = _apply_rounding(num, rounding)
	return {"ok": true, "value": out, "resolved": {"expr": expr, "vars": _collect_pretty_vars(expr, ctx), "result": out}}


static func _apply_rounding(x: float, rounding: String) -> float:
	match rounding:
		"ceil":
			return float(ceil(x))
		"round":
			return float(round(x))
		_:
			return float(floor(x)) # 默认 floor


static func _rewrite_expr(expr: String) -> String:
	var out = expr
	# 将 a.ATK -> a_ATK（Expression 的变量名不能包含 '.'）
	out = out.replace("a.", "a_")
	out = out.replace("t.", "t_")
	return out


static func _collect_vars(expr: String, ctx: Dictionary) -> Dictionary:
	# 返回：{ "a_ATK": 100, "t_DEF": 20 }
	var vars: Dictionary = {}
	var re = RegEx.new()
	re.compile("\\b([at])\\.([A-Za-z_][A-Za-z0-9_]*)\\b")
	for m in re.search_all(expr):
		var who = String(m.get_string(1))
		var stat = String(m.get_string(2))
		var key = "%s_%s" % [who, stat]
		if vars.has(key):
			continue
		vars[key] = _lookup_stat(ctx, who, stat)
	return vars


static func _collect_pretty_vars(expr: String, ctx: Dictionary) -> Dictionary:
	# 返回：{ "a.ATK": 100, "t.DEF": 20 }
	var vars: Dictionary = {}
	var re = RegEx.new()
	re.compile("\\b([at])\\.([A-Za-z_][A-Za-z0-9_]*)\\b")
	for m in re.search_all(expr):
		var who = String(m.get_string(1))
		var stat = String(m.get_string(2))
		var key = "%s.%s" % [who, stat]
		if vars.has(key):
			continue
		vars[key] = _lookup_stat(ctx, who, stat)
	return vars


static func _lookup_stat(ctx: Dictionary, who: String, stat: String) -> float:
	var stats_key = "a_stats" if who == "a" else "t_stats"
	if ctx.has(stats_key) and typeof(ctx[stats_key]) == TYPE_DICTIONARY:
		var sd: Dictionary = ctx[stats_key]
		if sd.has(stat):
			return float(sd[stat])

	var unit_key = "caster" if who == "a" else "target"
	if ctx.has(unit_key) and ctx[unit_key] != null:
		var u = ctx[unit_key]
		if u.has_method("get_stat"):
			return float(u.get_stat(stat))
		if _has_property(u, "stats") and u.stats != null and u.stats.has_method("get_final"):
			var dataset = ctx.get("dataset")
			if dataset != null and dataset.has_method("stat_id"):
				var sid = int(dataset.stat_id(stat))
				if sid >= 0:
					return float(u.stats.get_final(sid))
	return 0.0


static func _has_property(obj, prop_name: String) -> bool:
	if obj == null:
		return false
	if not (obj is Object):
		return false
	for p in obj.get_property_list():
		if String(p.get("name", "")) == prop_name:
			return true
	return false
