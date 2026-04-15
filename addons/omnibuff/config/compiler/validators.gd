class_name OmniValidate
extends RefCounted

## 校验与错误定位（最小可用版）
##
## 设计目标：
## - 所有错误/警告必须带：文件名 + 行号/JSONPath + ID（若有）
## - strict/lenient 策略由调用方决定：strict 将 Warning 升级为 Error 或直接阻断
## - 运行时核心不应该出现“静默忽略配置错误”的行为

enum Level { INFO, WARNING, ERROR }

class Issue:
	## 严重级别：INFO/WARNING/ERROR
	var level: int
	## 文件名（res://...）
	var file: String
	## 位置：CSV用 "line=12"，JSON用 "path=$.buffs[0].effects[1]"
	var loc: String
	## 条目ID（如 buff_id/stat_id），可能为空
	var id: String
	## 人类可读的错误信息
	var message: String

static func error(file: String, loc: String, id: String, msg: String) -> Issue:
	var i := Issue.new()
	i.level = Level.ERROR
	i.file = file
	i.loc = loc
	i.id = id
	i.message = msg
	return i

static func warning(file: String, loc: String, id: String, msg: String) -> Issue:
	var i := Issue.new()
	i.level = Level.WARNING
	i.file = file
	i.loc = loc
	i.id = id
	i.message = msg
	return i

static func info(file: String, loc: String, id: String, msg: String) -> Issue:
	var i := Issue.new()
	i.level = Level.INFO
	i.file = file
	i.loc = loc
	i.id = id
	i.message = msg
	return i

# -----------------------------------------------------------------------------
# M9：工程化校验（>=12条）
# -----------------------------------------------------------------------------

static func validate_all(manifest_path: String, manifest: Dictionary, enums_obj: Dictionary, sources: Dictionary, strict: bool) -> Array[Issue]:
	## 数据集全量校验入口（Schema治理）
	## 返回 Issue 列表；strict 模式会把部分 Warning 提升为 Error（见 _add_issue）。
	var issues: Array[Issue] = []

	_validate_manifest(manifest_path, manifest, strict, issues)
	_validate_enums(manifest_path, enums_obj, strict, issues)

	# 常用 type->file_path（用于错误定位）
	var file_stat := _file_of(manifest, "stat_defs", manifest_path)
	var file_buff := _file_of(manifest, "buff_defs", manifest_path)
	var file_skill := _file_of(manifest, "skill_defs", manifest_path)
	var file_pipe := _file_of(manifest, "damage_pipeline", manifest_path)
	var file_equip := _file_of(manifest, "equipment", manifest_path)
	var file_set := _file_of(manifest, "set_bonus", manifest_path)

	var enums := enums_obj.get("enums", {})
	var tags_table := _tag_id_table(enums_obj)

	# 1) stat_defs 校验
	if sources.has("stat_defs"):
		_validate_stat_defs(file_stat, sources["stat_defs"], enums, strict, issues)
	# 2) buff_defs 校验（含引用stat、枚举合法、tag合法、范围、OVERRIDE/CLAMP冲突、无filter监听DAMAGE告警等）
	if sources.has("buff_defs"):
		_validate_buff_defs(file_buff, sources["buff_defs"], enums, tags_table, sources.get("stat_defs", {}), strict, issues)
	# 3) skill_defs 校验（引用buff、枚举合法、概率范围）
	if sources.has("skill_defs"):
		_validate_skill_defs(file_skill, sources["skill_defs"], enums, sources.get("buff_defs", {}), strict, issues)
	# 4) damage_pipeline 校验（阶段缺失/顺序非法）
	if sources.has("damage_pipeline"):
		_validate_damage_pipeline(file_pipe, sources["damage_pipeline"], strict, issues)
	# 5) equipment.csv 最小校验（header存在）
	if sources.has("equipment"):
		_validate_equipment_csv(file_equip, sources["equipment"], strict, issues)
	# 6) set_bonus 最小校验（引用buff存在）
	if sources.has("set_bonus"):
		_validate_set_bonus(file_set, sources["set_bonus"], sources.get("buff_defs", {}), strict, issues)

	# 7) 触发链/循环依赖（Buff 触发器导致 apply_buff 的图分析）
	# - 循环触发：Error（可能无限触发）
	# - 过深触发链：Warning（可能出现“无限链”或性能/可控性问题）
	if sources.has("buff_defs"):
		_detect_buff_trigger_cycles(file_buff, sources["buff_defs"], strict, issues)

	return issues

