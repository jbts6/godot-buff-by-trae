# OmniBuff Phase 1 Command Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为纯回合制战斗新增 `COMMAND` 事件域（CMD_BEFORE/CMD_AFTER），支持对“攻击(普攻技能)/技能/道具/防御/逃跑”的监听与干预；并提供 `CANCEL_COMMAND` action、command filters（command_kind_any / item_id），以及 tests+demo+HUD 的端到端覆盖。

**Architecture:** 复用现有 EventIndex/BuffCore 的子集遍历框架：新增枚举与 phase 编码→扩展 EventIndex.PHASE_COUNT→新增 CommandContext→在 BuffCore.emit_event 支持 COMMAND 的 filters/action→在 demo/test 中构造 CommandContext 并模拟“战斗系统执行指令”。

**Tech Stack:** Godot 4.7 + GDScript + OmniEventIndex + OmniBuffCore + validators + GUT + buff_ui_demo。

---

## 0) 文件清单

- Modify: `godot-buff/data/base_demo/enums.json`
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- Create: `godot-buff/addons/omnibuff/runtime/core/command_context.gd`
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`
- Modify (data): `godot-buff/data/rpg_tests/skill_defs.json`
- Modify (data): `godot-buff/data/rpg_tests/buff_defs.json`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_command_events_phase1.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_command_events_phase1.gd.uid`

---

## Task 1：写 failing tests（RED）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_command_events_phase1.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_command_events_phase1.gd.uid`

- [ ] **Step 1: 测试骨架**

```gdscript
extends GutTest

const TestDataset := preload(\"res://addons/omnibuff/tests/helpers/test_dataset.gd\")
const TestBattle := preload(\"res://addons/omnibuff/tests/helpers/test_battle.gd\")
const CommandContext := preload(\"res://addons/omnibuff/runtime/core/command_context.gd\")

func test_cancel_escape_command() -> void:
    pass
```

- [ ] **Step 2: 3 个用例（初始应失败）**
1) ESCAPE：CMD_BEFORE 命中 `CANCEL_COMMAND` → ctx.cancel=true
2) ATTACK（普攻技能）：tags_mask 包含 BASIC_ATTACK 时，listener 命中
3) USE_ITEM：按 item_id 过滤命中

- [ ] **Step 3: Commit（仅测试）**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_command_events_phase1.gd addons/omnibuff/tests/rpg/test_command_events_phase1.gd.uid
git -C godot-buff commit -m \"test(command): add failing coverage for command events\"
```

---

## Task 2：enums 增量（event_type/event_phase/action_kind）

**Files:**
- Modify: `godot-buff/data/base_demo/enums.json`

- [ ] **Step 1: enums 增加**
- event_type：追加 `COMMAND`
- event_phase：追加 `CMD_BEFORE`、`CMD_AFTER`
- action_kind：追加 `CANCEL_COMMAND`

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add data/base_demo/enums.json
git -C godot-buff commit -m \"feat(enums): add command events and cancel action\"
```

---

## Task 3：EventIndex 扩展 phase count（兼容）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`

- [ ] **Step 1: 提升 PHASE_COUNT**
将 `PHASE_COUNT` 从 16 提升到一个安全值（例如 32），确保新增 phase 编码可用。

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/event_index.gd
git -C godot-buff commit -m \"feat(event): increase phase count for command phases\"
```

---

## Task 4：新增 CommandContext

**Files:**
- Create: `godot-buff/addons/omnibuff/runtime/core/command_context.gd`

- [ ] **Step 1: 实现 RefCounted ctx**

字段：
```gdscript
var actor_id: int
var command_kind: String
var skill_id: int = -1
var item_id: int = -1
var targets: PackedInt32Array = PackedInt32Array()
var tags_mask: int = 0
var cancel: bool = false
```

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/command_context.gd
git -C godot-buff commit -m \"feat(command): add command context\"
```

---

## Task 5：BuffCore 支持 COMMAND filters 与 CANCEL_COMMAND

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: filters 支持**
在 emit_event 的过滤逻辑中：
- 若 event_type==COMMAND：支持 `filters.command_kind_any`、`filters.item_id`
  - `command_kind_any`：any-of match
  - `item_id`：int match（ctx.item_id==-1 视为不匹配）

- [ ] **Step 2: 注册解析**
在 `_register_triggers_for_instance()` 解析 command filters 到 Listener（新增字段）：
- `filter_command_kind_mask_any`（或 Array[String]，按你喜欢；建议 mask）
- `filter_item_id: int`

- [ ] **Step 3: 新 action**
`CANCEL_COMMAND`：当 ctx 有字段 cancel 时，置 true

- [ ] **Step 4: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff commit -m \"feat(command): support command filters and cancel action\"
```

---

## Task 6：validators 支持 COMMAND

**Files:**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`

- [ ] **Step 1: filters 白名单**
允许：
- `command_kind_any`
- `item_id`

- [ ] **Step 2: action.kind= CANCELED_COMMAND 白名单与字段要求**
（无额外字段）

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/config/compiler/validators.gd
git -C godot-buff commit -m \"feat(validate): support command events\"
```

---

## Task 7：rpg_tests 数据（BASIC_ATTACK 与测试 buff）

**Files:**
- Modify: `godot-buff/data/rpg_tests/skill_defs.json`
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: skill_defs 增加 BASIC_ATTACK tag**
为至少一个技能增加 tags：`BASIC_ATTACK`（或新增一个专门的 basic attack skill）。

- [ ] **Step 2: buff_defs 增加 3 个测试 buff**
- cancel_escape：COMMAND/CMD_BEFORE + command_kind_any=["ESCAPE"] + CANCEL_COMMAND
- basic_attack_mark：COMMAND/CMD_AFTER + tag_mask_any=["BASIC_ATTACK"] + APPLY_BUFF(mark)
- use_item_mark：COMMAND/CMD_AFTER + item_id=2001 + APPLY_BUFF(mark)

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add data/rpg_tests/skill_defs.json data/rpg_tests/buff_defs.json
git -C godot-buff commit -m \"test(command): add rpg_tests defs for command events\"
```

---

## Task 8：HUD + Demo scenarios

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: HUD 输出 CANCEL_COMMAND action 摘要（若未覆盖）**

- [ ] **Step 2: demo 新增 3 个 scenario**
在 scenario 中手工构造 CommandContext（并注入 runtime 到 ctx.meta）：
- command_cancel_escape
- command_basic_attack_tag
- command_use_item

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/debug_hud.gd addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m \"feat(demo): add command event scenarios\"
```

---

## 最终验证

- [ ] `test_command_events_phase1.gd` 全绿
- [ ] 抽样跑 2 个旧 rpg_tests 仍绿
- [ ] Demo 三个 scenario 可复现：escape 被取消、basic attack tag 命中、use item 命中

