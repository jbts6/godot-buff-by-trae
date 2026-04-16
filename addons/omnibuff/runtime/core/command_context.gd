class_name OmniCommandContext
extends RefCounted

## 回合制“指令”上下文（Phase 1，最小可用版）
##
## 说明：
## - 用于 COMMAND 事件域（CMD_BEFORE/CMD_AFTER）
## - 由战斗系统组装后发给 BuffCore.emit_event

var actor_id: int
var command_kind: String # ATTACK / CAST_SKILL / USE_ITEM / DEFEND / ESCAPE

var skill_id: int = -1
var item_id: int = -1
var targets: PackedInt32Array = PackedInt32Array()

# 通用 tags_mask（复用 filters.tag_mask_any），例如 BASIC_ATTACK
var tags_mask: int = 0

# 控制流：CMD_BEFORE 阶段可被 CANCEL_COMMAND 置 true
var cancel: bool = false