# -----------------------------------------------------------------------------
# 内部：基础工具
# -----------------------------------------------------------------------------

static func _add_issue(issues: Array[Issue], issue: Issue, strict: bool) -> void:
	# strict 模式：将 WARNING 升级为 ERROR（用于阻断加载/CI）
	if strict and issue.level == Level.WARNING:
		issue.level = Level.ERROR
	issues.append(issue)

static func _file_of(manifest: Dictionary, type_name: String, manifest_path: String) -> String:
	if not manifest.has("files"):
		return manifest_path
	for f in manifest["files"]:
		if String(f.get("type", "")) == type_name:
			var base_dir := manifest_path.get_base_dir()
			return base_dir.path_join(String(f.get("path", "")))
	return manifest_path

static func _tag_id_table(enums_obj: Dictionary) -> Dictionary:
	# tag_id -> true
	var out := {}
	var tags: Array = enums_obj.get("tags", [])
	for t in tags:
		out[String(t.get("id", ""))] = true
	return out

static func _enum_has(enums: Dictionary, enum_name: String, value: String) -> bool:
	var arr: Array = enums.get(enum_name, [])
	for x in arr:
		if String(x) == value:
			return true
	return false

static func _unknown_fields(file: String, path: String, id: String, obj: Dictionary, allowed: Dictionary, strict: bool, issues: Array[Issue]) -> void:
	for k in obj.keys():
		if not allowed.has(String(k)):
			_add_issue(issues, warning(file, "path=" + path, id, "unknown field: " + String(k)), strict)

# -----------------------------------------------------------------------------
# 规则 0：manifest 基本校验
# -----------------------------------------------------------------------------

static func _validate_manifest(file: String, manifest: Dictionary, strict: bool, issues: Array[Issue]) -> void:
	# 规则：schema_version 必须存在且为 int
	if not manifest.has("schema_version"):
		_add_issue(issues, error(file, "path=$.schema_version", "", "missing schema_version"), strict)
	elif typeof(manifest["schema_version"]) != TYPE_INT:
		_add_issue(issues, error(file, "path=$.schema_version", "", "schema_version must be int"), strict)

	# 规则：files[] 必须存在
	if not manifest.has("files") or typeof(manifest["files"]) != TYPE_ARRAY:
		_add_issue(issues, error(file, "path=$.files", "", "manifest.files must be array"), strict)

# -----------------------------------------------------------------------------
# 规则 1~3：enums/tags 校验
# -----------------------------------------------------------------------------

static func _validate_enums(file: String, enums_obj: Dictionary, strict: bool, issues: Array[Issue]) -> void:
	if not enums_obj.has("enums") or typeof(enums_obj["enums"]) != TYPE_DICTIONARY:
		_add_issue(issues, error(file, "path=$.enums", "", "enums.json missing enums{}"), strict)
	if not enums_obj.has("tags") or typeof(enums_obj["tags"]) != TYPE_ARRAY:
		_add_issue(issues, error(file, "path=$.tags", "", "enums.json missing tags[]"), strict)

	# 规则：关键枚举集合必须存在（作为插件契约的一部分）
	var enums: Dictionary = enums_obj.get("enums", {})
	var required_enums := [
		"op_type", "apply_phase", "duration_type", "stack_mode", "refresh_policy",
		"buff_type", "event_type", "event_phase", "damage_type", "element",
		"condition_type", "ownership_mode", "dispel_scope", "action_kind"
	]
	for name in required_enums:
		if not enums.has(name) or typeof(enums[name]) != TYPE_ARRAY:
			_add_issue(issues, error(file, "path=$.enums." + String(name), "", "missing required enum list: " + String(name)), strict)
			continue

		# 规则：enum 数组项必须是非空字符串，且不得重复（用于协议治理/错误定位）
		var arr: Array = enums.get(name, [])
		var seen := {}
		for i in range(arr.size()):
			var p := "path=$.enums.%s[%s]" % [String(name), i]
			if typeof(arr[i]) != TYPE_STRING or String(arr[i]) == "":
				_add_issue(issues, error(file, p, "", "enum item must be non-empty string"), strict)
				continue
			var v := String(arr[i])
			if seen.has(v):
				_add_issue(issues, error(file, p, "", "duplicate enum item: " + v), strict)
			else:
				seen[v] = true

	# 规则：tag id/code 不重复；code 非负且 <=62（当前 bitmask 使用 int，63+ 会溢出风险）
	var seen_id := {}
	var seen_code := {}
	var tags: Array = enums_obj.get("tags", [])
	for i in range(tags.size()):
		var t: Dictionary = tags[i]
		var id := String(t.get("id", ""))
		var code := int(t.get("code", -1))
		var p := "$.tags[%s]" % i
		if id == "":
			_add_issue(issues, error(file, "path=" + p, "", "tag.id empty"), strict)
		elif seen_id.has(id):
			_add_issue(issues, error(file, "path=" + p, id, "duplicate tag id"), strict)
		else:
			seen_id[id] = true
		if code < 0 or code > 62:
			_add_issue(issues, error(file, "path=" + p, id, "tag.code out of range (0..62)"), strict)
		elif seen_code.has(code):
			_add_issue(issues, error(file, "path=" + p, id, "duplicate tag code"), strict)
		else:
			seen_code[code] = true

