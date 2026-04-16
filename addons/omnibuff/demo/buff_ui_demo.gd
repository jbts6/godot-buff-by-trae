extends Control

## OmniBuff UI Demo（可视化 / RPG Tests Coverage）
##
## 打开场景：res://addons/omnibuff/demo/buff_ui_demo.tscn
##
## 说明：
## - 这是“scenario runner”形式的 demo：左侧选择场景，右侧看日志输出。
## - 每个 scenario 尽量对齐 `addons/omnibuff/tests/rpg/` 的语义（不依赖 GUT）。
## - 运行前会 reset（避免多次点击导致状态污染）。

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const EnumsRuntime = preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")
const DatasetCompiler = preload("res://addons/omnibuff/config/compiler/dataset_compiler.gd")

const StatsComponent = preload("res://addons/omnibuff/runtime/components/stats_component.gd")
const BuffCore = preload("res://addons/omnibuff/runtime/core/buff_core.gd")
const DamagePipeline = preload("res://addons/omnibuff/runtime/core/damage_pipeline.gd")
const Replay = preload("res://addons/omnibuff/runtime/core/replay.gd")
const CommandContext = preload("res://addons/omnibuff/runtime/core/command_context.gd")
const BattleExecutor = preload("res://addons/omnibuff/runtime/core/battle_executor.gd")
const TurnComponent = preload("res://addons/omnibuff/runtime/components/turn_component.gd")
const DebugHudScene = preload("res://addons/omnibuff/demo/debug_hud.tscn")

@onready var lbl_status: Label = %StatusLabel
@onready var log_box: RichTextLabel = %LogBox

@onready var btn_reset: Button = %BtnReset
@onready var dataset_select: OptionButton = %DatasetSelect
@onready var scenario_list: ItemList = %ScenarioList
@onready var btn_load: Button = %BtnLoad
@onready var btn_run_selected: Button = %BtnRunSelected
@onready var btn_run_all: Button = %BtnRunAll
@onready var btn_toggle_hud: Button = %BtnToggleHud
@onready var btn_copy_log: Button = %BtnCopyLog
@onready var btn_clear_log: Button = %BtnClearLog

var replay: RefCounted
var enums_rt: RefCounted
var ds: RefCounted
var sources: Dictionary = {}
var pipe: RefCounted
var turn: RefCounted

# RichTextLabel 的 append_text 不一定会同步到 `text` 属性（UI能看到但读到空串）。
# 因此我们维护一个“可复制”的纯文本缓冲区。
var _log_buffer: String = ""

var _dataset_id: String = ""

var _all_scenarios: Array = []
var _visible_scenarios: Array = []

var _hud: Window = null
var _hud_runtime: Dictionary = {}
var _hud_attacker_id: int = -1
var _hud_defender_id: int = -1


func _ready() -> void:
	btn_reset.pressed.connect(_reset_state)
	btn_load.pressed.connect(func(): _load_dataset_by_id(_dataset_id))
	btn_run_selected.pressed.connect(_run_selected)
	btn_run_all.pressed.connect(_run_all)
	btn_toggle_hud.pressed.connect(_toggle_hud)
	btn_copy_log.pressed.connect(_copy_log_to_clipboard)
	btn_clear_log.pressed.connect(func():
		_log_buffer = ""
		log_box.clear()
	)

	dataset_select.clear()
	dataset_select.add_item("base_demo")
	dataset_select.add_item("rpg_tests")
	dataset_select.item_selected.connect(func(_idx: int):
		_dataset_id = dataset_select.get_item_text(dataset_select.selected)
		_refresh_scenario_list()
	)

	_register_scenarios()
	_dataset_id = "rpg_tests"
	dataset_select.select(1)
	_refresh_scenario_list()

	_reset_state()


func _log(msg: String) -> void:
	_log_buffer += msg + "\n"
	log_box.append_text(msg + "\n")
	log_box.scroll_to_line(log_box.get_line_count())


func _copy_log_to_clipboard() -> void:
	DisplayServer.clipboard_set(_log_buffer)
	lbl_status.text = "已复制日志到剪贴板（%s 字符）" % [_log_buffer.length()]


func _reset_state() -> void:
	replay = Replay.new()
	pipe = DamagePipeline.new()
	turn = TurnComponent.new()
	enums_rt = null
	ds = null
	sources = {}
	lbl_status.text = "未加载数据集"
	_log("[UI Demo] reset")


func _dataset_manifest_path(dataset_id: String) -> String:
	if dataset_id == "rpg_tests":
		return "res://data/rpg_tests/manifest.json"
	return "res://data/base_demo/manifest.json"


func _load_dataset_by_id(dataset_id: String) -> bool:
	var manifest_path: String = _dataset_manifest_path(dataset_id)
	var result = ManifestLoader.load_dataset_full(manifest_path, true)
	if not result.issues.is_empty():
		for issue in result.issues:
			_log("[ERROR] %s %s %s: %s" % [issue.file, issue.loc, issue.id, issue.message])
		lbl_status.text = "加载失败（见日志）"
		return false

	enums_rt = EnumsRuntime.from_enums_json(result.enums)
	ds = DatasetCompiler.compile(result.manifest, enums_rt, result.sources)
	sources = result.sources
	lbl_status.text = "已加载 %s（ATK=%s HP=%s）" % [dataset_id, ds.stat_id("ATK"), ds.stat_id("HP")]
	return true


func _ensure_loaded_for(dataset_id: String) -> bool:
	if ds != null and enums_rt != null and _dataset_id == dataset_id:
		return true
	_dataset_id = dataset_id
	return _load_dataset_by_id(dataset_id)


func _refresh_scenario_list() -> void:
	scenario_list.clear()
	_visible_scenarios = []
	for s in _all_scenarios:
		if String((s as Dictionary).get("dataset", "")) != _dataset_id:
			continue
		_visible_scenarios.append(s)
		scenario_list.add_item(String((s as Dictionary).get("title", "")))
	if scenario_list.item_count > 0:
		scenario_list.select(0)


func _run_selected() -> void:
	var selected := scenario_list.get_selected_items()
	if selected.is_empty():
		_log("[UI Demo] no scenario selected")
		return
	var idx: int = int(selected[0])
	if idx < 0 or idx >= _visible_scenarios.size():
		return
	_run_scenario(_visible_scenarios[idx])


func _run_all() -> void:
	for s in _visible_scenarios:
		_run_scenario(s)


func _run_scenario(s: Dictionary) -> void:
	_reset_state()
	_hud_runtime = {}
	_hud_attacker_id = -1
	_hud_defender_id = -1
	var dataset_id: String = String(s.get("dataset", ""))
	if not _ensure_loaded_for(dataset_id):
		return
	var title: String = String(s.get("title", ""))
	_log("\n==================================================")
	_log("SCENARIO: " + title)
	_log("covers: " + str(s.get("covers", [])))
	_log("dataset: " + dataset_id)
	var dmg_from: int = int(replay.damage_traces.size())
	var dot_from: int = int(replay.dot_traces.size())
	(s.get("fn") as Callable).call()
	_dump_replay_delta(dmg_from, dot_from)
	_sync_hud_runtime()


func _toggle_hud() -> void:
	if _hud == null:
		_hud = DebugHudScene.instantiate()
		add_child(_hud)
		_hud.hide()
	if _hud.visible:
		_hud.hide()
	else:
		_hud.show()
	_sync_hud_runtime()


