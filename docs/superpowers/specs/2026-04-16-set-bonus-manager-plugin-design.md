# 套装加成管理器（Set Bonus Manager）插件设计（解耦于 OmniBuff）

## 目标

新增一个独立插件（放在 `addons/` 下），负责“套装是否生效”的判定与下发：

- 输入：装备列表（或任何 build/loadout 配置）、套装配置（set defs）
- 输出：对 `OmniBuffCore` 执行 `apply_buff/remove_by_buff_id`（或按 tag 移除）
- **不侵入 OmniBuff 内部**：不改 buff_core 的计算逻辑、不读取 buff 实例内部结构

换句话说：
- **OmniBuff = What（效果是什么）**
- **SetBonusManager = When（什么时候该拥有这些效果）**

---

## 范围

### In scope
- 统计套装件数（2件/4件/6件…可扩展）
- 通过 diff（应有 vs 现有）做到幂等 apply/remove
- 支持多套装同时生效（不同 set_id）
- 提供最小数据结构与示例，便于业务接入

### Out of scope
- 装备系统本身（穿脱、槽位规则、物品生成）
- UI 面板展示（但可以通过 `StatsComponent.get_final` 读最终值）
- 战斗内临时套装触发（那属于 buff/trigger 域）

---

## 插件形态与目录结构（建议）

新增插件：`addons/omni_set_bonuses/`

```
addons/omni_set_bonuses/
  plugin.cfg                  # 可让 Godot 编辑器识别为插件（可选）
  plugin.gd                   # EditorPlugin（可选：仅注册 autoload / 提供菜单）
  runtime/
    set_bonus_manager.gd      # 核心：纯运行时逻辑（不依赖 Editor）
    set_defs.gd               # set defs 数据结构（类型/校验/工具函数）
  docs/
    README.md                 # 使用方式 + 示例
  tests/
    test_set_bonus_manager.gd # GUT：幂等/diff 行为
```

> 如果你不想引入 EditorPlugin，也可以只提供 runtime/ 脚本；但为了“视为插件”，仍推荐带 `plugin.cfg`。

---

## 数据模型

### 1) 装备输入（由外部系统提供）

SetBonusManager 只要求你能提供以下最小信息：

```gdscript
var equipped_items := [
  {"item_id":"sword_01", "set_id":"dragon"},
  {"item_id":"ring_01",  "set_id":"dragon"},
  {"item_id":"amu_99",   "set_id":"phoenix"}
]
```

约定：
- `set_id` 为空/缺失 ⇒ 不参与套装统计

### 2) 套装定义（set defs）

```gdscript
var set_defs := {
  "dragon": {
    2: "set_dragon_2pc",
    4: "set_dragon_4pc"
  },
  "phoenix": {
    2: "set_phoenix_2pc"
  }
}
```

约定：
- key 是套装 id（String）
- value 是 `{threshold:int -> buff_id:String}` 映射
- threshold 可扩展任意段（2/4/6/8…）

---

## 核心 API（运行时）

文件：`runtime/set_bonus_manager.gd`

### 1) 计算应该激活的 buff 列表

```gdscript
static func compute_active_set_buffs(equipped_items: Array, set_defs: Dictionary) -> PackedStringArray
```

输出：需要激活的 set-buff id（例如：`["set_dragon_2pc","set_dragon_4pc"]`）

### 2) 对某个实体刷新（幂等）

```gdscript
static func refresh_entity(
  stats: OmniStatsComponent,
  buffs: OmniBuffCore,
  equipped_items: Array,
  set_defs: Dictionary,
  source_entity_id: int,
  active_tag: String = "SET_BONUS"
) -> void
```

行为：
- 计算 `desired_buffs`
- 以 tag `SET_BONUS`（或固定前缀）为“管理域”，只对这一域做 add/remove
- 对 `desired_buffs` 中缺失的：`buffs.apply_buff(stats, buff_id, source_entity_id)`
- 对现有但不在 `desired_buffs` 的：`buffs.remove_by_buff_id(stats, buff_id, "ALL", source_entity_id, false, true)`

> 这里使用 `remove_by_buff_id`（BuffCore 现有 API）实现“精确移除”，不需要侵入 Buff 系统。

---

## 约定与最佳实践

1) **套装 buff 建议统一打 tag：`SET_BONUS`**
   - 便于快速识别与清理（例如换装时先清空再补齐也可）
2) **ownership_mode 建议 GLOBAL**（套装属于“状态”，不应叠加）
3) source_entity_id：建议填角色自身 id（用于 remove_by_buff_id 限定来源）

---

## 测试计划（最小集）

新增 GUT：
- 给定 equipped_items 与 set_defs，断言 `compute_active_set_buffs` 输出正确
- refresh 幂等：连续调用 2 次，第二次不应产生额外实例增长（inst_ids 不增长）
- 换装 diff：从 4 件 → 2 件，断言 `set_*_4pc` 被移除、`set_*_2pc` 仍存在