# -----------------------------------------------------------------------------
# 规则 4~5：stat_defs 校验（ID重复、范围非法、未知字段）
# -----------------------------------------------------------------------------

static func _validate_stat_defs(file: String, obj: Dictionary, enums: Dictionary, strict: bool, issues: Array[Issue]) -> void:
	var allowed := {"id": true, "default": true, "min": true, "max": true, "clamp": true}
	var arr: Array = obj.get("stats", [])
	var seen := {}
	for i in range(arr.size()):
		var s: Dictionary = arr[i]
		var id := String(s.get("id", ""))
		var p := "$.stats[%s]" % i
		_unknown_fields(file, p, id, s, allowed, strict, issues)

		if id == "":
			_add_issue(issues, error(file, "path=" + p, "", "stat id empty"), strict)
			continue
		if seen.has(id):
			_add_issue(issues, error(file, "path=" + p, id, "duplicate stat id"), strict)
			continue
		seen[id] = true

		var v_def := float(s.get("default", 0.0))
		var v_min := float(s.get("min", -INF))
		var v_max := float(s.get("max", INF))
		if v_min > v_max:
			_add_issue(issues, error(file, "path=" + p, id, "min > max"), strict)
		if v_def < v_min or v_def > v_max:
			_add_issue(issues, error(file, "path=" + p, id, "default out of range"), strict)

# -----------------------------------------------------------------------------
# 规则 6~11：buff_defs 校验（引用不存在、枚举非法、tag非法、范围非法、监听过宽、OVERRIDE冲突）
# -----------------------------------------------------------------------------