func _sync_hud_runtime() -> void:
	if _hud == null:
		return
	# 为 HUD 附加 ds，便于展示 stat/buff id
	var rt := _hud_runtime.duplicate()
	rt["ds"] = ds
	# 为 Listeners/DOT 等输出附加 enums_rt（用于 tag_mask 与 event_type/phase 反查）
	rt["enums_rt"] = enums_rt
	_hud.set_runtime(rt)
	_hud.set_preferred_entities(_hud_attacker_id, _hud_defender_id)


func _dump_replay_delta(dmg_from: int, dot_from: int) -> void:
	var dmg_to: int = int(replay.damage_traces.size())
	var dot_to: int = int(replay.dot_traces.size())
	if dmg_to > dmg_from:
		_log(replay.debug_dump_damage_range(dmg_from))
	if dot_to > dot_from:
		_log(replay.debug_dump_dot_range(dot_from))


func _mk_actor(eid: int) -> Dictionary:
	var s = StatsComponent.new(eid, ds)
	var b = BuffCore.new(ds, enums_rt)
	return {"id": eid, "stats": s, "buffs": b}


func _mk_runtime(actors: Array) -> Dictionary:
	var stats_by_entity: Dictionary = {}
	var buff_by_entity: Dictionary = {}
	for a in actors:
		var ad: Dictionary = a
		stats_by_entity[int(ad["id"])] = ad["stats"]
		buff_by_entity[int(ad["id"])] = ad["buffs"]
	var rt := {"stats_by_entity": stats_by_entity, "buff_by_entity": buff_by_entity}
	# 约定：最后一次构建的 runtime 作为 Debug HUD 的数据源
	_hud_runtime = rt
	return rt


func _ids_sorted(actors: Array) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for a in actors:
		ids.append(int((a as Dictionary)["id"]))
	ids.sort()
	return ids


func _dump_actor_basic(label: String, a: Dictionary, stat_names: Array) -> void:
	_log("--- " + label + " (eid=" + str(int(a["id"])) + ") ---")
	for sn in stat_names:
		var sid: int = int(ds.stat_id(String(sn)))
		if sid >= 0:
			_log("%s=%s" % [String(sn), float(a["stats"].get_final(sid))])
	_log(a["buffs"].debug_dump_instances())


func _count_instances_by_buff_id(buffs: RefCounted, buff_id_str: String) -> int:
	var cnt: int = 0
	for inst_id in buffs.inst_ids:
		var inst = buffs.instances_by_id.get(int(inst_id), null)
		if inst == null:
			continue
		var def: Dictionary = ds.buff_defs[int(inst.buff_def_id)]
		if String(def.get("id", "")) == buff_id_str:
			cnt += 1
	return cnt


func _register_scenarios() -> void:
	_all_scenarios = [
		{
			"id": "dataset_authority",
			"title": "Dataset / Manifest authority & issues",
			"dataset": "rpg_tests",
			"covers": ["test_manifest_loader_authority.gd", "test_dataset_isolation_manifests.gd"],
			"fn": Callable(self, "_sc_dataset_authority")
		},
		{
			"id": "stats_percent_layers",
			"title": "Stats / Percent layers (multi-stage multipliers)",
			"dataset": "rpg_tests",
			"covers": ["test_stat_percent_layers.gd", "test_percent_modifier.gd"],
			"fn": Callable(self, "_sc_stats_percent_layers")
		},
		{
			"id": "stats_override_and_clamp",
			"title": "Stats / override priority + clamp",
			"dataset": "rpg_tests",
			"covers": ["test_stat_priority_and_override.gd", "test_stat_clamp.gd"],
			"fn": Callable(self, "_sc_stats_override_and_clamp")
		},
		{
			"id": "lifecycle_expire",
			"title": "Buff lifecycle / expire on turn end",
			"dataset": "rpg_tests",
			"covers": ["test_buff_lifecycle_expire.gd"],
			"fn": Callable(self, "_sc_lifecycle_expire")
		},
		{
			"id": "lifecycle_stacking",
			"title": "Buff lifecycle / stacking modes",
			"dataset": "rpg_tests",
			"covers": ["test_buff_lifecycle_stacking.gd"],
			"fn": Callable(self, "_sc_lifecycle_stacking")
		},
		{
			"id": "while_condition",
			"title": "Buff lifecycle / while-condition active/inactive",
			"dataset": "rpg_tests",
			"covers": ["test_buff_lifecycle_while_condition.gd", "test_buff_removal_a5.gd (inactive remove)"],
			"fn": Callable(self, "_sc_while_condition")
		},
		{
			"id": "remove_a5",
			"title": "Remove (A5) / by_buff_id + by_tag + stop trigger",
			"dataset": "rpg_tests",
			"covers": ["test_buff_removal_a5.gd"],
			"fn": Callable(self, "_sc_remove_a5")
		},
		{
			"id": "shield_and_reduction",
			"title": "Damage / shield absorb + reduction",
			"dataset": "rpg_tests",
			"covers": ["test_shield_absorb.gd", "test_damage_reduction.gd"],
			"fn": Callable(self, "_sc_shield_and_reduction")
		},
		{
			"id": "filters_require_crit",
			"title": "Phase1 Filters / require_crit gates triggers",
			"dataset": "rpg_tests",
			"covers": ["test_event_filters_extended.gd (require_crit)"],
			"fn": Callable(self, "_sc_filters_require_crit")
		},
		{
			"id": "filters_shield_absorbed",
			"title": "Phase1 Filters / require_shield_absorbed",
			"dataset": "rpg_tests",
			"covers": ["test_event_filters_extended.gd (shield_absorbed)"],
			"fn": Callable(self, "_sc_filters_shield_absorbed")
		},
		{
			"id": "filters_fire_immunity",
			"title": "Phase1 Filters / element=FIRE -> fire immunity (final_damage=0)",
			"dataset": "rpg_tests",
			"covers": ["test_event_filters_extended.gd (fire immunity)"],
			"fn": Callable(self, "_sc_filters_fire_immunity")
		},
		{
			"id": "filters_skill_id",
			"title": "Phase1 Filters / skill_id gates triggers",
			"dataset": "rpg_tests",
			"covers": ["test_event_filters_extended.gd (skill_id)"],
			"fn": Callable(self, "_sc_filters_skill_id")
		},
		{
			"id": "filters_min_absorbed_shield",
			"title": "Phase1 Filters / min_absorbed_shield threshold",
			"dataset": "rpg_tests",
			"covers": ["test_event_filters_extended.gd (min_absorbed_shield)"],
			"fn": Callable(self, "_sc_filters_min_absorbed_shield")
		},
		{
			"id": "action_heal",
			"title": "Phase1 Actions / HEAL (+30 after take)",
			"dataset": "rpg_tests",
			"covers": ["test_event_actions_phase1.gd (heal)"],
			"fn": Callable(self, "_sc_action_heal")
		},
		{
			"id": "action_add_shield",
			"title": "Phase1 Actions / ADD_SHIELD (+50 before take)",
			"dataset": "rpg_tests",
			"covers": ["test_event_actions_phase1.gd (add shield)"],
			"fn": Callable(self, "_sc_action_add_shield")
		},
		{
			"id": "action_dispel_debuff",
			"title": "Phase1 Actions / DISPEL (by_tag=DEBUFF)",
			"dataset": "rpg_tests",
			"covers": ["test_event_actions_phase1.gd (dispel)"],
			"fn": Callable(self, "_sc_action_dispel_debuff")
		},
		{
			"id": "action_lifesteal",
			"title": "Phase1 Actions / LIFESTEAL (20%)",
			"dataset": "rpg_tests",
			"covers": ["test_event_actions_phase1.gd (lifesteal)"],
			"fn": Callable(self, "_sc_action_lifesteal")
		},
		{
			"id": "action_reflect",
			"title": "Phase1 Actions / REFLECT_DAMAGE (30%)",
			"dataset": "rpg_tests",
			"covers": ["test_event_actions_phase1.gd (reflect)"],
			"fn": Callable(self, "_sc_action_reflect")
		},
		{
			"id": "command_cancel_escape",
			"title": "Phase1 Command / CANCEL escape (CMD_BEFORE)",
			"dataset": "rpg_tests",
			"covers": ["test_command_events_phase1.gd (cancel escape)"],
			"fn": Callable(self, "_sc_command_cancel_escape")
		},
		{
			"id": "command_basic_attack_tag",
			"title": "Phase1 Command / BASIC_ATTACK tag match",
			"dataset": "rpg_tests",
			"covers": ["test_command_events_phase1.gd (basic attack tag)"],
			"fn": Callable(self, "_sc_command_basic_attack_tag")
		},
		{
			"id": "command_use_item",
			"title": "Phase1 Command / USE_ITEM item_id filter",
			"dataset": "rpg_tests",
			"covers": ["test_command_events_phase1.gd (use item)"],
			"fn": Callable(self, "_sc_command_use_item")
		},
		{
			"id": "executor_attack_basic",
			"title": "Executor / ATTACK basic attack bonus -> DAMAGE chain",
			"dataset": "rpg_tests",
			"covers": ["test_battle_executor_minimal.gd (attack)"],
			"fn": Callable(self, "_sc_executor_attack_basic")
		},
		{
			"id": "executor_escape_cancel",
			"title": "Executor / ESCAPE canceled by COMMAND",
			"dataset": "rpg_tests",
			"covers": ["test_battle_executor_minimal.gd (escape)"],
			"fn": Callable(self, "_sc_executor_escape_cancel")
		},
		{
			"id": "executor_multihit_triple_slash",
			"title": "Executor / multi-hit triple slash (roll_key increments)",
			"dataset": "rpg_tests",
			"covers": ["test_battle_executor_multihit_multitarget.gd (multihit)"],
			"fn": Callable(self, "_sc_executor_multihit_triple_slash")
		},
		{
			"id": "executor_multitarget_all",
			"title": "Executor / multi-target ALL (sorted targets)",
			"dataset": "rpg_tests",
			"covers": ["test_battle_executor_multihit_multitarget.gd (multitarget)"],
			"fn": Callable(self, "_sc_executor_multitarget_all")
		},
		{
			"id": "event_chance_apply_determinism",
			"title": "Event / CHANCE_APPLY_BUFF determinism (seed+roll visible)",
			"dataset": "rpg_tests",
			"covers": ["test_event_chance_apply_buff_determinism.gd"],
			"fn": Callable(self, "_sc_event_chance_apply_determinism")
		},
		{
			"id": "dot_actions_mul_set_clear",
			"title": "DOT actions / MUL + SET + ADD(-1) + CLEAR(tag)",
			"dataset": "rpg_tests",
			"covers": ["test_dot_actions_mul_add_set_clear.gd"],
			"fn": Callable(self, "_sc_dot_actions_mul_set_clear")
		},
		{
			"id": "roll_key",
			"title": "RNG / roll_key deterministic hit+crit",
			"dataset": "rpg_tests",
			"covers": ["test_roll_key_makes_hit_crit_independent_per_strike.gd", "test_hit_crit_determinism.gd"],
			"fn": Callable(self, "_sc_roll_key")
		},
		{
			"id": "multihit_each_hit_dot",
			"title": "Multi-hit / each hit applies DOT",
			"dataset": "rpg_tests",
			"covers": ["test_multihit_each_hit_applies_dot.gd"],
			"fn": Callable(self, "_sc_multihit_each_hit_dot")
		},
		{
			"id": "aoe_multitarget_multihit",
			"title": "AOE / multi-target + multi-hit + per-target hit/crit + DOT",
			"dataset": "rpg_tests",
			"covers": ["test_aoe_multitarget_multihit_per_target_hit_crit_and_dot.gd"],
			"fn": Callable(self, "_sc_aoe_multitarget_multihit")
		},
		{
			"id": "full_turn_script_battle",
			"title": "Integration / full turn script battle (DOT@TURN_START + dispel + immunity)",
			"dataset": "rpg_tests",
			"covers": ["test_full_turn_script_battle.gd", "test_undispellable_and_immunity.gd"],
			"fn": Callable(self, "_sc_full_turn_script_battle")
		}
	]


