extends Control

## OmniBuff UI Demo（可视化）
##
## 打开场景：res://addons/omnibuff/demo/buff_ui_demo.tscn
## 目标：在一个 UI 里演示当前 OmniBuff 具备的主要能力（与 demo_runner.gd 内容一致）。

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const EnumsRuntime = preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")
const DatasetCompiler = preload("res://addons/omnibuff/config/compiler/dataset_compiler.gd")

const StatsComponent = preload("res://addons/omnibuff/runtime/components/stats_component.gd")
const BuffCore = preload("res://addons/omnibuff/runtime/core/buff_core.gd")
const DamagePipeline = preload("res://addons/omnibuff/runtime/core/damage_pipeline.gd")
const Replay = preload("res://addons/omnibuff/runtime/core/replay.gd")
const TurnComponent = preload("res://addons/omnibuff/runtime/components/turn_component.gd")

@onready var lbl_status: Label = %StatusLabel
@onready var log_box: RichTextLabel = %LogBox

@onready var btn_reset: Button = %BtnReset
@onready var btn_load: Button = %BtnLoad
@onready var btn_stat_dirty: Button = %BtnStatDirty
@onready var btn_equip_inject: Button = %BtnEquipInject
@onready var btn_damage_pipeline: Button = %BtnDamagePipeline
@onready var btn_multihit: Button = %BtnMultihit
@onready var btn_dot_multi_source: Button = %BtnDotMultiSource
@onready var btn_dispel: Button = %BtnDispel
@onready var btn_clear_log: Button = %BtnClearLog

var replay: RefCounted
var enums_rt: RefCounted
var ds: RefCounted
var pipe: RefCounted


func _ready() -> void:
	btn_reset.pressed.connect(_reset_state)
	btn_load.pressed.connect(_load_dataset)
	btn_stat_dirty.pressed.connect(_demo_stat_cache_dirty)
	btn_equip_inject.pressed.connect(_demo_equip_modifier_injection)
	btn_damage_pipeline.pressed.connect(_demo_damage_pipeline_and_event_index)
	btn_multihit.pressed.connect(_demo_multihit_attack_and_defense_buff)
	btn_dot_multi_source.pressed.connect(_demo_dot_multi_source_tick)
	btn_dispel.pressed.connect(_demo_dispel_semantics)
	btn_clear_log.pressed.connect(func(): log_box.clear())

	_reset_state()


func _log(msg: String) -> void:
	log_box.append_text(msg + "\n")
	log_box.scroll_to_line(log_box.get_line_count())


func _reset_state() -> void:
	replay = Replay.new()
	pipe = DamagePipeline.new()
	enums_rt = null
	ds = null
	lbl_status.text = "未加载数据集"
	_log("[UI Demo] reset")


func _ensure_loaded() -> bool:
	if ds != null and enums_rt != null:
		return true
	_log("[UI Demo] dataset not loaded, auto-loading…")
	_load_dataset()
	return ds != null and enums_rt != null


func _load_dataset() -> void:
	# 用 base_demo 数据集演示（与 demo_runner.gd 保持一致）
	var result = ManifestLoader.load_dataset_full("res://data/base_demo/manifest.json", true)
	if not result.issues.is_empty():
		for issue in result.issues:
			_log("[ERROR] %s %s %s: %s" % [issue.file, issue.loc, issue.id, issue.message])
		lbl_status.text = "加载失败（见日志）"
		return

	enums_rt = EnumsRuntime.from_enums_json(result.enums)
	ds = DatasetCompiler.compile(result.manifest, enums_rt, result.sources)

	lbl_status.text = "已加载 base_demo：stat(ATK)=%s buff(buff_atk_up_3t)=%s" % [ds.stat_id("ATK"), ds.buff_id("buff_atk_up_3t")]
	_log("[UI Demo] dataset loaded OK")


func _demo_stat_cache_dirty() -> void:
	if not _ensure_loaded():
		return
	_log("\n=== Demo: StatCache dirty ===")
	var atk: int = int(ds.stat_id("ATK"))
	var s = StatsComponent.new(1, ds)
	_log("ATK1(default)=%s" % [s.get_final(atk)])
	s.add_base(atk, 5.0)
	_log("ATK2(after add_base +5)=%s" % [s.get_final(atk)])
	_log("ATK3(cache hit)=%s" % [s.get_final(atk)])


