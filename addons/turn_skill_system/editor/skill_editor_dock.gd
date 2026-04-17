@tool
extends Control

const SkillDB := preload("res://addons/turn_skill_system/runtime/skill_db.gd")
const IndexBuilder := preload("res://addons/turn_skill_system/runtime/index_builder.gd")
const JsonIO := preload("res://addons/turn_skill_system/runtime/json_io.gd")
const SkillValidator := preload("res://addons/turn_skill_system/runtime/skill_validator.gd")
const SkillRuntime := preload("res://addons/turn_skill_system/runtime/skill_runtime.gd")
const Grid := preload("res://addons/turn_skill_system/runtime/grid.gd")

@onready var _search: LineEdit = $Root/Left/FilterRow/Search
@onready var _type_filter: OptionButton = $Root/Left/FilterRow/TypeFilter
@onready var _skill_list: ItemList = $Root/Left/SkillList

@onready var _reload_btn: Button = $Root/Left/LeftButtons/ReloadIndexBtn
@onready var _rebuild_btn: Button = $Root/Left/LeftButtons/RebuildIndexBtn
@onready var _new_btn: Button = $Root/Left/LeftButtons/NewSkillBtn

@onready var _validate_btn: Button = $Root/Right/EditorButtons/ValidateBtn
@onready var _save_btn: Button = $Root/Right/EditorButtons/SaveBtn
@onready var _simulate_btn: Button = $Root/Right/EditorButtons/SimulateBtn

@onready var _json_edit: TextEdit = $Root/Right/JsonEdit
@onready var _output: TextEdit = $Root/Right/Output

var _db := SkillDB.new()
var _index: Dictionary = {} # id -> entry
var _current_entry: Dictionary = {}

func _ready() -> void:
	_type_filter.clear()
	_type_filter.add_item("all")
	_type_filter.add_item("active")
	_type_filter.add_item("passive")
	_type_filter.add_item("aura")
	_type_filter.select(0)

	_search.text_changed.connect(_refresh_list)
	_type_filter.item_selected.connect(func(_i): _refresh_list())
	_skill_list.item_selected.connect(_on_select)

	_reload_btn.pressed.connect(_reload_index)
	_rebuild_btn.pressed.connect(_rebuild_index)
	_new_btn.pressed.connect(_new_skill)
	_validate_btn.pressed.connect(_validate_current)
	_save_btn.pressed.connect(_save_current)
	_simulate_btn.pressed.connect(_simulate_current)

	_reload_index()


func _log(msg: String) -> void:
	_output.text += msg + "\n"
	_output.scroll_vertical = 999999


func _reload_index() -> void:
	_output.text = ""
	var r := _db.reload_index()
	if not bool(r.get("ok", false)):
		_log("[index] reload failed: %s" % str(r.get("errors", [])))
		return
	_index = _db._index_by_id
	_log("[index] loaded: %d skills" % _index.size())
	_refresh_list()


func _rebuild_index() -> void:
	_output.text = ""
	var r := IndexBuilder.rebuild_index()
	if not bool(r.get("ok", false)):
		_log("[index] rebuild failed")
		return
	var wr := IndexBuilder.write_index(r.index)
	if not bool(wr.get("ok", false)):
		_log("[index] write failed: %s" % str(wr))
		return
	_log("[index] rebuilt: %d skills (issues=%d)" % [r.index.get("skills", []).size(), r.get("issues", []).size()])
	_reload_index()


func _refresh_list(_unused := "") -> void:
	_skill_list.clear()
	var q := _search.text.strip_edges().to_lower()
	var tf := _type_filter.get_item_text(_type_filter.selected)
	for id in _index.keys():
		var e: Dictionary = _index[id]
		if tf != "all" and String(e.get("type", "")) != tf:
			continue
		var hay := ("%s %s %s" % [String(e.get("name", "")), String(id), str(e.get("tags", []))]).to_lower()
		if q != "" and hay.find(q) < 0:
			continue
		_skill_list.add_item("%s  (%s)" % [String(e.get("name", id)), String(id)])
		_skill_list.set_item_metadata(_skill_list.item_count - 1, e)


func _on_select(idx: int) -> void:
	_current_entry = _skill_list.get_item_metadata(idx)
	var path := String(_current_entry.get("path", ""))
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_log("[open] failed: %s" % path)
		return
	_json_edit.text = f.get_as_text()
	_log("[open] %s" % path)