# ------------------------------
# Scenarios
# ------------------------------

func _sc_dataset_authority() -> void:
	var result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	_log("issues.count=" + str(result.issues.size()))
	_log("manifest.dataset_id=" + String(result.manifest.get("dataset_id", "")))
	_log("source keys=" + str(result.sources.keys()))


func _sc_stats_percent_layers() -> void:
	var e := _mk_actor(9801)
	_hud_attacker_id = int(e["id"])
	# Debug HUD 依赖 runtime 注入 entity 列表；单体场景也要构建 runtime
	_mk_runtime([e])
	var atk_id: int = int(ds.stat_id("ATK"))
	_dump_actor_basic("baseline", e, ["ATK"])

	e["buffs"].apply_buff(e["stats"], "buff_test_weapon_atk_flat_10", 9801)
	e["buffs"].apply_buff(e["stats"], "buff_test_passive_atk_flat_5", 9801)
	e["buffs"].apply_buff(e["stats"], "buff_atk_pct_5", 9801)
	e["buffs"].apply_buff(e["stats"], "buff_test_trinket_atk_pct_10", 9801)
	e["buffs"].apply_buff(e["stats"], "buff_test_total_atk_pct_20", 9801)

	var expected: float = (10.0 + 10.0 + 5.0) * (1.0 + 0.05 + 0.10) * (1.0 + 0.20)
	_log("ATK expected=" + str(expected) + " got=" + str(float(e["stats"].get_final(atk_id))))
	_log(e["buffs"].debug_dump_instances())


func _sc_stats_override_and_clamp() -> void:
	var e := _mk_actor(7001)
	_hud_attacker_id = int(e["id"])
	_mk_runtime([e])
	var hit_id: int = int(ds.stat_id("HIT_RATE"))
	_log("baseline HIT_RATE=" + str(float(e["stats"].get_final(hit_id))))

	# override priority
	var inst_low: int = int(e["buffs"].apply_buff(e["stats"], "buff_c_override_hit_1_p800", int(e["id"])))
	var inst_high: int = int(e["buffs"].apply_buff(e["stats"], "buff_c_override_hit_0_p900", int(e["id"])))
	_log("override inst_low=%s inst_high=%s HIT_RATE=%s (expect 0)" % [inst_low, inst_high, float(e["stats"].get_final(hit_id))])

	# clamp
	var inst_plus2: int = int(e["buffs"].apply_buff(e["stats"], "buff_c_add_hit_plus_2", int(e["id"])))
	_log("after HIT_RATE+2 inst=%s HIT_RATE(clamped)=%s (expect 1)" % [inst_plus2, float(e["stats"].get_final(hit_id))])
	_log(e["buffs"].debug_dump_instances())