static func _validate_buff_defs(file: String, obj: Dictionary, enums: Dictionary, tag_table: Dictionary, stat_defs_obj: Dictionary, strict: bool, issues: Array[Issue]) -> void:
	var allowed := {
		"id": true, "name": true, "buff_type": true, "tags": true, "duration": true,
		"stack": true, "effects": true, "triggers": true, "conditions": true, "dot": true, "dispel": true, "ui_group_key": true
	}
	# 子结构允许字段（用于“未知字段”治理）
	var allowed_duration := {"type": true, "turns": true, "tick_phase": true, "policy": true}
	var allowed_stack := {"mode": true, "max_stack": true, "refresh_policy": true, "ownership_mode": true}
	var allowed_effect := {"kind": true, "stat": true, "op": true, "phase": true, "priority": true, "value": true, "expr": true, "tags": true, "clamp_min": true, "clamp_max": true}
	var allowed_trigger := {"event_type": true, "event_phase": true, "filters": true, "action": true, "scope": true}
	var allowed_filters := {"tag_mask_any": true, "damage_type_any": true, "skill_id": true, "require_hit": true, "stat_threshold": true}
	var allowed_action := {
		"kind": true,
		"value": true,
		"buff_id": true,
		"apply_buff_id": true,
		"chance": true,
		"dot_buff_id": true,
		"dot_tags_mask_any": true
	}
	var allowed_dot := {"tick_phase": true, "element": true, "base_ratio": true, "read_source_stat": true}
	var allowed_dispel := {"dispellable": true, "immune_tags_any": true, "scope": true}
	var allowed_condition := {"type": true, "set_id": true, "count": true, "tag": true, "stat": true, "value": true}

	var arr: Array = obj.get("buffs", [])
	var seen := {}

	# 构建 stat id 表用于引用校验
	var stat_ids := {}
	for s in stat_defs_obj.get("stats", []):
		stat_ids[String((s as Dictionary).get("id", ""))] = true

	for i in range(arr.size()):
		var b: Dictionary = arr[i]
		var id := String(b.get("id", ""))
		var p := "$.buffs[%s]" % i
		_unknown_fields(file, p, id, b, allowed, strict, issues)

		if id == "":
			_add_issue(issues, error(file, "path=" + p, "", "buff id empty"), strict)
			continue
		if seen.has(id):
			_add_issue(issues, error(file, "path=" + p, id, "duplicate buff id"), strict)
			continue
		seen[id] = true

		# buff_type 枚举校验
		var bt := String(b.get("buff_type", ""))
		if bt == "" or not _enum_has(enums, "buff_type", bt):
			_add_issue(issues, error(file, "path=" + p + ".buff_type", id, "invalid buff_type=" + bt), strict)

		# tags 合法性校验
		var tags: Array = b.get("tags", [])
		for ti in range(tags.size()):
			var t := String(tags[ti])
			if not tag_table.has(t):
				_add_issue(issues, warning(file, "path=" + p + ".tags[%s]" % ti, id, "unknown tag=" + t), strict)

		# duration/type 枚举校验 + turns范围
		var duration: Dictionary = b.get("duration", {})
		if typeof(duration) == TYPE_DICTIONARY:
			_unknown_fields(file, p + ".duration", id, duration, allowed_duration, strict, issues)
		var dt := String(duration.get("type", ""))
		if dt == "" or not _enum_has(enums, "duration_type", dt):
			_add_issue(issues, error(file, "path=" + p + ".duration.type", id, "invalid duration.type=" + dt), strict)
		if dt == "TURNS":
			var turns := int(duration.get("turns", -1))
			if turns < 0:
				_add_issue(issues, error(file, "path=" + p + ".duration.turns", id, "turns must be >=0"), strict)

		# stack/mode 枚举校验 + max_stack范围
		var stack: Dictionary = b.get("stack", {})
		if typeof(stack) == TYPE_DICTIONARY:
			_unknown_fields(file, p + ".stack", id, stack, allowed_stack, strict, issues)
		var sm := String(stack.get("mode", ""))
		if sm == "" or not _enum_has(enums, "stack_mode", sm):
			_add_issue(issues, error(file, "path=" + p + ".stack.mode", id, "invalid stack.mode=" + sm), strict)
		var max_stack := int(stack.get("max_stack", 1))
		if max_stack <= 0:
			_add_issue(issues, error(file, "path=" + p + ".stack.max_stack", id, "max_stack must be > 0"), strict)

		# effects：引用stat存在 + op/phase枚举校验 + OVERRIDE冲突
		var override_seen := {} # key = stat|phase -> count
		var effects: Array = b.get("effects", [])
		for ei in range(effects.size()):
			var e: Dictionary = effects[ei]
			if typeof(e) == TYPE_DICTIONARY:
				_unknown_fields(file, p + ".effects[%s]" % ei, id, e, allowed_effect, strict, issues)
			var kind := String(e.get("kind", ""))
			if kind != "modifier":
				continue
			var stat := String(e.get("stat", ""))
			if stat == "" or not stat_ids.has(stat):
				_add_issue(issues, error(file, "path=" + p + ".effects[%s].stat" % ei, id, "unknown stat ref=" + stat), strict)
			var op := String(e.get("op", ""))
			if op == "" or not _enum_has(enums, "op_type", op):
				_add_issue(issues, error(file, "path=" + p + ".effects[%s].op" % ei, id, "invalid op=" + op), strict)
			var phase := String(e.get("phase", ""))
			if phase == "" or not _enum_has(enums, "apply_phase", phase):
				_add_issue(issues, error(file, "path=" + p + ".effects[%s].phase" % ei, id, "invalid phase=" + phase), strict)
			if op == "OVERRIDE":
				var k := stat + "|" + phase
				override_seen[k] = int(override_seen.get(k, 0)) + 1

		for k in override_seen.keys():
			if int(override_seen[k]) > 1:
				_add_issue(issues, error(file, "path=" + p + ".effects", id, "OVERRIDE conflict for " + String(k)), strict)

		# triggers：枚举校验 + “监听DAMAGE但无filter”告警 + action合法
		var triggers: Array = b.get("triggers", [])
		for ti in range(triggers.size()):
			var t: Dictionary = triggers[ti]
			if typeof(t) == TYPE_DICTIONARY:
				_unknown_fields(file, p + ".triggers[%s]" % ti, id, t, allowed_trigger, strict, issues)
			var et := String(t.get("event_type", ""))
			var ep := String(t.get("event_phase", ""))
			if et == "" or not _enum_has(enums, "event_type", et):
				_add_issue(issues, error(file, "path=" + p + ".triggers[%s].event_type" % ti, id, "invalid event_type=" + et), strict)
			if ep == "" or not _enum_has(enums, "event_phase", ep):
				_add_issue(issues, error(file, "path=" + p + ".triggers[%s].event_phase" % ti, id, "invalid event_phase=" + ep), strict)

			var filters: Dictionary = t.get("filters", {})
			if typeof(filters) == TYPE_DICTIONARY:
				_unknown_fields(file, p + ".triggers[%s].filters" % ti, id, filters, allowed_filters, strict, issues)
			if et == "DAMAGE" and filters.is_empty():
				_add_issue(issues, warning(file, "path=" + p + ".triggers[%s].filters" % ti, id, "DAMAGE trigger has no filters (may bloat listeners)"), strict)

			var action: Dictionary = t.get("action", {})
			var ak := String(action.get("kind", ""))
			if typeof(action) == TYPE_DICTIONARY:
				_unknown_fields(file, p + ".triggers[%s].action" % ti, id, action, allowed_action, strict, issues)
			# action.kind 白名单（更贴近真实项目的协议治理）
			# - 必须在 enums.action_kind 中存在，否则 strict=Error / lenient=Warning
			if ak == "":
				_add_issue(issues, error(file, "path=" + p + ".triggers[%s].action.kind" % ti, id, "missing action.kind"), strict)
			elif not _enum_has(enums, "action_kind", ak):
				_add_issue(issues, warning(file, "path=" + p + ".triggers[%s].action.kind" % ti, id, "action.kind not in whitelist: " + ak), strict)

			# 若 action.kind 为 APPLY_BUFF/CHANCE_APPLY_BUFF，则必须声明 buff_id/apply_buff_id 且引用存在
			if ak == "APPLY_BUFF" or ak == "CHANCE_APPLY_BUFF":
				var target_buff_id := ""
				if action.has("buff_id"):
					target_buff_id = String(action.get("buff_id", ""))
				elif action.has("apply_buff_id"):
					target_buff_id = String(action.get("apply_buff_id", ""))
				if target_buff_id == "":
					_add_issue(issues, error(file, "path=" + p + ".triggers[%s].action" % ti, id, "missing buff_id/apply_buff_id for action.kind=" + ak), strict)
				else:
					# 复用 buff_ids 表（在本函数开头构建）
					if not seen.has(target_buff_id):
						# 注意：seen 是本文件内已出现的 buff_id 集合；缺失也可能是“后定义”。
						# 因此这里再做一次“全局存在性”校验：遍历 obj.buffs（O(N)）仅在校验期可接受。
						var exists := false
						for bb in arr:
							if String((bb as Dictionary).get("id", "")) == target_buff_id:
								exists = true
								break
						if not exists:
							_add_issue(issues, error(file, "path=" + p + ".triggers[%s].action" % ti, id, "action references missing buff_id=" + target_buff_id), strict)

			# 规则：chance（若存在）范围必须 0..1
			if action.has("chance"):
				var ch := float(action.get("chance", -1.0))
				if ch < 0.0 or ch > 1.0:
					_add_issue(issues, error(file, "path=" + p + ".triggers[%s].action.chance" % ti, id, "chance must be 0..1"), strict)

		# dot：引用stat存在 + base_ratio范围
		var dot: Dictionary = b.get("dot", {})
		if not dot.is_empty():
			if typeof(dot) == TYPE_DICTIONARY:
				_unknown_fields(file, p + ".dot", id, dot, allowed_dot, strict, issues)
			var rs := String(dot.get("read_source_stat", ""))
			if rs != "" and not stat_ids.has(rs):
				_add_issue(issues, error(file, "path=" + p + ".dot.read_source_stat", id, "unknown stat ref=" + rs), strict)
			var r := float(dot.get("base_ratio", 0.0))
			if r < 0.0:
				_add_issue(issues, error(file, "path=" + p + ".dot.base_ratio", id, "base_ratio must be >=0"), strict)

		# dispel：未知字段治理
		var dispel: Dictionary = b.get("dispel", {})
		if not dispel.is_empty() and typeof(dispel) == TYPE_DICTIONARY:
			_unknown_fields(file, p + ".dispel", id, dispel, allowed_dispel, strict, issues)

		# conditions：未知字段治理（本demo未实现条件系统，但协议仍要治理）
		var conds: Array = b.get("conditions", [])
		for ci in range(conds.size()):
			var cnd: Dictionary = conds[ci]
			if typeof(cnd) == TYPE_DICTIONARY:
				_unknown_fields(file, p + ".conditions[%s]" % ci, id, cnd, allowed_condition, strict, issues)