func _demo_equip_modifier_injection() -> void:
	if not _ensure_loaded():
		return
	_log("\n=== Demo: Equip buff injects modifiers ===")
	var atk: int = int(ds.stat_id("ATK"))
	var s = StatsComponent.new(2, ds)
	var buff = BuffCore.new(ds, enums_rt)
	_log("ATK(before equip)=%s" % [s.get_final(atk)])
	buff.apply_buff(s, "buff_equip_weapon_001", s.entity_id)
	_log("ATK(after equip buff_equip_weapon_001)=%s" % [s.get_final(atk)])


func _demo_damage_pipeline_and_event_index() -> void:
	if not _ensure_loaded():
		return
	_log("\n=== Demo: DamagePipeline + EventIndex + AFTER_DEAL apply DOT ===")
	var attacker = StatsComponent.new(101, ds)
	var buff_attacker = BuffCore.new(ds, enums_rt)
	buff_attacker.apply_buff(attacker, "buff_equip_weapon_001", attacker.entity_id)
	buff_attacker.apply_buff(attacker, "buff_test_before_deal_plus5", attacker.entity_id)
	buff_attacker.apply_buff(attacker, "buff_test_after_deal_apply_dot", attacker.entity_id)

	var defender = StatsComponent.new(202, ds)
	var buff_defender = BuffCore.new(ds, enums_rt)

	var runtime := {
		"stats_by_entity": {101: attacker, 202: defender},
		"buff_by_entity": {101: buff_attacker, 202: buff_defender}
	}
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var ctx = pipe.deal_damage(attacker, defender, buff_attacker, buff_defender, ds, 20.0, replay, 1, tags_mask, runtime, 0)
	_log("final_damage=%s defender_hp=%s" % [ctx.final_damage, defender.get_final(ds.stat_id("HP"))])
	_log(replay.debug_dump_last_damage())
	_log(buff_defender.debug_dump_instances())

	# 推进到下一回合，在 TURN_START 结算 DOT
	var stats_by_entity := {101: attacker, 202: defender}
	var buff_by_entity := {101: buff_attacker, 202: buff_defender}
	var turn = TurnComponent.new()
	var ids := PackedInt32Array([101, 202]); ids.sort()

	turn.on_turn_end(ids, buff_by_entity, stats_by_entity, pipe, ds, replay)
	var dot_from: int = replay.dot_traces.size()
	turn.on_turn_start(ids, buff_by_entity, stats_by_entity, pipe, ds, replay)
	_log("after TurnStart DOT tick, defender_hp=%s" % [defender.get_final(ds.stat_id("HP"))])
	_log(replay.debug_dump_dot_range(dot_from))