func _sc_lifecycle_expire() -> void:
	var e := _mk_actor(7201)
	_hud_attacker_id = int(e["id"])
	var runtime := _mk_runtime([e])
	var ids := _ids_sorted([e])
	var atk_id: int = int(ds.stat_id("ATK"))

	e["buffs"].apply_buff(e["stats"], "buff_life_replace_atk_10_2t", 111)
	_log("after apply ATK=" + str(float(e["stats"].get_final(atk_id))))
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null)
	_log("after Turn1 end ATK=" + str(float(e["stats"].get_final(atk_id))))
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, null)
	_log("after Turn2 end (expired) ATK=" + str(float(e["stats"].get_final(atk_id))))
	_log(e["buffs"].debug_dump_instances())


func _sc_lifecycle_stacking() -> void:
	var e := _mk_actor(7102)
	_hud_attacker_id = int(e["id"])
	_mk_runtime([e])
	var atk_id: int = int(ds.stat_id("ATK"))
	_log("baseline ATK=" + str(float(e["stats"].get_final(atk_id))))

	# REPLACE（GLOBAL）：重复 apply 仍 1 个实例
	e["buffs"].apply_buff(e["stats"], "buff_life_replace_atk_10_2t", 111)
	e["buffs"].apply_buff(e["stats"], "buff_life_replace_atk_10_2t", 222)
	_log("REPLACE inst_count=" + str(_count_instances_by_buff_id(e["buffs"], "buff_life_replace_atk_10_2t")))

	# ADD_STACK（GLOBAL）：叠层并 cap
	for i in range(5):
		e["buffs"].apply_buff(e["stats"], "buff_life_stack_atk_10_2t_max3", 111)
	_log("ADD_STACK(inst=1) stacks capped, ATK=" + str(float(e["stats"].get_final(atk_id))))

	# MULTI_INSTANCE：三次创建三实例
	for i in range(3):
		e["buffs"].apply_buff(e["stats"], "buff_life_multi_atk_10_2t", 111)
	_log("MULTI_INSTANCE inst_count=" + str(_count_instances_by_buff_id(e["buffs"], "buff_life_multi_atk_10_2t")))
	_log(e["buffs"].debug_dump_instances())


func _sc_while_condition() -> void:
	var e := _mk_actor(7505)
	_hud_attacker_id = int(e["id"])
	_mk_runtime([e])
	var hp_id: int = int(ds.stat_id("HP"))
	var atk_id: int = int(ds.stat_id("ATK"))

	_log("baseline HP=" + str(float(e["stats"].get_final(hp_id))) + " ATK=" + str(float(e["stats"].get_final(atk_id))))
	e["buffs"].apply_buff(e["stats"], "buff_cond_hp_le_50_atk_up_10", 111)
	_log("after apply (inactive expected) ATK=" + str(float(e["stats"].get_final(atk_id))))
	_log(e["buffs"].debug_dump_instances())

	# 扣血到 50：应激活
	e["stats"].add_base(hp_id, -50.0)
	_log("after HP->50 ATK=" + str(float(e["stats"].get_final(atk_id))))
	_log(e["buffs"].debug_dump_instances())


func _sc_remove_a5() -> void:
	var attacker := _mk_actor(7503)
	var defender := _mk_actor(7504)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	attacker["buffs"].apply_buff(attacker["stats"], "buff_on_hit_apply_dot", int(attacker["id"]))
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 12.0, replay, 1, tags_mask, runtime, 0)
	_log("after hit#1 defender DOT count=" + str(_count_instances_by_buff_id(defender["buffs"], "buff_dot_fire_3t")))

	var removed: int = int(attacker["buffs"].remove_by_buff_id(attacker["stats"], "buff_on_hit_apply_dot", "ALL"))
	_log("removed trigger buff count=" + str(removed))

	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 12.0, replay, 2, tags_mask, runtime, 0)
	_log("after hit#2 defender DOT count (should not increase)=" + str(_count_instances_by_buff_id(defender["buffs"], "buff_dot_fire_3t")))

	# remove by tag（DEBUFF）
	defender["buffs"].apply_buff(defender["stats"], "buff_dot_fire_3t", 111)
	var removed_debuff: int = int(defender["buffs"].remove_by_tag(defender["stats"], "DEBUFF", "ALL"))
	_log("remove_by_tag(DEBUFF) removed=" + str(removed_debuff))
	_log(defender["buffs"].debug_dump_instances())


func _sc_shield_and_reduction() -> void:
	var attacker := _mk_actor(7601)
	var defender := _mk_actor(7602)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var hp_id: int = int(ds.stat_id("HP"))
	var shield_id: int = int(ds.stat_id("SHIELD"))

	defender["buffs"].apply_buff(defender["stats"], "buff_shield_50", int(defender["id"]))
	_log("after shield SHIELD=" + str(float(defender["stats"].get_final(shield_id))) + " HP=" + str(float(defender["stats"].get_final(hp_id))))

	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 30.0, replay, 10, tags_mask, runtime, 0)
	_log("after hit with shield SHIELD=" + str(float(defender["stats"].get_final(shield_id))) + " HP=" + str(float(defender["stats"].get_final(hp_id))))

	defender["buffs"].apply_buff(defender["stats"], "buff_dmg_reduce_20p", int(defender["id"]))
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 30.0, replay, 11, tags_mask, runtime, 0)
	_log("after hit with dmg_reduce HP=" + str(float(defender["stats"].get_final(hp_id))))
	_log(defender["buffs"].debug_dump_instances())


func _sc_filters_require_crit() -> void:
	var attacker := _mk_actor(8851)
	var defender := _mk_actor(8852)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])

	# 固定命中
	var hit_id := int(ds.stat_id("HIT_RATE"))
	var evade_id := int(ds.stat_id("EVADE"))
	attacker["stats"].add_base(hit_id, 1.0 - float(attacker["stats"].get_final(hit_id)))
	defender["stats"].add_base(evade_id, 0.0 - float(defender["stats"].get_final(evade_id)))

	# 强制暴击：CRIT_RATE=1；CRIT_DMG=0 避免额外倍伤影响观测
	var cr_id := int(ds.stat_id("CRIT_RATE"))
	var cd_id := int(ds.stat_id("CRIT_DMG"))
	attacker["stats"].add_base(cr_id, 1.0 - float(attacker["stats"].get_final(cr_id)))
	attacker["stats"].add_base(cd_id, 0.0 - float(attacker["stats"].get_final(cd_id)))

	attacker["buffs"].apply_buff(attacker["stats"], "buff_filter_require_crit_add_base_5", int(attacker["id"]))
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var ctx = pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 10.0, replay, 1, tags_mask, runtime, 0)
	_log("crit=" + str(bool(ctx.crit)) + " base_damage(after buffs)=" + str(float(ctx.base_damage)))


func _sc_filters_shield_absorbed() -> void:
	var attacker := _mk_actor(8861)
	var defender := _mk_actor(8862)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])

	var hit_id := int(ds.stat_id("HIT_RATE"))
	var evade_id := int(ds.stat_id("EVADE"))
	attacker["stats"].add_base(hit_id, 1.0 - float(attacker["stats"].get_final(hit_id)))
	defender["stats"].add_base(evade_id, 0.0 - float(defender["stats"].get_final(evade_id)))

	defender["buffs"].apply_buff(defender["stats"], "buff_filter_require_shield_absorbed_apply_buff", int(defender["id"]))
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var shield_id := int(ds.stat_id("SHIELD"))
	# 1) 无护盾：不触发
	defender["stats"].add_base(shield_id, 0.0 - float(defender["stats"].get_final(shield_id)))
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 10.0, replay, 1, tags_mask, runtime, 0)
	_log("no shield: attacker.buff_dummy_mark_1 cnt=" + str(_count_instances_by_buff_id(attacker["buffs"], "buff_dummy_mark_1")))

	# 2) 有护盾：触发
	defender["stats"].add_base(shield_id, 50.0 - float(defender["stats"].get_final(shield_id)))
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 10.0, replay, 2, tags_mask, runtime, 0)
	_log("with shield: attacker.buff_dummy_mark_1 cnt=" + str(_count_instances_by_buff_id(attacker["buffs"], "buff_dummy_mark_1")))


