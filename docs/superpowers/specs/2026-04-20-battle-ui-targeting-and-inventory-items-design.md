# 战斗 UI（格子点选目标）+ 独立背包/道具系统（战斗内使用）设计 Spec

日期：2026-04-20  
目标：在现有 TurnManager / TurnSkillSystem / OmniBuff / BattleNarrator 的基础上，补齐 **可套 UI 的玩家操作闭环**：  
1) 战斗中可“点技能/点物品 → 格子点选目标 → 确认释放”  
2) **背包/道具系统完全独立**（不复用 skill_db；未来可脱离战斗单独演进）  
3) 道具使用依旧能被战斗播报（BattleNarrator）捕捉并语义化输出  

---

## 1. 范围与非目标

### 1.1 范围（本期做）
- 战斗 UI 最小可玩：
  - 技能列表（来自 SkillDB）与物品列表（来自 Inventory）
  - 格子点击选目标（高亮可选格子）
  - 生成并提交“行动”给 TurnManager
- 独立背包/道具系统（运行时）：
  - ItemDef（道具定义）、Inventory（持有数量/消耗）
  - BattleItemSystem：战斗内使用道具并应用效果
- 播报联动：
  - 道具造成的 heal/damage/apply_buff/remove_buff 也会 emit 对应 battle events（before/after heal/damage、buff_applied/buff_removed）

### 1.2 非目标（本期不做）
- 完整背包 UI（整理、排序、拖拽、装备栏等）
- 复杂物品规则（共享 CD、回合内限制、多目标链式选择等）
- 动画系统/时间轴（仅保留 demo 的节奏延迟能力）

---

## 2. 关键约束（来自现有代码形态）

1) TurnManager 目前以 `TurnCommand(skill_id, primary_cell, extra)` 为主输入，并在 resolve 阶段调用 SkillRuntime。  
2) 我们希望道具系统独立，但仍要接入 TurnManager 的回合状态机（不然 UI/AI/胜负判断会割裂）。  
3) BattleNarrator 已基于 BattleEventBus 事件流工作；道具效果必须发出同类事件，才能播报一致。

---

## 3. 方案对比（如何把“使用道具”接入 TurnManager）

### 方案 A：TurnCommand 增加 kind（推荐）
扩展 TurnCommand，使其支持两类命令：
- `kind="skill"`：现有流程不变
- `kind="item"`：TurnManager 在 resolve 时调用 `BattleItemSystem.execute_item(...)`

优点：
- 道具系统仍是独立模块（Inventory + BattleItemSystem）
- TurnManager 只做“路由”，不需要把 item 当成 skill
- UI/AI 的提交入口仍统一（submit_player_command）

成本：
- 需要改 TurnCommand/TurnManager resolve 分支，并更新相关测试与 demo

### 方案 B：伪装成 skill_id（不推荐，违背“独立系统”）
例如用 `skill_id="item:potion_small"`，SkillRuntime 里做特殊分支。

缺点：
- item 定义/逻辑被迫耦合在技能系统里
- 未来背包系统独立演进会更痛

结论：选 **方案 A**。

---

## 4. 架构拆分（文件级）

### 4.1 Inventory（独立系统，不依赖战斗）
路径建议：`res://addons/inventory_system/runtime/`
- `item_def.gd`（或 JSON defs + loader）：id/name/desc/targeting/effects…
- `inventory.gd`：`add_item/remove_item/get_count/consume`
- `inventory_component.gd`（可选）：挂到角色/账号/队伍

### 4.2 BattleItemSystem（战斗适配层）
路径建议：`res://addons/turn_manager/runtime/items/`
职责：
- 校验可用性（数量>0、目标合法、战斗内允许等）
- 消耗物品（Inventory.consume）
- 应用效果（通过 OmniBuffAdapter 或直接操作 stats/buffs，但必须 emit battle events）
- 产出播报所需的事件 payload（skill_id 可为空，另加 item_id）

事件约定（沿用现有 EventNames 字符串）：
- `before_heal/after_heal`、`before_damage/after_damage`
- `buff_applied/buff_removed`
- 可新增：`item_used`（便于播报“谁使用了什么物品”）

### 4.3 Battle UI（技能/物品共享“点选目标”）
路径建议：`res://addons/turn_manager/runtime/ui/`
组件：
- `battle_action_panel.tscn/.gd`：两个 tab（技能/物品），点击后进入“选目标”模式
- `battle_targeting_overlay.gd`：计算/高亮可选格子，处理格子点击
- `battle_hud.tscn`：组合 action_panel + log_panel +（可选）单位面板

核心共用点：TargetingResolver
- 输入：actor、action（skill 或 item）、grid、camp
- 输出：可选 cell 列表

---

## 5. 数据与接口（最小集合）

### 5.1 ItemDef（建议字典结构）
```json
{
  "id": "item_potion_small",
  "name": "小治疗药水",
  "targeting": { "rule": "single_cell", "camp": "ally" },
  "effects": [
    { "kind": "heal", "params": { "amount": 35 } }
  ]
}
```

### 5.2 TurnCommand 扩展（方案 A）
新增字段：
- `kind: String = "skill"`  # "skill" | "item"
- `id: String`               # skill_id 或 item_id

兼容策略：
- 保留现有 `skill_id` 字段但作为 alias（或迁移为 `id`）
- demo 与旧调用可继续用 `TurnCommand.new("act_xxx", cell)`，默认 kind=skill

### 5.3 UI 流程（玩家操作）
1) TurnManager 发 `action_requested(actor, valid_skills)`
2) UI 显示：
   - 技能列表（valid_skills + 冷却/可用性）
   - 道具列表（inventory 中可用道具）
3) 玩家点一个技能/道具 → overlay 高亮可选格子
4) 玩家点格子 → 生成 TurnCommand：
   - skill：`TurnCommand.new_skill(skill_id, cell)`
   - item：`TurnCommand.new_item(item_id, cell)`
5) `turn_manager.submit_player_command(cmd)`

---

## 6. 播报与配色联动

BattleNarrator 将新增对 `item_used` 的播报：
- “主角 使用 道具【小治疗药水】（目标：队友）”
并沿用现有 after_heal/after_damage 行输出数值变化。

---

## 7. 验收标准

1) demo/hud 中可点击技能或道具，进入选格子模式并成功提交行动  
2) 道具消耗库存（数量减少），且效果生效（HP 变化 / buff 变化）  
3) 播报面板能显示“使用道具/造成伤害/治疗/BUFF 变化”  
4) 技能与道具共享“格子选目标”逻辑（可选格子一致、camp 限制一致）  

