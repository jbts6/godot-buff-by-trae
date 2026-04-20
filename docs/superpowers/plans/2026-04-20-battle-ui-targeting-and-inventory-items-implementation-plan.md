# 战斗 UI（格子点选目标）+ 独立背包/道具系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 TurnManager/TurnSkillSystem/OmniBuff 的基础上，实现一个可套 UI 的“技能/道具 → 格子点选目标 → 提交行动”闭环；道具系统保持独立，但可接入回合制战斗并产生一致的播报事件。

**Architecture:**  
1) 扩展 TurnCommand 支持 `kind=skill|item`（推荐方案 A）。  
2) 新增独立 `inventory_system` 插件（ItemDef + Inventory）。  
3) 新增 `BattleItemSystem`（战斗适配层）在 TurnManager resolve 阶段执行 item。  
4) 新增 Battle HUD：ActionPanel（技能/道具）+ TargetingOverlay（格子高亮/点击）+ BattleLogPanel（已有）。

**Tech Stack:** Godot 4.7, GDScript, TurnManager, TurnSkillSystem, OmniBuff, BattleEventBus, RichTextLabel(BBCode)。

---

## 0) 文件结构（先锁定）

**Modify**
- `res://addons/turn_manager/runtime/turn_command.gd`
- `res://addons/turn_manager/runtime/turn_manager.gd`
- `res://addons/turn_manager/runtime/battle_narrator.gd`（新增 item_used 播报）

**Create**
- `res://addons/inventory_system/plugin.cfg`
- `res://addons/inventory_system/plugin.gd`
- `res://addons/inventory_system/runtime/item_def.gd`
- `res://addons/inventory_system/runtime/inventory.gd`
- `res://addons/turn_manager/runtime/items/battle_item_system.gd`
- `res://addons/turn_manager/runtime/ui/battle_action_panel.tscn`
- `res://addons/turn_manager/runtime/ui/battle_action_panel.gd`
- `res://addons/turn_manager/runtime/ui/battle_targeting_overlay.gd`
- `res://addons/turn_manager/runtime/ui/battle_hud.tscn`
- `res://addons/turn_manager/runtime/ui/battle_hud.gd`

**Demo**
- `res://addons/turn_manager/demo/demo_battle.tscn`
- `res://addons/turn_manager/demo/demo_battle.gd`

**Tests**
- `res://addons/turn_manager/tests/test_turn_command_kind_item.gd`
- `res://addons/turn_manager/tests/test_battle_item_system_smoke.gd`

---

## Task 1（RED）: TurnCommand 支持 kind=item 的测试

**Files:**
- Create: `res://addons/turn_manager/tests/test_turn_command_kind_item.gd`

- [ ] Step 1: 写失败测试：TurnCommand 必须能构造 item 命令且字段正确

```gdscript
extends GutTest
const TurnCommand = preload("res://addons/turn_manager/runtime/turn_command.gd")

func test_turn_command_item_kind() -> void:
	var cmd = TurnCommand.new_item("item_potion_small", Vector2i(0, 0))
	assert_eq(String(cmd.kind), "item")
	assert_eq(String(cmd.id), "item_potion_small")
	assert_eq(Vector2i(cmd.primary_cell), Vector2i(0, 0))
```

- [ ] Step 2: 运行 GUT（本地）：`./run_gut_tests.sh`，预期 FAIL（new_item 不存在）
- [ ] Step 3: Commit

```bash
git add addons/turn_manager/tests/test_turn_command_kind_item.gd
git commit -m "test(turn_manager): require item kind TurnCommand"
```

---

## Task 2（GREEN）: 实现 TurnCommand.kind/id（兼容旧 skill_id）

**Files:**
- Modify: `res://addons/turn_manager/runtime/turn_command.gd`

- [ ] Step 1: 修改 TurnCommand：
  - 新增字段 `kind:String`、`id:String`
  - 保留旧字段 `skill_id` 作为 alias（读取时返回 id；写入时同步）
  - 新增构造函数：
    - `static func new_skill(skill_id:String, cell:Vector2i) -> TurnCommand`
    - `static func new_item(item_id:String, cell:Vector2i) -> TurnCommand`
- [ ] Step 2: 运行 GUT，预期 Task 1 PASS
- [ ] Step 3: Commit

```bash
git add addons/turn_manager/runtime/turn_command.gd
git commit -m "feat(turn_manager): add TurnCommand kind for item"
```

---

## Task 3（RED）: BattleItemSystem 冒烟测试（使用道具能改 HP 并 emit after_heal）

**Files:**
- Create: `res://addons/turn_manager/tests/test_battle_item_system_smoke.gd`

- [ ] Step 1: 写失败测试（伪代码结构，按工程现有 stats/buffs 组件构造一个最小 runtime_dict）
  - 创建 inventory（item_potion_small count=1）
  - 创建 battle_item_system 并 bind(event_bus, omnibuff_adapter, inventory, ds, runtime_dict)
  - 调用 `use_item(actor_id, item_id, target_cell)` 后：
    - target HP 增加
    - inventory count 减少
    - event_bus capture 中包含 `after_heal`