func _sc_filters_fire_immunity() -> void:
	# Boss 火焰免疫：element=FIRE 时 final_damage=0（通过 BEFORE_TAKE 设置超大 SHIELD 实现）
	var attacker := _mk_actor(8871)
	var boss := _mk_actor(8872)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(boss["id"])
	var runtime := _mk_runtime([attacker, boss])

	var hit_id := int(ds.stat_id("HIT_RATE"))
	var evade_id := int(ds.stat_id("EVADE"))
	attacker["stats"].add_base(hit_id, 1.0 - float(attacker["stats"].get_final(hit_id)))
	boss["stats"].add_base(evade_id, 0.0 - float(boss["stats"].get_final(evade_id)))

	boss["buffs"].apply_buff(boss["stats"], "buff_boss_fire_immunity", int(boss["id"]))
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var el_fire := int(enums_rt.enum_int("element", "FIRE"))
	var dt_magic := int(enums_rt.enum_int("damage_type", "MAGIC"))
	var ctx = pipe.deal_damage(attacker["stats"], boss["stats"], attacker["buffs"], boss["buffs"], ds, 10.0, replay, 1, tags_mask, runtime, 0, -1, dt_magic, el_fire)
	_log("fire damage: final_damage=" + str(float(ctx.final_damage)) + " absorbed_shield=" + str(float(ctx.get_meta("absorbed_shield"))))


func _sc_filters_skill_id() -> void:
	var attacker := _mk_actor(8881)
	var defender := _mk_actor(8882)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])

	var hit_id := int(ds.stat_id("HIT_RATE"))
	var evade_id := int(ds.stat_id("EVADE"))
	attacker["stats"].add_base(hit_id, 1.0 - float(attacker["stats"].get_final(hit_id)))
	defender["stats"].add_base(evade_id, 0.0 - float(defender["stats"].get_final(evade_id)))

	defender["buffs"].apply_buff(defender["stats"], "buff_filter_skill_id_apply_mark", int(defender["id"]))
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# skill_id=1001：触发
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 10.0, replay, 1, tags_mask, runtime, 0, 1001)
	_log("skill_id=1001 mark cnt=" + str(_count_instances_by_buff_id(attacker["buffs"], "buff_dummy_mark_1")))

	# skill_id=2002：不触发（先移除 mark）
	attacker["buffs"].remove_by_buff_id(attacker["stats"], "buff_dummy_mark_1", "ALL")
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 10.0, replay, 2, tags_mask, runtime, 0, 2002)
	_log("skill_id=2002 mark cnt=" + str(_count_instances_by_buff_id(attacker["buffs"], "buff_dummy_mark_1")))


func _sc_filters_min_absorbed_shield() -> void:
	var attacker := _mk_actor(8891)
	var defender := _mk_actor(8892)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])

	var hit_id := int(ds.stat_id("HIT_RATE"))
	var evade_id := int(ds.stat_id("EVADE"))
	attacker["stats"].add_base(hit_id, 1.0 - float(attacker["stats"].get_final(hit_id)))
	defender["stats"].add_base(evade_id, 0.0 - float(defender["stats"].get_final(evade_id)))

	defender["buffs"].apply_buff(defender["stats"], "buff_filter_min_absorbed_shield_apply_mark", int(defender["id"]))
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var shield_id := int(ds.stat_id("SHIELD"))

	# A) shield=10, dmg=10 => absorbed=10 < 20，不触发
	defender["stats"].add_base(shield_id, 10.0 - float(defender["stats"].get_final(shield_id)))
	var ctx1 = pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 10.0, replay, 1, tags_mask, runtime, 0, 1001)
	_log("A absorbed=" + str(float(ctx1.get_meta("absorbed_shield"))) + " mark cnt=" + str(_count_instances_by_buff_id(attacker["buffs"], "buff_dummy_mark_1")))

	# B) shield=50, dmg=30 => absorbed=30 >= 20，触发
	attacker["buffs"].remove_by_buff_id(attacker["stats"], "buff_dummy_mark_1", "ALL")
	defender["stats"].add_base(shield_id, 50.0 - float(defender["stats"].get_final(shield_id)))
	var ctx2 = pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 30.0, replay, 2, tags_mask, runtime, 0, 1001)
	_log("B absorbed=" + str(float(ctx2.get_meta("absorbed_shield"))) + " mark cnt=" + str(_count_instances_by_buff_id(attacker["buffs"], "buff_dummy_mark_1")))


func _sc_action_heal() -> void:
	var attacker := _mk_actor(9001)
	var defender := _mk_actor(9002)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var hp_id: int = int(ds.stat_id("HP"))

	# 先扣点血
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 20.0, replay, 1, tags_mask, runtime, 0)
	_log("before heal HP=" + str(float(defender["stats"].get_final(hp_id))))

	defender["buffs"].apply_buff(defender["stats"], "buff_action_heal_30", int(defender["id"]))
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 0.0, replay, 2, tags_mask, runtime, 0)
	_log("after heal HP=" + str(float(defender["stats"].get_final(hp_id))))


func _sc_action_add_shield() -> void:
	var attacker := _mk_actor(9011)
	var defender := _mk_actor(9012)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var shield_id: int = int(ds.stat_id("SHIELD"))

	defender["buffs"].apply_buff(defender["stats"], "buff_action_add_shield_50", int(defender["id"]))
	var ctx = pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 30.0, replay, 1, tags_mask, runtime, 0)
	var absorbed := 0.0
	if ctx.has_meta("absorbed_shield"):
		absorbed = float(ctx.get_meta("absorbed_shield"))
	_log("after hit SHIELD=" + str(float(defender["stats"].get_final(shield_id))) + " absorbed=" + str(absorbed))


func _sc_action_dispel_debuff() -> void:
	var attacker := _mk_actor(9021)
	var defender := _mk_actor(9022)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 先挂一个 DOT（DEBUFF）
	defender["buffs"].apply_buff(defender["stats"], "buff_dot_fire_3t", int(attacker["id"]))
	_log("before dispel dot cnt=" + str(_count_instances_by_buff_id(defender["buffs"], "buff_dot_fire_3t")))

	defender["buffs"].apply_buff(defender["stats"], "buff_action_dispel_debuff", int(defender["id"]))
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 0.0, replay, 1, tags_mask, runtime, 0)
	_log("after dispel dot cnt=" + str(_count_instances_by_buff_id(defender["buffs"], "buff_dot_fire_3t")))