# -----------------------------------------------------------------------------
# 规则 12：skill_defs 校验（引用buff、枚举合法、chance范围）
# -----------------------------------------------------------------------------

static func _validate_skill_defs(file: String, obj: Dictionary, enums: Dictionary, buff_defs_obj: Dictionary, strict: bool, issues: Array[Issue]) -> void:
	var allowed_skill := {"id": true, "name": true, "damage_type": true, "element": true, "base_damage": true, "tags": true, "on_cast": true, "on_hit": true}
	var allowed_on_cast := {"kind": true, "target": true, "buff_id": true}
	var allowed_on_hit := {"kind": true, "chance": true, "target": true, "buff_id": true}

	var arr: Array = obj.get("skills", [])
	var seen := {}
	var buff_ids := {}
	for b in buff_defs_obj.get("buffs", []):
		buff_ids[String((b as Dictionary).get("id", ""))] = true

	for i in range(arr.size()):
		var s: Dictionary = arr[i]
		var id := String(s.get("id", ""))
		var p := "$.skills[%s]" % i
		if typeof(s) == TYPE_DICTIONARY:
			_unknown_fields(file, p, id, s, allowed_skill, strict, issues)
		if id == "":
			_add_issue(issues, error(file, "path=" + p, "", "skill id empty"), strict)
			continue
		if seen.has(id):
			_add_issue(issues, error(file, "path=" + p, id, "duplicate skill id"), strict)
			continue
		seen[id] = true

		var dt := String(s.get("damage_type", ""))
		if dt != "" and not _enum_has(enums, "damage_type", dt):
			_add_issue(issues, error(file, "path=" + p + ".damage_type", id, "invalid damage_type=" + dt), strict)
		var el := String(s.get("element", ""))
		if el != "" and not _enum_has(enums, "element", el):
			_add_issue(issues, error(file, "path=" + p + ".element", id, "invalid element=" + el), strict)

		# on_cast apply_buff 引用存在
		var on_cast: Array = s.get("on_cast", [])
		for ci in range(on_cast.size()):
			var c: Dictionary = on_cast[ci]
			if typeof(c) == TYPE_DICTIONARY:
				_unknown_fields(file, p + ".on_cast[%s]" % ci, id, c, allowed_on_cast, strict, issues)
			if String(c.get("kind", "")) == "apply_buff":
				var bid := String(c.get("buff_id", ""))
				if bid == "" or not buff_ids.has(bid):
					_add_issue(issues, error(file, "path=" + p + ".on_cast[%s].buff_id" % ci, id, "unknown buff ref=" + bid), strict)

		# on_hit chance_apply_buff 概率范围 + 引用存在
		var on_hit: Array = s.get("on_hit", [])
		for hi in range(on_hit.size()):
			var h: Dictionary = on_hit[hi]
			if typeof(h) == TYPE_DICTIONARY:
				_unknown_fields(file, p + ".on_hit[%s]" % hi, id, h, allowed_on_hit, strict, issues)
			if String(h.get("kind", "")) == "chance_apply_buff":
				var ch := float(h.get("chance", -1.0))
				if ch < 0.0 or ch > 1.0:
					_add_issue(issues, error(file, "path=" + p + ".on_hit[%s].chance" % hi, id, "chance must be 0..1"), strict)
				var bid2 := String(h.get("buff_id", ""))
				if bid2 == "" or not buff_ids.has(bid2):
					_add_issue(issues, error(file, "path=" + p + ".on_hit[%s].buff_id" % hi, id, "unknown buff ref=" + bid2), strict)

