extends RefCounted
class_name ItemDef

## 最小道具定义（独立于战斗/技能系统）
##
## 约定字段：
## - id/name/desc
## - targeting: Dictionary（例如 {rule:"single_cell", camp:"ally"}）
## - effects: Array[Dictionary]（例如 {kind:"heal", params:{amount:35}}）

var id: String = ""
var name: String = ""
var desc: String = ""
var targeting: Dictionary = {}
var effects: Array = []


static func from_dict(d: Dictionary) -> ItemDef:
	var x = ItemDef.new()
	x.id = String(d.get("id", ""))
	x.name = String(d.get("name", ""))
	x.desc = String(d.get("desc", ""))
	x.targeting = d.get("targeting", {})
	x.effects = d.get("effects", [])
	return x

