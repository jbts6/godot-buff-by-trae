# Omni Set Bonuses（套装加成管理器）

本插件提供一个**完全解耦于 OmniBuff 内部**的“套装加成管理器”：

- 它不理解“装备系统”细节
- 它只根据你给的 `equipped_items`（含 set_id）与 `set_defs`（阈值→buff_id）计算结果
- 然后只调用 OmniBuff 的公开接口：
  - `apply_buff(stats, buff_id, source_entity_id)`
  - `remove_by_buff_id(stats, buff_id, ...)`

---

## 1) 数据结构

### equipped_items（外部系统提供）

```gdscript
var equipped_items := [
  {"item_id":"sword_01", "set_id":"dragon"},
  {"item_id":"ring_01",  "set_id":"dragon"},
  {"item_id":"amu_99",   "set_id":"phoenix"}
]
```

约定：
- `set_id` 缺失或空字符串：不参与套装统计

### set_defs（套装定义）

```gdscript
var set_defs := {
  "dragon": {2: "set_dragon_2pc", 4: "set_dragon_4pc"},
  "phoenix": {2: "set_phoenix_2pc"}
}
```

---

## 2) 用法（幂等刷新）

```gdscript
const SBM = preload("res://addons/omni_set_bonuses/runtime/set_bonus_manager.gd")

var mgr := SBM.new()

# 当装备发生变化时调用一次（不要每帧调用）
mgr.refresh_entity(actor.stats, actor.buffs, equipped_items, set_defs, actor.stats.entity_id)
```

说明：
- 本管理器会在内部缓存“该实体当前激活的套装buff列表”，因此重复调用是幂等的。
- 撤销时使用 `remove_by_buff_id(..., force=true)`，确保套装能被可靠移除。

---

## 3) Demo（演示场景）

打开场景：

- `res://addons/omni_set_bonuses/demo/set_bonus_demo.tscn`

演示内容：
- UI 按钮模拟换装（0/2件/4件）
- 每次点击都会调用 `OmniSetBonusManager.refresh_entity(...)`
- 文本显示 `ATK` 最终值（直接读 `StatsComponent.get_final`）