func _validate_current() -> void:
	_output.text = ""
	var parsed = JSON.parse_string(_json_edit.text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_log("[validate] json parse failed")
		return
	var file_path := String(_current_entry.get("path", ""))
	var issues := SkillValidator.validate_skill(parsed, file_path if file_path != "" else "<unsaved>", true)
	if issues.is_empty():
		_log("[validate] ok")
		return
	for it in issues:
		_log("[%s] %s %s %s" % [it.get("severity",""), it.get("file_path",""), it.get("field_path",""), it.get("message","")])


func _save_current() -> void:
	_output.text = ""
	if _current_entry.is_empty():
		_log("[save] no selected skill")
		return
	var parsed = JSON.parse_string(_json_edit.text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_log("[save] json parse failed")
		return
	var path := String(_current_entry.get("path", ""))
	if path == "":
		_log("[save] missing path")
		return
	var preferred := ["version","id","type","name","desc","tags","targeting","on_cast","on_hit","triggers","aura","meta"]
	var r := JsonIO.write_json_stable(path, parsed, preferred)
	if not bool(r.get("ok", false)):
		_log("[save] failed: %s" % str(r))
		return
	_log("[save] ok: %s" % path)
	_rebuild_index()


func _new_skill() -> void:
	_output.text = ""
	var tf := _type_filter.get_item_text(_type_filter.selected)
	if tf == "all":
		tf = "active"
	var ts := int(Time.get_unix_time_from_system())
	var id := "act_new_%d" % ts
	var dir := "res://addons/turn_skill_system/data/skills/%s" % tf
	if tf == "passive":
		id = "pas_new_%d" % ts
	if tf == "aura":
		id = "aur_new_%d" % ts
	var path := "%s/%s.json" % [dir, id]
	var tmpl := {
		"version": 1,
		"id": id,
		"type": tf,
		"name": id,
		"tags": [],
	}
	if tf == "active":
		tmpl["targeting"] = "FIRST"
		tmpl["on_cast"] = []
		tmpl["on_hit"] = []
	if tf == "passive":
		tmpl["triggers"] = []
	if tf == "aura":
		tmpl["targeting"] = {"needs_primary": false, "primary_role": "cell", "rule": "single_cell", "params": {}}
		tmpl["aura"] = {"range": {"rule": "ally_front_row", "params": {}}, "on_enter": [], "on_exit": []}
	var preferred := ["version","id","type","name","desc","tags","targeting","on_cast","on_hit","triggers","aura","meta"]
	var wr := JsonIO.write_json_stable(path, tmpl, preferred)
	if not bool(wr.get("ok", false)):
		_log("[new] write failed: %s" % str(wr))
		return
	_log("[new] created: %s" % path)
	_rebuild_index()


class EditorPreviewUnit:
	extends RefCounted
	var entity_id: int
	var camp: String
	var cell: Vector2i
	var stats
	var buffs

	func _init(eid: int, c: String, p: Vector2i, s, b) -> void:
		entity_id = eid
		camp = c
		cell = p
		stats = s
		buffs = b


func _simulate_current() -> void:
	_output.text = ""
	var parsed = JSON.parse_string(_json_edit.text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_log("[simulate] json parse failed")
		return
	var skill_id := String(parsed.get("id", ""))
	if skill_id == "":
		_log("[simulate] missing id")
		return

	# 临时写入磁盘（保证 SkillDB 能通过 index 找到并 lazy load）
	if _current_entry.is_empty():
		_log("[simulate] no selected skill (please save first)")
		return
	_save_current()

	# 构造最小战斗上下文（使用 rpg_tests 数据集）
	var result := OmniBuff.ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	var enums_rt := OmniBuff.EnumsRuntime.from_enums_json(result.enums)
	var ds := OmniBuff.DatasetCompiler.compile(result.manifest, enums_rt, result.sources)

	var grid := Grid.new()
	var u1_stats := OmniBuff.StatsComponent.new(1001, ds)
	var u2_stats := OmniBuff.StatsComponent.new(2001, ds)
	var u3_stats := OmniBuff.StatsComponent.new(2002, ds)
	var b1 := OmniBuff.BuffCore.new(ds, enums_rt)
	var b2 := OmniBuff.BuffCore.new(ds, enums_rt)
	var b3 := OmniBuff.BuffCore.new(ds, enums_rt)
	var u1 := EditorPreviewUnit.new(1001, "ally", Vector2i(2, 1), u1_stats, b1)
	var u2 := EditorPreviewUnit.new(2001, "enemy", Vector2i(0, 1), u2_stats, b2)
	var u3 := EditorPreviewUnit.new(2002, "enemy", Vector2i(1, 1), u3_stats, b3)
	grid.set_units([u1, u2, u3])

	var runtime_dict := {"stats_by_entity": {1001: u1_stats, 2001: u2_stats, 2002: u3_stats}, "buff_by_entity": {1001: b1, 2001: b2, 2002: b3}}

	var sim := SkillRuntime.simulate_cast(skill_id, u1, null, {"grid": grid, "dataset": ds, "enums_rt": enums_rt, "runtime_dict": runtime_dict})
	_log(JSON.stringify(sim, "  "))

