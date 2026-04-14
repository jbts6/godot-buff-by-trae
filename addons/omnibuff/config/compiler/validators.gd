class_name OmniValidate
extends RefCounted

enum Level { INFO, WARNING, ERROR }

class Issue:
	var level: int
	var file: String
	var loc: String # "line=12" or "path=$.buffs[0].effects[1]"
	var id: String
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