# -----------------------------------------------------------------------------
# 规则 13：damage_pipeline 校验（阶段缺失/顺序非法）
# -----------------------------------------------------------------------------

static func _validate_damage_pipeline(file: String, obj: Dictionary, strict: bool, issues: Array[Issue]) -> void:
	var allowed_stage := {"stage": true, "emit_event": true, "phase": true, "side": true}
	var arr: Array = obj.get("pipeline", [])
	if arr.is_empty():
		_add_issue(issues, error(file, "path=$.pipeline", "", "pipeline empty"), strict)
		return
	# 必须包含的阶段（最小约束）
	var required := ["build", "before_deal", "before_take", "resolve", "apply", "after_deal", "after_take", "death"]
	var stages := []
	for i in range(arr.size()):
		if typeof(arr[i]) == TYPE_DICTIONARY:
			_unknown_fields(file, "$.pipeline[%s]" % i, "", (arr[i] as Dictionary), allowed_stage, strict, issues)
		stages.append(String((arr[i] as Dictionary).get("stage", "")))
	for r in required:
		if not stages.has(r):
			_add_issue(issues, error(file, "path=$.pipeline", "", "missing stage=" + String(r)), strict)

	# 顺序固定（与文档一致）
	for i in range(min(required.size(), stages.size())):
		if stages[i] != required[i]:
			_add_issue(issues, warning(file, "path=$.pipeline[%s].stage" % i, "", "stage order differs (expected " + required[i] + ")"), strict)
			break