func _demo_multihit_attack_and_defense_buff() -> void:
	if not _ensure_loaded():
		return
	_log("\n=== Demo: Multi-hit + DEF buff ===")
	var base_hits := PackedFloat32Array([12.0, 14.0, 18.0])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var attacker = StatsComponent.new(501, ds)
	var buff_attacker = BuffCore.new(ds, enums_rt)
	buff_attacker.apply_buff(attacker, "buff_equip_weapon_001", attacker.entity_id)

	# Case A: no DEF buff
	var defender_a = StatsComponent.new(502, ds)
	var buff_defender_a = BuffCore.new(ds, enums_rt)
	var runtime_a := {"stats_by_entity": {501: attacker, 502: defender_a}, "buff_by_entity": {501: buff_attacker, 502: buff_defender_a}}
	_log("[CaseA] start_hp=%s" % [defender_a.get_final(ds.stat_id("HP"))])
	for i in range(base_hits.size()):
		var base_damage: float = float(base_hits[i])
		var from_idx: int = replay.damage_traces.size()
		var ctx = pipe.deal_damage(attacker, defender_a, buff_attacker, buff_defender_a, ds, base_damage, replay, 100 + i, tags_mask, runtime_a, i)
		_log(" hit#%s base=%s final=%s hp=%s" % [i + 1, base_damage, ctx.final_damage, defender_a.get_final(ds.stat_id("HP"))])
		_log(replay.debug_dump_damage_range(from_idx))

	# Case B: DEF+20
	var defender_b = StatsComponent.new(503, ds)
	var buff_defender_b = BuffCore.new(ds, enums_rt)
	buff_defender_b.apply_buff(defender_b, "buff_def_up_20_3t", defender_b.entity_id)
	var runtime_b := {"stats_by_entity": {501: attacker, 503: defender_b}, "buff_by_entity": {501: buff_attacker, 503: buff_defender_b}}
	_log("[CaseB] start_hp=%s (DEF+20 applied)" % [defender_b.get_final(ds.stat_id("HP"))])
	_log(buff_defender_b.debug_dump_instances())
	for i in range(base_hits.size()):
		var base_damage: float = float(base_hits[i])
		var from_idx: int = replay.damage_traces.size()
		var ctx = pipe.deal_damage(attacker, defender_b, buff_attacker, buff_defender_b, ds, base_damage, replay, 200 + i, tags_mask, runtime_b, i)
		_log(" hit#%s base=%s final=%s hp=%s" % [i + 1, base_damage, ctx.final_damage, defender_b.get_final(ds.stat_id("HP"))])
		_log(replay.debug_dump_damage_range(from_idx))


func _demo_dot_multi_source_tick() -> void:
	if not _ensure_loaded():
		return
	_log("\n=== Demo: DOT multi-source tick (TURN_START) ===")
	var src_a = StatsComponent.new(301, ds)
	var src_a_buff = BuffCore.new(ds, enums_rt)
	src_a_buff.apply_buff(src_a, "buff_equip_weapon_001", src_a.entity_id) # ATK=30

	var src_b = StatsComponent.new(302, ds)
	var src_b_buff = BuffCore.new(ds, enums_rt)
	src_b_buff.apply_buff(src_b, "buff_equip_weapon_001", src_b.entity_id) # ATK=30
	src_b.add_base(ds.stat_id("ATK"), 20.0) # ATK=50

	var target = StatsComponent.new(303, ds)
	var target_buff = BuffCore.new(ds, enums_rt)

	target_buff.apply_buff(target, "buff_dot_fire_3t", src_a.entity_id)
	target_buff.apply_buff(target, "buff_dot_fire_3t", src_b.entity_id)
	_log(target_buff.debug_dump_instances())

	var stats_by_entity := {301: src_a, 302: src_b, 303: target}
	var buff_by_entity := {301: src_a_buff, 302: src_b_buff, 303: target_buff}
	var turn = TurnComponent.new()
	var ids := PackedInt32Array([301, 302, 303]); ids.sort()

	for i in range(3):
		turn.on_turn_end(ids, buff_by_entity, stats_by_entity, pipe, ds, replay)
		var dot_from: int = replay.dot_traces.size()
		turn.on_turn_start(ids, buff_by_entity, stats_by_entity, pipe, ds, replay)
		_log("TurnStart#%s target_hp=%s" % [i + 1, target.get_final(ds.stat_id("HP"))])
		_log(replay.debug_dump_dot_range(dot_from))


func _demo_dispel_semantics() -> void:
	if not _ensure_loaded():
		return
	_log("\n=== Demo: Dispel semantics (default does not remove PASSIVE/IMPLICIT) ===")
	var target = StatsComponent.new(401, ds)
	var target_buff = BuffCore.new(ds, enums_rt)
	target_buff.apply_buff(target, "buff_equip_weapon_001", 999) # IMPLICIT
	target_buff.apply_buff(target, "buff_food_atk_20_5t", 999)  # EXPLICIT

	_log("ATK(before dispel)=%s" % [target.get_final(ds.stat_id("ATK"))])
	_log(target_buff.debug_dump_instances())
	var removed: int = int(target_buff.dispel_by_tag(target, "BUFF", false))
	_log("dispel_by_tag(BUFF) removed=%s" % [removed])
	_log("ATK(after dispel)=%s" % [target.get_final(ds.stat_id("ATK"))])
	_log(target_buff.debug_dump_instances())