func _sc_action_lifesteal() -> void:
	var attacker := _mk_actor(9031)
	var defender := _mk_actor(9032)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var hp_id: int = int(ds.stat_id("HP"))

	# attacker 先掉血
	attacker["stats"].add_base(hp_id, -50.0)
	_log("before lifesteal attacker.HP=" + str(float(attacker["stats"].get_final(hp_id))))

	attacker["buffs"].apply_buff(attacker["stats"], "buff_action_lifesteal_20p", int(attacker["id"]))
	var ctx = pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 30.0, replay, 1, tags_mask, runtime, 0)
	_log("damage.final=" + str(float(ctx.final_damage)) + " after lifesteal attacker.HP=" + str(float(attacker["stats"].get_final(hp_id))))


func _sc_action_reflect() -> void:
	var attacker := _mk_actor(9041)
	var defender := _mk_actor(9042)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var hp_id: int = int(ds.stat_id("HP"))

	defender["buffs"].apply_buff(defender["stats"], "buff_action_reflect_30p", int(defender["id"]))
	var hp0 := float(attacker["stats"].get_final(hp_id))
	var ctx = pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 40.0, replay, 1, tags_mask, runtime, 0)
	_log("damage.final=" + str(float(ctx.final_damage)) + " attacker.HP " + str(hp0) + " -> " + str(float(attacker["stats"].get_final(hp_id))))


func _sc_command_cancel_escape() -> void:
	var actor := _mk_actor(9051)
	_hud_attacker_id = int(actor["id"])
	_hud_defender_id = -1
	var runtime := _mk_runtime([actor])

	actor["buffs"].apply_buff(actor["stats"], "buff_cmd_cancel_escape", int(actor["id"]))

	var ctx := CommandContext.new()
	ctx.actor_id = int(actor["id"])
	ctx.command_kind = "ESCAPE"
	ctx.set_meta("runtime", runtime)

	actor["buffs"].emit_event("COMMAND", "CMD_BEFORE", ctx)
	_log("escape canceled? " + str(bool(ctx.cancel)))


func _sc_command_basic_attack_tag() -> void:
	var actor := _mk_actor(9061)
	_hud_attacker_id = int(actor["id"])
	_hud_defender_id = -1
	var runtime := _mk_runtime([actor])

	actor["buffs"].apply_buff(actor["stats"], "buff_cmd_basic_attack_mark", int(actor["id"]))

	var ctx := CommandContext.new()
	ctx.actor_id = int(actor["id"])
	ctx.command_kind = "ATTACK"
	ctx.skill_id = 1001
	ctx.tags_mask = int(enums_rt.tag_mask(["BASIC_ATTACK"]))
	ctx.set_meta("runtime", runtime)

	actor["buffs"].emit_event("COMMAND", "CMD_AFTER", ctx)
	_log("mark cnt=" + str(_count_instances_by_buff_id(actor["buffs"], "buff_dummy_mark_1")))


func _sc_command_use_item() -> void:
	var actor := _mk_actor(9071)
	_hud_attacker_id = int(actor["id"])
	_hud_defender_id = -1
	var runtime := _mk_runtime([actor])

	actor["buffs"].apply_buff(actor["stats"], "buff_cmd_use_item_mark", int(actor["id"]))

	var ctx := CommandContext.new()
	ctx.actor_id = int(actor["id"])
	ctx.command_kind = "USE_ITEM"
	ctx.item_id = 2001
	ctx.set_meta("runtime", runtime)

	actor["buffs"].emit_event("COMMAND", "CMD_AFTER", ctx)
	_log("item 2001 mark cnt=" + str(_count_instances_by_buff_id(actor["buffs"], "buff_dummy_mark_1")))


func _sc_executor_attack_basic() -> void:
	var exec := BattleExecutor.new()
	var attacker := _mk_actor(9301)
	var defender := _mk_actor(9302)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])

	# attacker：普攻加成（DAMAGE/BEFORE_DEAL + BASIC_ATTACK）
	attacker["buffs"].apply_buff(attacker["stats"], "buff_basic_attack_add_base_5", int(attacker["id"]))

	var cmd := CommandContext.new()
	cmd.actor_id = int(attacker["id"])
	cmd.command_kind = "ATTACK"
	cmd.targets = PackedInt32Array([int(defender["id"])])
	cmd.skill_id = 1 # rpg_tests/skill_basic_attack_1（按 skill_defs.skills 索引）

	var res = exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, replay)
	if res.last_damage_ctx != null:
		_log("damage.base=" + str(float(res.last_damage_ctx.base_damage)) + " final=" + str(float(res.last_damage_ctx.final_damage)))
	else:
		_log("[ERROR] no damage ctx")


func _sc_executor_escape_cancel() -> void:
	var exec := BattleExecutor.new()
	var actor := _mk_actor(9311)
	_hud_attacker_id = int(actor["id"])
	_hud_defender_id = -1
	var runtime := _mk_runtime([actor])

	actor["buffs"].apply_buff(actor["stats"], "buff_cmd_cancel_escape", int(actor["id"]))

	var cmd := CommandContext.new()
	cmd.actor_id = int(actor["id"])
	cmd.command_kind = "ESCAPE"

	var res = exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, replay)
	_log("escape canceled=" + str(bool(res.canceled)) + " escaped=" + str(bool(res.escaped)))


func _sc_executor_multihit_triple_slash() -> void:
	var exec := BattleExecutor.new()
	var attacker := _mk_actor(9321)
	var defender := _mk_actor(9322)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])

	var cmd := CommandContext.new()
	cmd.actor_id = int(attacker["id"])
	cmd.command_kind = "CAST_SKILL"
	cmd.targets = PackedInt32Array([int(defender["id"])])
	cmd.skill_id = 0 # rpg_tests/skill_triple_slash（按 skill_defs.skills 索引）

	var dmg_from := replay.damage_traces.size()
	exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, replay)
	var dmg_to := replay.damage_traces.size()
	_log("damage traces +" + str(dmg_to - dmg_from))
	if dmg_to > dmg_from:
		_log(replay.debug_dump_damage_range(dmg_from))


func _sc_executor_multitarget_all() -> void:
	var exec := BattleExecutor.new()
	var attacker := _mk_actor(9331)
	var a := _mk_actor(9333)
	var b := _mk_actor(9332) # 故意乱序输入 targets
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(a["id"])
	var runtime := _mk_runtime([attacker, a, b])

	var cmd := CommandContext.new()
	cmd.actor_id = int(attacker["id"])
	cmd.command_kind = "CAST_SKILL"
	cmd.targets = PackedInt32Array([int(a["id"]), int(b["id"])])
	cmd.skill_id = 2 # rpg_tests/skill_whirlwind（按 skill_defs.skills 索引）

	var dmg_from := replay.damage_traces.size()
	exec.execute_command(1, cmd, runtime, ds, enums_rt, pipe, sources, replay)
	var dmg_to := replay.damage_traces.size()
	_log("damage traces +" + str(dmg_to - dmg_from))
	if dmg_to > dmg_from:
		_log(replay.debug_dump_damage_range(dmg_from))


func _sc_event_chance_apply_determinism() -> void:
	# 复刻 tests/rpg/test_event_chance_apply_buff_determinism.gd 的核心：展示 seed/roll 与实际 apply 是否一致，并重复一次验证一致性
	var attacker_id: int = 9101
	var defender_id: int = 9102
	var turn_index: int = 123
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	var r1: Dictionary = _chance_apply_run_once(attacker_id, defender_id, turn_index, tags_mask)
	var r2: Dictionary = _chance_apply_run_once(attacker_id, defender_id, turn_index, tags_mask)
	_log("run1: inst=%s seed=%s roll=%.6f expected=%s actual=%s" % [r1["inst_id"], r1["seed"], float(r1["roll"]), r1["expected"], r1["actual"]])
	_log("run2: inst=%s seed=%s roll=%.6f expected=%s actual=%s" % [r2["inst_id"], r2["seed"], float(r2["roll"]), r2["expected"], r2["actual"]])
	_log("deterministic? " + str(int(r1["seed"]) == int(r2["seed"]) and is_equal_approx(float(r1["roll"]), float(r2["roll"])) and bool(r1["actual"]) == bool(r2["actual"])))


