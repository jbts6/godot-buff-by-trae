class_name OmniLifeContext
extends RefCounted

## 生命周期事件上下文（Phase 1 收尾，最小可用版）
##
## 用途：
## - event_type=LIFE, event_phase=DEATH/REVIVE
## - 由战斗系统在“单位死亡/复活”时组装并发送给 BuffCore.emit_event

## 发生事件的主体（死亡者/复活者）
var actor_id: int = -1

## 事件来源（例如 killer）；没有则 -1
var source_id: int = -1

## 通用 tags_mask（复用 filters.tag_mask_any），例如 HERO/BOSS（由上层战斗系统决定是否使用）
var tags_mask: int = 0