# -----------------------------------------------------------------------------
# 规则 14：equipment.csv 最小校验（header字段）
# -----------------------------------------------------------------------------

static func _validate_equipment_csv(file: String, rows: Array, strict: bool, issues: Array[Issue]) -> void:
	if rows.is_empty():
		_add_issue(issues, warning(file, "root", "", "equipment.csv empty"), strict)
		return
	var header := (rows[0] as OmniCsv.Row).cols
	var required := ["id", "name", "slot", "implicit_buff_id", "tags"]
	for r in required:
		if header.find(r) == -1:
			_add_issue(issues, error(file, "line=%s" % (rows[0] as OmniCsv.Row).line_no, "", "equipment.csv missing column=" + r), strict)

# -----------------------------------------------------------------------------
# 规则 15：set_bonus 最小校验（引用buff存在）
# -----------------------------------------------------------------------------

static func _validate_set_bonus(file: String, obj: Dictionary, buff_defs_obj: Dictionary, strict: bool, issues: Array[Issue]) -> void:
	var allowed_set := {"id": true, "name": true, "bonuses": true}
	var allowed_bonus := {"count": true, "apply_buff_id": true}
	var buff_ids := {}
	for b in buff_defs_obj.get("buffs", []):
		buff_ids[String((b as Dictionary).get("id", ""))] = true
	var sets: Array = obj.get("sets", [])
	for i in range(sets.size()):
		var s: Dictionary = sets[i]
		var sid := String(s.get("id", ""))
		if typeof(s) == TYPE_DICTIONARY:
			_unknown_fields(file, "$.sets[%s]" % i, sid, s, allowed_set, strict, issues)
		var bonuses: Array = s.get("bonuses", [])
		for bi in range(bonuses.size()):
			var bb: Dictionary = bonuses[bi]
			if typeof(bb) == TYPE_DICTIONARY:
				_unknown_fields(file, "$.sets[%s].bonuses[%s]" % [i, bi], sid, bb, allowed_bonus, strict, issues)
			var bid := String(bb.get("apply_buff_id", ""))
			if bid != "" and not buff_ids.has(bid):
				_add_issue(issues, error(file, "path=$.sets[%s].bonuses[%s].apply_buff_id" % [i, bi], sid, "unknown buff ref=" + bid), strict)

# -----------------------------------------------------------------------------
# 规则 16：Buff 触发链循环/过深检测（无限触发链风险）
# -----------------------------------------------------------------------------

