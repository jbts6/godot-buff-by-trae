extends Node

## OmniBuff 单例（Autoload 入口，命名空间式用法）
##
## 目标：
## - “启用插件” -> 自动向宿主项目添加 Autoload：OmniBuff
## - “禁用插件” -> 自动移除该 Autoload：OmniBuff
## - 代码侧通过 `OmniBuff.Xxx` 访问运行时脚本资源（类似命名空间）
##
## 示例：
##   var replay := OmniBuff.Replay.new()
##   var buffs := OmniBuff.BuffCore.new(ds, enums_rt)
##
## 说明：
## - 这里暴露的是 Script 资源（preload 返回的类），不是实例。
## - 之所以用 preload 而不是依赖 class_name：
##   - 避免 Godot 全局类表/缓存时机不确定导致的解析期报错。
## - 插件使用方建议：
##   - 业务代码里尽量通过 `OmniBuff.Xxx` / preload 引用脚本，不要直接写 `class_name` 标识符（例如 OmniExprContext），
##     以避免在“插件未加载完全/脚本未被解析”时出现编译错误。
##   - 对 `DamagePipeline.deal_damage()`：若你更在意 API 兼容性（插件升级不炸），建议优先使用 `deal_damage_v1()`（旧签名兼容层），
##     而不是到处用位置参数直接调用 `deal_damage(...)`（未来可能继续演进签名）。

# --- Runtime Core ---
const EnumsRuntime := preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")
const CompiledDataset := preload("res://addons/omnibuff/runtime/core/compiled_data.gd")
const StatsCore := preload("res://addons/omnibuff/runtime/core/stats_core.gd")
const CommandContext := preload("res://addons/omnibuff/runtime/core/command_context.gd")
const EventIndex := preload("res://addons/omnibuff/runtime/core/event_index.gd")
const BuffCore := preload("res://addons/omnibuff/runtime/core/buff_core.gd")
const BattleExecutor := preload("res://addons/omnibuff/runtime/core/battle_executor.gd")
const DamagePipeline := preload("res://addons/omnibuff/runtime/core/damage_pipeline.gd")
const Replay := preload("res://addons/omnibuff/runtime/core/replay.gd")
const ExprContext := preload("res://addons/omnibuff/runtime/core/expr_context.gd")

# --- Runtime Components ---
const StatsComponent := preload("res://addons/omnibuff/runtime/components/stats_component.gd")
const TurnComponent := preload("res://addons/omnibuff/runtime/components/turn_component.gd")

# --- Config / Compiler ---
const Json := preload("res://addons/omnibuff/config/parsers/json_reader.gd")
const Csv := preload("res://addons/omnibuff/config/parsers/csv_reader.gd")
const Validate := preload("res://addons/omnibuff/config/compiler/validators.gd")
const Migrate := preload("res://addons/omnibuff/config/compiler/migrate.gd")
const ManifestLoader := preload("res://addons/omnibuff/config/manifest_loader.gd")
const DatasetCompiler := preload("res://addons/omnibuff/config/compiler/dataset_compiler.gd")

func _ready() -> void:
	# 单例不承载逻辑，仅作为“命名空间入口”。
	pass