func _chance_apply_run_once(attacker_id: int, defender_id: int, turn_index: int, tags_mask: int) -> Dictionary:
	var attacker := _mk_actor(attacker_id)
	var defender := _mk_actor(defender_id)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])

	# 固定命中/暴击，避免随机性影响事件触发（只测 CHANCE_APPLY_BUFF）
	var hit_id: int = int(ds.stat_id("HIT_RATE"))
	var crit_id: int = int(ds.stat_id("CRIT_RATE"))
	var eva_id: int = int(ds.stat_id("EVADE"))
	attacker["stats"].add_base(hit_id, 1.0 - float(attacker["stats"].get_final(hit_id)))
	attacker["stats"].add_base(crit_id, 0.0 - float(attacker["stats"].get_final(crit_id)))
	defender["stats"].add_base(eva_id, 0.0 - float(defender["stats"].get_final(eva_id)))

	var inst_id: int = int(attacker["buffs"].apply_buff(attacker["stats"], "buff_event_chance_apply_dot_50", attacker_id))
	var ctx = pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 30.0, null, turn_index, tags_mask, runtime, 0)
	var seed: int = int(attacker["buffs"]._event_seed(ctx, inst_id))
	var roll: float = float(attacker["buffs"]._roll01(seed))
	var expected: bool = roll < 0.5
	var actual: bool = (_count_instances_by_buff_id(defender["buffs"], "buff_dot_fire_3t") > 0)
	return {"inst_id": inst_id, "seed": seed, "roll": roll, "expected": expected, "actual": actual}


func _advance_to_next_turn_start(ids_sorted: PackedInt32Array, runtime: Dictionary) -> void:
	# TurnEnd 推进回合号（不结算 TURN_START DOT），再 TurnStart 结算 DOT
	turn.on_turn_end(ids_sorted, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	turn.on_turn_start(ids_sorted, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)


func _sc_dot_actions_mul_set_clear() -> void:
	# 合并展示 MUL / SET / ADD(-1) / CLEAR(tag=POISON)
	var attacker := _mk_actor(8111)
	var defender := _mk_actor(8112)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])
	var ids := _ids_sorted([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 固定命中/暴击 + 让 direct hit 不扣血：base_damage=0 且 ATK==DEF
	var hit_id: int = int(ds.stat_id("HIT_RATE"))
	var crit_id: int = int(ds.stat_id("CRIT_RATE"))
	var eva_id: int = int(ds.stat_id("EVADE"))
	var atk_id: int = int(ds.stat_id("ATK"))
	var def_id: int = int(ds.stat_id("DEF"))
	attacker["stats"].add_base(hit_id, 1.0 - float(attacker["stats"].get_final(hit_id)))
	attacker["stats"].add_base(crit_id, 0.0 - float(attacker["stats"].get_final(crit_id)))
	defender["stats"].add_base(eva_id, 0.0 - float(defender["stats"].get_final(eva_id)))
	attacker["stats"].add_base(atk_id, 10.0 - float(attacker["stats"].get_final(atk_id)))
	defender["stats"].add_base(def_id, 10.0 - float(defender["stats"].get_final(def_id)))

	# 1) defender 挂可叠层 FIRE DOT（stacks=1, turns=3）
	defender["buffs"].apply_buff(defender["stats"], "buff_dot_fire_stack_3t", int(attacker["id"]))
	# 2) attacker 命中后将目标 DOT stacks *2，并刷新 turns
	attacker["buffs"].apply_buff(attacker["stats"], "buff_on_hit_dot_mul2", int(attacker["id"]))
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 0.0, replay, turn.turn_index, tags_mask, runtime, 0)
	_log("after DOT_MUL trigger: defender buffs:")
	_log(defender["buffs"].debug_dump_instances())

	# tick 一次，观察 dot trace base_damage（应该翻倍）
	var dot_from: int = int(replay.dot_traces.size())
	_advance_to_next_turn_start(ids, runtime)
	_log("after TurnStart tick: dot_traces+=" + str(int(replay.dot_traces.size()) - dot_from))
	_log(replay.debug_dump_dot_range(dot_from))

	# 3) SET=3
	attacker["buffs"].apply_buff(attacker["stats"], "buff_on_hit_dot_set3", int(attacker["id"]))
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 0.0, replay, turn.turn_index, tags_mask, runtime, 0)
	_log("after DOT_SET trigger: defender buffs:")
	_log(defender["buffs"].debug_dump_instances())

	# 4) ADD(-1) 清除（stacks 可能到 0）
	attacker["buffs"].apply_buff(attacker["stats"], "buff_on_hit_dot_add_minus1", int(attacker["id"]))
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 0.0, replay, turn.turn_index, tags_mask, runtime, 0)
	_log("after DOT_ADD(-1) trigger: defender buffs:")
	_log(defender["buffs"].debug_dump_instances())

	# 5) CLEAR(tag=POISON)：先挂 FIRE+POISON，再 clear POISON
	defender["buffs"].apply_buff(defender["stats"], "buff_dot_fire_stack_3t", int(attacker["id"]))
	defender["buffs"].apply_buff(defender["stats"], "buff_dot_poison_3t", int(attacker["id"]))
	attacker["buffs"].apply_buff(attacker["stats"], "buff_on_hit_dot_clear_poison", int(attacker["id"]))
	pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 0.0, replay, turn.turn_index, tags_mask, runtime, 0)
	_log("after CLEAR(POISON) trigger: defender buffs:")
	_log(defender["buffs"].debug_dump_instances())


func _sc_roll_key() -> void:
	var attacker := _mk_actor(9701)
	var defender := _mk_actor(9702)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 确保必中/可暴击
	var hit_id: int = int(ds.stat_id("HIT_RATE"))
	var eva_id: int = int(ds.stat_id("EVADE"))
	var crit_id: int = int(ds.stat_id("CRIT_RATE"))
	var crit_dmg_id: int = int(ds.stat_id("CRIT_DMG"))
	attacker["stats"].add_base(hit_id, 1.0 - float(attacker["stats"].get_final(hit_id)))
	attacker["stats"].add_base(crit_id, 0.5 - float(attacker["stats"].get_final(crit_id)))
	attacker["stats"].add_base(crit_dmg_id, 1.0 - float(attacker["stats"].get_final(crit_dmg_id)))
	defender["stats"].add_base(eva_id, 0.0 - float(defender["stats"].get_final(eva_id)))

	var turn_index: int = 777
	var ctx1 = pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 12.0, replay, turn_index, tags_mask, runtime, 1001)
	var ctx2 = pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, 12.0, replay, turn_index, tags_mask, runtime, 1002)
	_log("ctx1 hit=%s crit=%s roll_key=1001" % [ctx1.hit, ctx1.crit])
	_log("ctx2 hit=%s crit=%s roll_key=1002" % [ctx2.hit, ctx2.crit])


