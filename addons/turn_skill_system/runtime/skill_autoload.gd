extends Node
class_name SkillAutoload

## Autoload 运行时上下文容器（插件启用时安装到 ProjectSettings → Autoload）。
##
## 说明：
## - SkillRuntime 的静态入口会优先尝试使用该 Autoload，以实现业务侧“零注入一行 cast”
## - 在单元测试/离线模拟中，也允许绕过 Autoload，直接 new 各模块并从 extra 注入

const SkillDB := preload("res://addons/turn_skill_system/runtime/skill_db.gd")
const BattleEventBus := preload("res://addons/turn_skill_system/runtime/battle_event_bus.gd")
const TargetingRegistry := preload("res://addons/turn_skill_system/runtime/targeting/targeting_registry.gd")
const EffectRegistry := preload("res://addons/turn_skill_system/runtime/effects/effect_registry.gd")
const OmniBuffAdapter := preload("res://addons/turn_skill_system/runtime/omni_buff_adapter.gd")
const PassiveManager := preload("res://addons/turn_skill_system/runtime/passive_manager.gd")
const AuraManager := preload("res://addons/turn_skill_system/runtime/aura_manager.gd")
const Grid := preload("res://addons/turn_skill_system/runtime/grid.gd")

var db: SkillDB
var event_bus: BattleEventBus
var targeting: TargetingRegistry
var effects: EffectRegistry
var omnibuff: OmniBuffAdapter
var passive_manager: PassiveManager
var aura_manager: AuraManager
var grid: Grid

func ensure_ready() -> void:
	if db != null:
		return

	db = SkillDB.new()
	db.reload_index()

	event_bus = BattleEventBus.new()

	targeting = TargetingRegistry.new()
	targeting.register_defaults()

	effects = EffectRegistry.new()
	effects.register_defaults()

	omnibuff = OmniBuffAdapter.new()
	passive_manager = PassiveManager.new()
	aura_manager = AuraManager.new()

	grid = Grid.new()

	# 默认绑定（dataset/runtime_dict 由业务侧在战斗开始时 setup）
	passive_manager.bind(event_bus, db, effects, omnibuff, grid)
	aura_manager.bind(event_bus, db, effects, omnibuff, grid)