- [ ] Step 2: Commit

---

## Task 4（GREEN）: 实现 inventory_system（ItemDef + Inventory）

**Files:**
- Create: `res://addons/inventory_system/runtime/item_def.gd`
- Create: `res://addons/inventory_system/runtime/inventory.gd`
- Create: `res://addons/inventory_system/plugin.cfg`
- Create: `res://addons/inventory_system/plugin.gd`（最小空插件，仅用于启用脚本类/资源类型）

- [ ] Step 1: ItemDef（可先用 Dictionary + helper，不强制 Resource）
- [ ] Step 2: Inventory 支持：
  - `set_count(item_id:int)`
  - `get_count(item_id)`
  - `can_consume(item_id, amount)`
  - `consume(item_id, amount)`（返回 ok/err）
- [ ] Step 3: Commit

---

## Task 5（GREEN）: 实现 BattleItemSystem（独立战斗适配层）

**Files:**
- Create: `res://addons/turn_manager/runtime/items/battle_item_system.gd`

- [ ] Step 1: 接口：
  - `bind(event_bus, omnibuff_adapter, inventory, ds, runtime_dict, item_db:Dictionary)`
  - `execute_item(actor_id:int, item_id:String, target_cell:Vector2i) -> Dictionary`
- [ ] Step 2: 内部逻辑：
  - 校验数量
  - 解析 item_db[item_id].effects
  - 对 heal/damage/apply_buff/remove_buff：
    - 直接调用 omnibuff_adapter（或 omnibuff_singleton）执行
    - emit `before_* / after_* / buff_*` 与 `item_used`
- [ ] Step 3: 让 Task 3 测试通过
- [ ] Step 4: Commit

---

## Task 6（GREEN）: TurnManager resolve 支持 kind=item

**Files:**
- Modify: `res://addons/turn_manager/runtime/turn_manager.gd`
- Modify: `res://addons/turn_manager/runtime/battle_context.gd`（新增 battle_item_system 引用）

- [ ] Step 1: BattleContext 增加字段 `battle_item_system`
- [ ] Step 2: TurnManager._handle_resolve_action 分支：
  - `cmd.kind=="skill"`：现状
  - `cmd.kind=="item"`：调用 `context.battle_item_system.execute_item(...)`
  - 成功后 emit action_finished
- [ ] Step 3: Commit

---

## Task 7（GREEN）: BattleNarrator 增加 item_used 的播报

**Files:**
- Modify: `res://addons/turn_manager/runtime/battle_narrator.gd`

- [ ] Step 1: 监听 `item_used`：
  - 输出“{actor} 使用 道具【name】”
- [ ] Step 2: Commit

---

## Task 8（RED/GREEN）: Battle HUD（技能/道具列表 + 格子点选目标）

**Files:**
- Create: `res://addons/turn_manager/runtime/ui/battle_action_panel.tscn/.gd`
- Create: `res://addons/turn_manager/runtime/ui/battle_targeting_overlay.gd`
- Create: `res://addons/turn_manager/runtime/ui/battle_hud.tscn/.gd`

- [ ] Step 1 (RED): 先搭场景与脚本骨架，能显示面板但不可用 → commit
- [ ] Step 2 (GREEN): 实现 TargetingResolver：
  - skill：读取 skill.targeting（FIRST/ALL/single_cell camp）
  - item：读取 item.targeting
  - 输出可点击 cell 列表
- [ ] Step 3 (GREEN): overlay 高亮与点击回调：
  - 点格子生成 TurnCommand（skill/item）并 submit
- [ ] Step 3.1 (GREEN): 增加“取消选择/返回”交互：
  - ActionPanel 上提供 `取消/返回` 按钮（或 Esc 键）
  - 取消后：
    - 清空当前选中的 action（skill/item）
    - 清空高亮格子
    - 回到技能/道具列表可选状态
- [ ] Step 4: Commit

---

## Task 9（GREEN）: demo_battle 接入 BattleHUD + 初始道具

**Files:**
- Modify: `res://addons/turn_manager/demo/demo_battle.tscn`
- Modify: `res://addons/turn_manager/demo/demo_battle.gd`

- [ ] Step 1: demo 场景挂 BattleHUD（含 BattleLogPanel）
- [ ] Step 2: demo 初始化 inventory（比如主角 2 个小药水）
- [ ] Step 3: action_requested 时不再自动 submit（或保留“自动/手动”开关）
- [ ] Step 4: Commit

---

## Task 10（可选）: 文档

**Files:**
- Modify: `res://addons/turn_manager/README.md`
- Modify: `res://addons/inventory_system/README.md`（新增）

- [ ] Step 1: 描述 UI 操作流与 item 系统边界
- [ ] Step 2: Commit
