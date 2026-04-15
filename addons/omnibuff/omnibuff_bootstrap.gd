extends Node

## OmniBuffBootstrap（工程侧 Autoload 单例）
##
## 背景：
## - Godot 的 `class_name` 全局类表由编辑器扫描/缓存生成。
## - 在真实项目/插件开发过程中，可能出现“脚本已存在但全局类尚未被缓存”的情况，
##   导致其它脚本在解析阶段引用 `OmniReplay` 等类时报：
##   `Identifier "<ClassName>" not declared in the current scope.`
##
## 解决策略：
## - 由工程侧添加一个 Autoload（单例）脚本，在启动时 `preload()` 所有插件脚本资源，
##   强制它们被 Godot 解析/加载，从而最大限度避免“全局类缺失/缓存不同步”导致的解析问题。
##
## 注意：
## - 这不是运行时必需逻辑，仅用于“工程集成稳定性”与“开发期抗缓存问题”。
## - 生产项目中仍建议：跨模块依赖使用 `preload("res://...")` 或显式依赖注入，
##   不要完全依赖 class_name 的全局可见性。

# --- Config / Compiler ---
const OmniJson = preload("res://addons/omnibuff/config/parsers/json_reader.gd")
const OmniCsv = preload("res://addons/omnibuff/config/parsers/csv_reader.gd")
const OmniValidate = preload("res://addons/omnibuff/config/compiler/validators.gd")
const OmniMigrate = preload("res://addons/omnibuff/config/compiler/migrate.gd")
const OmniManifestLoader = preload("res://addons/omnibuff/config/manifest_loader.gd")
const OmniDatasetCompiler = preload("res://addons/omnibuff/config/compiler/dataset_compiler.gd")

# --- Runtime Core ---
const OmniEnumsRuntime = preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")
const OmniCompiledDataset = preload("res://addons/omnibuff/runtime/core/compiled_data.gd")
const OmniStatsCore = preload("res://addons/omnibuff/runtime/core/stats_core.gd")
const OmniEventIndex = preload("res://addons/omnibuff/runtime/core/event_index.gd")
const OmniBuffCore = preload("res://addons/omnibuff/runtime/core/buff_core.gd")
const OmniDamagePipeline = preload("res://addons/omnibuff/runtime/core/damage_pipeline.gd")
const OmniReplay = preload("res://addons/omnibuff/runtime/core/replay.gd")

# --- Runtime Components ---
const OmniStatsComponent = preload("res://addons/omnibuff/runtime/components/stats_component.gd")
const OmniTurnComponent = preload("res://addons/omnibuff/runtime/components/turn_component.gd")

func _ready() -> void:
	# 启动时触发一次加载即可；不需要实例化任何对象。
	# 若你希望静默，可删掉该日志。
	print("[OmniBuffBootstrap] loaded omnibuff scripts")
