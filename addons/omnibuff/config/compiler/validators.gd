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