func _sc_multihit_each_hit_dot() -> void:
	var attacker := _mk_actor(9301)
	var defender := _mk_actor(9302)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# attacker 三连：每段 AFTER_DEAL 挂 DOT（require_hit=true 的版本更符合语义）
	attacker["buffs"].apply_buff(attacker["stats"], "buff_on_hit_apply_dot_require_hit", int(attacker["id"]))

	# 强制必中
	var hit_id: int = int(ds.stat_id("HIT_RATE"))
	var eva_id: int = int(ds.stat_id("EVADE"))
	attacker["stats"].add_base(hit_id, 1.0 - float(attacker["stats"].get_final(hit_id)))
	defender["stats"].add_base(eva_id, 0.0 - float(defender["stats"].get_final(eva_id)))

	var base_hits := [12.0, 14.0, 18.0]
	for i in range(base_hits.size()):
		pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, float(base_hits[i]), replay, 200 + i, tags_mask, runtime, i)
	_log("defender DOT instances=" + str(_count_instances_by_buff_id(defender["buffs"], "buff_dot_fire_3t")))
	_log(defender["buffs"].debug_dump_instances())


func _sc_aoe_multitarget_multihit() -> void:
	# 复刻测试语义：3段 * 2目标；目标A必中；目标B必miss；每段命中挂DOT
	var attacker := _mk_actor(9601)
	var def_a := _mk_actor(9602)
	var def_b := _mk_actor(9603)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(def_a["id"])
	var runtime := _mk_runtime([attacker, def_a, def_b])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# attacker: HIT=1, CRIT=0.5
	var hit_id: int = int(ds.stat_id("HIT_RATE"))
	var crit_id: int = int(ds.stat_id("CRIT_RATE"))
	var crit_dmg_id: int = int(ds.stat_id("CRIT_DMG"))
	attacker["stats"].add_base(hit_id, 1.0 - float(attacker["stats"].get_final(hit_id)))
	attacker["stats"].add_base(crit_id, 0.5 - float(attacker["stats"].get_final(crit_id)))
	attacker["stats"].add_base(crit_dmg_id, 1.0 - float(attacker["stats"].get_final(crit_dmg_id)))

	# A: EVADE=0；B: EVADE=1
	var eva_id: int = int(ds.stat_id("EVADE"))
	def_a["stats"].add_base(eva_id, 0.0 - float(def_a["stats"].get_final(eva_id)))
	def_b["stats"].add_base(eva_id, 1.0 - float(def_b["stats"].get_final(eva_id)))

	attacker["buffs"].apply_buff(attacker["stats"], "buff_on_hit_apply_dot_require_hit", int(attacker["id"]))

	var base_hits := [12.0, 14.0, 18.0]
	var targets := [def_a, def_b]
	for seg in range(base_hits.size()):
		var turn_index: int = 300 + seg
		for ti in range(targets.size()):
			var t: Dictionary = targets[ti]
			var ctx = pipe.deal_damage(attacker["stats"], t["stats"], attacker["buffs"], t["buffs"], ds, float(base_hits[seg]), replay, turn_index, tags_mask, runtime, (seg << 8) | ti)
			_log("seg=%s target=%s hit=%s crit=%s final=%s" % [seg + 1, int(t["id"]), ctx.hit, ctx.crit, ctx.final_damage])

	_log("def_a DOT instances=" + str(_count_instances_by_buff_id(def_a["buffs"], "buff_dot_fire_3t")))
	_log("def_b DOT instances=" + str(_count_instances_by_buff_id(def_b["buffs"], "buff_dot_fire_3t")))

	# 结算一次 TURN_START DOT（按来源合并：def_a 仅 1 条 dot trace；def_b 无）
	var ids := _ids_sorted([attacker, def_a, def_b])
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	var dot_from: int = int(replay.dot_traces.size())
	turn.on_turn_start(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	_log("dot_traces delta=" + str(int(replay.dot_traces.size()) - dot_from))


func _sc_full_turn_script_battle() -> void:
	# 复刻 tests/rpg/test_full_turn_script_battle.gd 的语义（TURN_START DOT + dispel + immunity）
	var attacker := _mk_actor(9001)
	var defender := _mk_actor(9002)
	_hud_attacker_id = int(attacker["id"])
	_hud_defender_id = int(defender["id"])
	var runtime := _mk_runtime([attacker, defender])
	var ids := _ids_sorted([attacker, defender])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# attacker deterministic: HIT=1, CRIT=0
	var hit_id: int = int(ds.stat_id("HIT_RATE"))
	var crit_id: int = int(ds.stat_id("CRIT_RATE"))
	attacker["stats"].add_base(hit_id, 1.0 - float(attacker["stats"].get_final(hit_id)))
	attacker["stats"].add_base(crit_id, 0.0 - float(attacker["stats"].get_final(crit_id)))

	var hp_id: int = int(ds.stat_id("HP"))
	var shield_id: int = int(ds.stat_id("SHIELD"))

	# Turn1: defender shield
	defender["buffs"].apply_buff(defender["stats"], "buff_shield_50", int(defender["id"]))
	_log("Turn1: shield=" + str(float(defender["stats"].get_final(shield_id))) + " hp=" + str(float(defender["stats"].get_final(hp_id))))
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

	# Turn2: attacker multihit apply DOT
	attacker["buffs"].apply_buff(attacker["stats"], "buff_on_hit_apply_dot", int(attacker["id"]))
	var base_hits := [12.0, 14.0, 18.0]
	for i in range(base_hits.size()):
		pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, float(base_hits[i]), replay, 200 + i, tags_mask, runtime, i)
	_log("Turn2: defender DOT instances=" + str(_count_instances_by_buff_id(defender["buffs"], "buff_dot_fire_3t")))
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

	# Turn3 start: DOT tick (1 trace per source)
	var hp_before: float = float(defender["stats"].get_final(hp_id))
	var dot_from: int = int(replay.dot_traces.size())
	turn.on_turn_start(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	_log("Turn3 start: dot_traces+=" + str(int(replay.dot_traces.size()) - dot_from) + " hp " + str(hp_before) + "->" + str(float(defender["stats"].get_final(hp_id))))

	# Turn3: dispel DEBUFF success (remove DOT)
	var removed: int = int(defender["buffs"].dispel_by_tag(defender["stats"], "DEBUFF", false))
	_log("Turn3: dispel DEBUFF removed=" + str(removed) + " remaining DOT=" + str(_count_instances_by_buff_id(defender["buffs"], "buff_dot_fire_3t")))
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

	# Turn4 start: no DOT tick
	dot_from = int(replay.dot_traces.size())
	turn.on_turn_start(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	_log("Turn4 start: dot_traces+=" + str(int(replay.dot_traces.size()) - dot_from))

	# Turn4: apply dots again; set dispel immunity; dispel should fail
	for i in range(base_hits.size()):
		pipe.deal_damage(attacker["stats"], defender["stats"], attacker["buffs"], defender["buffs"], ds, float(base_hits[i]), replay, 400 + i, tags_mask, runtime, i)
	defender["buffs"].target_dispel_immunity_mask |= int(enums_rt.tag_mask(["DEBUFF"]))
	removed = int(defender["buffs"].dispel_by_tag(defender["stats"], "DEBUFF", false))
	_log("Turn4: dispel with immunity removed=" + str(removed) + " remaining DOT=" + str(_count_instances_by_buff_id(defender["buffs"], "buff_dot_fire_3t")))
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)

	# Turn5 start: DOT ticks again
	dot_from = int(replay.dot_traces.size())
	turn.on_turn_start(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	_log("Turn5 start: dot_traces+=" + str(int(replay.dot_traces.size()) - dot_from))
