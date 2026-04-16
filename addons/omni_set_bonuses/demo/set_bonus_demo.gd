extends Control

## 演示：换装 → 调用 OmniSetBonusManager.refresh_entity → 属性面板读取最终 ATK
##
## 打开场景：res://addons/omni_set_bonuses/demo/set_bonus_demo.tscn
## 点击按钮切换 0/2pc/4pc，观察 ATK 文本变化。

const ManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const EnumsRuntime = preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")
const DatasetCompiler = preload("res://addons/omnibuff/config/compiler/dataset_compiler.gd")
const StatsComponent = preload("res://addons/omnibuff/runtime/components/stats_component.gd")
const BuffCore = preload("res://addons/omnibuff/runtime/core/buff_core.gd")

const SetBonusManager = preload("res://addons/omni_set_bonuses/runtime/set_bonus_manager.gd")

@onready var atk_label: Label = %AtkLabel
@onready var btn_none: Button = %BtnNone
@onready var btn_2pc: Button = %Btn2pc
@onready var btn_4pc: Button = %Btn4pc

var ds: OmniCompiledDataset
var enums_rt: OmniEnumsRuntime
var stats: OmniStatsComponent
var buffs: OmniBuffCore
var mgr: OmniSetBonusManager

var set_defs: Dictionary = {"dragon": {2: "set_dragon_2pc", 4: "set_dragon_4pc"}}
var items0: Array = []
var items2: Array = [
	{"item_id": "slot1", "set_id": "dragon"},
	{"item_id": "slot2", "set_id": "dragon"}
]
var items4: Array = [
	{"item_id": "slot1", "set_id": "dragon"},
	{"item_id": "slot2", "set_id": "dragon"},
	{"item_id": "slot3", "set_id": "dragon"},
	{"item_id": "slot4", "set_id": "dragon"}
]


func _ready() -> void:
	_init_runtime()

	btn_none.pressed.connect(func(): _apply_items(items0))
	btn_2pc.pressed.connect(func(): _apply_items(items2))
	btn_4pc.pressed.connect(func(): _apply_items(items4))

	_apply_items(items0)


func _init_runtime() -> void:
	# 用 rpg_tests 数据集做演示（项目内置，便于直接打开跑）
	var res = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	if not res.issues.is_empty():
		for i in res.issues:
			push_warning("[Demo] dataset issue: " + String(i.message))

	enums_rt = EnumsRuntime.from_enums_json(res.enums)
	ds = DatasetCompiler.compile(res.manifest, enums_rt, res.sources)

	stats = StatsComponent.new(9001, ds)
	buffs = BuffCore.new(ds, enums_rt)
	mgr = SetBonusManager.new()


func _apply_items(equipped_items: Array) -> void:
	# 关键点：换装发生时调用 refresh_entity（幂等、只做 diff）
	mgr.refresh_entity(stats, buffs, equipped_items, set_defs, int(stats.entity_id))

	var atk_id: int = int(ds.stat_id("ATK"))
	var v: float = float(stats.get_final(atk_id))
	atk_label.text = "ATK = %.3f" % v

