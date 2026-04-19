# 战斗语义化播报（BattleNarrator + 面板）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现一套基于 BattleEventBus 的战斗语义化播报系统：默认简洁、可切换详细；输出到游戏内 RichTextLabel 面板；补齐 `buff_applied/buff_removed` 与 `turn_order_computed` 事件，能播报被动/光环、出手顺序、每回合技能与伤害/治疗结果。

**Architecture:**  
- `BattleNarrator`（runtime）：订阅 event_bus，将事件翻译为 BBCode 行，通过 signal 输出给 UI；内部用 Log.gd 的 `Log.to_printable()` 生成彩色文本。  
- `BattleLogPanel`（runtime/ui）：RichTextLabel 展示；toggle 控制 narrator.detail_level（默认简洁）。  
- 事件补齐：Apply/Remove Buff effect emit buff_applied/buff_removed；TurnManager 重排队列后 emit turn_order_computed。

**Tech Stack:** Godot 4.7, GDScript, addons/log(Log.gd), TurnManager, TurnSkillSystem, OmniBuff。

---

## Task 1（RED）: 新增 BattleNarrator 冒烟测试（把事件翻译成播报行）

**Files:**
- Create: `res://addons/turn_manager/tests/test_battle_narrator_smoke.gd`

- [ ] Step 1: 写测试：创建一个假的 event_bus（或用 BattleEventBus），实例化 BattleNarrator，bind 后 emit 一组事件：
  - battle_started
  - turn_order_computed（含 order）
  - turn_started/action_started/after_damage/unit_died
 断言：narrator 至少 emit 了若干行（line_emitted 被调用），并且包含关键词（如“战斗开始”“回合”“受到”）。
- [ ] Step 2: 运行 GUT，确认 FAIL（尚无 BattleNarrator）
- [ ] Step 3: Commit：
  - `git add ... && git commit -m "test(turn_manager): add battle narrator smoke test"`

---

## Task 2（GREEN）: 实现 BattleNarrator（最小可用：简洁模式）

**Files:**
- Create: `res://addons/turn_manager/runtime/battle_narrator.gd`

- [ ] Step 1: 实现 bind + 监听 event_bus.event_emitted
- [ ] Step 2: 事件映射（先做简洁模式）：
  - battle_started -> “战斗开始！”
  - turn_order_computed -> “计算出手顺序：...”
  - turn_started -> “回合 X：Y 行动”
  - action_started -> “Y 使用【skill】”
  - after_damage -> “T 受到 N 伤害，HP a/b”
  - after_heal -> “T 恢复 N，HP a/b”
  - unit_died -> “T 倒下了！”
- [ ] Step 3: 文本生成用 `Log.to_printable([payload], {pretty=true, disable_colors=false})`，产出 BBCode 字符串后 emit
- [ ] Step 4: 运行 GUT，确认 Task 1 PASS
- [ ] Step 5: Commit：
  - `git add ... && git commit -m "feat(turn_manager): add BattleNarrator runtime"`

---

## Task 3（RED）: 新增 UI 冒烟测试/场景验证（面板能展示播报）

**Files:**
- Create: `res://addons/turn_manager/runtime/ui/battle_log_panel.tscn`
- Create: `res://addons/turn_manager/runtime/ui/battle_log_panel.gd`

- [ ] Step 1: 先不跑自动化 UI 测试，改为 demo 场景接入做手动验收（RED：先创建文件与最小脚本，运行会缺 narrator 接入）
- [ ] Step 2: Commit（仅添加面板骨架）：
  - `git add ... && git commit -m "feat(ui): add battle log panel skeleton"`

---

## Task 4（GREEN）: 实现 BattleLogPanel（简洁/详细切换 + 追加行）

**Files:**
- Modify: `res://addons/turn_manager/runtime/ui/battle_log_panel.gd`
- Modify: `res://addons/turn_manager/runtime/ui/battle_log_panel.tscn`

- [ ] Step 1: RichTextLabel：`bbcode_enabled=true`，提供 `append_line(bbcode:String)`
- [ ] Step 2: Toggle（OptionButton/CheckBox）：
  - 默认简洁
  - 切换时调用 `narrator.set_detail_level(...)`