static func _detect_buff_trigger_cycles(file: String, buff_defs_obj: Dictionary, strict: bool, issues: Array[Issue]) -> void:
	## 检测 “Buff触发器 -> apply_buff -> 新Buff” 形成的依赖图是否存在循环/过深链。
	##
	## 为什么重要：
	## - 循环触发（A触发B，B触发A）会导致无限触发链（逻辑与性能灾难）
	## - 过深链（A->B->C->...）容易造成难以预测的顺序与调试困难
	##
	## 约束：
	## - 本函数只做“静态风险检测”，不尝试推断 runtime filters 是否一定命中。
	## - 只要配置层声明了 apply_buff 行为，就应被纳入风险评估。

	var buffs: Array = buff_defs_obj.get("buffs", [])
	var buff_ids := {}
	for b in buffs:
		buff_ids[String((b as Dictionary).get("id", ""))] = true

	# 构建邻接表：from_buff_id -> Array[to_buff_id]
	var edges := {}
	for b in buffs:
		var bd: Dictionary = b
		var from_id := String(bd.get("id", ""))
		if from_id == "":
			continue
		edges[from_id] = []

		var triggers: Array = bd.get("triggers", [])
		for t in triggers:
			var td: Dictionary = t
			var action: Dictionary = td.get("action", {})
			var kind := String(action.get("kind", ""))
			# 只把“会施加buff”的动作纳入依赖图，避免误报（例如 ADD_BASE_DAMAGE 并不会引入新buff）
			if kind != "APPLY_BUFF" and kind != "CHANCE_APPLY_BUFF":
				continue
			# 兼容多种命名：buff_id / apply_buff_id
			var to_id := ""
			if action.has("buff_id"):
				to_id = String(action.get("buff_id", ""))
			elif action.has("apply_buff_id"):
				to_id = String(action.get("apply_buff_id", ""))

			# 只要声明了“对某buff的引用”，就纳入图
			if to_id != "":
				(edges[from_id] as Array).append(to_id)

	# 规则：引用不存在（即使其它校验会报，这里也补一条更语义化的信息）
	for from_id in edges.keys():
		for to_id in edges[from_id]:
			if not buff_ids.has(String(to_id)):
				_add_issue(issues, error(file, "path=$.buffs[id=%s].triggers[].action" % from_id, from_id, "trigger references missing buff_id=" + String(to_id)), strict)

	# 1) 环检测（DFS）
	var visiting := {} # node -> true
	var visited := {}  # node -> true
	var stack: Array[String] = []

	for start in edges.keys():
		if visited.has(start):
			continue
		_dfs_cycle(file, String(start), edges, visiting, visited, stack, strict, issues)

	# 2) 过深链检测（在无环前提下进行）
	# 若存在环，上面已经 Error；这里仍做一次“深度上限”告警，帮助定位潜在无限链。
	var MAX_CHAIN := 16
	for start2 in edges.keys():
		var path: Array[String] = []
		_dfs_depth_limit(file, String(start2), edges, MAX_CHAIN, path, strict, issues)

static func _dfs_cycle(file: String, node: String, edges: Dictionary, visiting: Dictionary, visited: Dictionary, stack: Array[String], strict: bool, issues: Array[Issue]) -> void:
	visiting[node] = true
	stack.append(node)

	var nexts: Array = edges.get(node, [])
	for n in nexts:
		var to := String(n)
		if not edges.has(to):
			continue
		if visiting.has(to):
			# 发现环：输出路径片段
			var idx := stack.find(to)
			var cycle := []
			for i in range(idx, stack.size()):
				cycle.append(stack[i])
			cycle.append(to)
			_add_issue(issues, error(file, "path=$.buffs[id=%s].triggers" % node, node, "trigger cycle detected: " + " -> ".join(cycle)), strict)
			continue
		if not visited.has(to):
			_dfs_cycle(file, to, edges, visiting, visited, stack, strict, issues)

	stack.pop_back()
	visiting.erase(node)
	visited[node] = true

static func _dfs_depth_limit(file: String, node: String, edges: Dictionary, max_depth: int, path: Array[String], strict: bool, issues: Array[Issue]) -> void:
	# 深度限制遍历：发现链过深即告警一次
	path.append(node)
	if path.size() > max_depth:
		_add_issue(issues, warning(file, "path=$.buffs[id=%s].triggers" % node, node, "trigger chain too deep (>%s): %s" % [max_depth, " -> ".join(path)]), strict)
		path.pop_back()
		return

	var nexts: Array = edges.get(node, [])
	for n in nexts:
		var to := String(n)
		if not edges.has(to):
			continue
		# 防止在存在环时无限递归：若已在 path 中则跳过（环由 _dfs_cycle 报错）
		if path.has(to):
			continue
		_dfs_depth_limit(file, to, edges, max_depth, path, strict, issues)

	path.pop_back()