- [ ] Step 3: 清空按钮（可选）
- [ ] Step 4: Commit：
  - `git add ... && git commit -m "feat(ui): implement battle log panel"`

---

## Task 5（RED）: 新增测试（buff_applied 事件必须能被 narrator 播报）

**Files:**
- Modify: `res://addons/turn_manager/tests/test_battle_narrator_smoke.gd`（或新增 `test_battle_narrator_buff_applied.gd`）

- [ ] Step 1: 增加用例：emit buff_applied（包含 caster_id/target_id/buff_id），断言播报包含“获得/生效”字样
- [ ] Step 2: 运行 GUT，确认 FAIL（还没有 buff_applied 事件来源）
- [ ] Step 3: Commit（仅测试）：
  - `git add ... && git commit -m "test: require buff_applied narration"`

---

## Task 6（GREEN）: Apply/Remove Buff effect 发出 buff_applied/buff_removed

**Files:**
- Modify: `res://addons/turn_skill_system/runtime/event_names.gd`（新增常量）
- Modify: `res://addons/turn_skill_system/runtime/effects/apply_buff_effect.gd`
- Modify: `res://addons/turn_skill_system/runtime/effects/remove_buff_effect.gd`（若存在）

- [ ] Step 1: 在 EventNames 增加：
  - `BUFF_APPLIED := "buff_applied"`
  - `BUFF_REMOVED := "buff_removed"`
- [ ] Step 2: apply_buff_effect：成功 apply 后 emit_event(EventNames.BUFF_APPLIED, {...})
- [ ] Step 3: remove_buff_effect：成功 remove 后 emit BUFF_REMOVED
- [ ] Step 4: 运行 GUT，确认 Task 5 PASS（narrator 能收到事件并播报）
- [ ] Step 5: Commit：
  - `git add ... && git commit -m "feat(turn_skill_system): emit buff applied/removed events"`

---

## Task 7（RED）: 新增测试（turn_order_computed 必须播报）

**Files:**
- Modify: narrator 测试文件

- [ ] Step 1: 断言“计算出手顺序”行出现，且顺序包含 eid/名称
- [ ] Step 2: Commit（仅测试）：
  - `git add ... && git commit -m "test: require turn order narration"`

---

## Task 8（GREEN）: TurnManager emit turn_order_computed

**Files:**
- Modify: `res://addons/turn_manager/runtime/turn_manager.gd`

- [ ] Step 1: 在每轮重排队列后（队列确定时）emit：
  - `event_bus.emit_event("turn_order_computed", {"round_index":..., "turn_index":..., "order":[{eid,camp,speed}]})`
- [ ] Step 2: Commit：
  - `git add ... && git commit -m "feat(turn_manager): emit turn_order_computed event"`

---

## Task 9（GREEN）: demo_battle 接入 BattleLogPanel + BattleNarrator

**Files:**
- Modify: `res://addons/turn_manager/demo/demo_battle.tscn`（加一个 BattleLogPanel 节点）
- Modify: `res://addons/turn_manager/demo/demo_battle.gd`（创建 narrator，bind，并将 narrator 输出接到面板）

- [ ] Step 1: 在 demo 场景中实例化 panel（作为子节点）
- [ ] Step 2: demo_battle.gd：
  - `var narrator = BattleNarrator.new()`
  - `narrator.bind(context.event_bus, skill_rt.grid, ds, skill_rt.db, runtime_dict, name_map)`
  - `narrator.line_emitted.connect(panel.append_line)`
- [ ] Step 3: 手动运行 demo 验收：
  - 默认简洁播报
  - 切换为详细后，额外输出每个目标的细节（或更详 meta）
  - 被动/光环 buff 施加有播报
  - 出手顺序有播报
- [ ] Step 4: Commit：
  - `git add ... && git commit -m "chore(demo): add semantic battle narration panel"`

---

## Task 10（可选）: README 说明

**Files:**
- Modify: `res://addons/turn_manager/README.md`

- [ ] Step 1: 简述 BattleNarrator/BattleLogPanel 的用途与接入方式
- [ ] Step 2: Commit：
  - `git add ... && git commit -m "docs: describe battle narrator"`

