# OmniBuff BattleExecutor (Minimal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一个最小可用的回合制 `OmniBattleExecutor`，把 `COMMAND` 事件与 `DAMAGE`/DamagePipeline 串起来，支持 ATTACK/CAST_SKILL/USE_ITEM/DEFEND/ESCAPE，并提供 tests+demo 验证（尤其是“普攻加成”与“取消逃跑”）。

**Architecture:** executor 是“战斗系统桥接层”，不改现有核心：通过 `ctx.set_meta("runtime", runtime)` 复用 BuffCore actions；对攻击/技能使用 `pipeline.deal_damage`；对道具/防御/逃跑仅做最小行为与 COMMAND before/after 触发。技能数据暂从 loader 的 `sources["skill_defs"]` 读取（不扩展 CompiledDataset）。

**Tech Stack:** Godot 4.7 + GDScript + OmniCommandContext + OmniBuffCore + OmniDamagePipeline + OmniManifestLoader + GUT。

---

## 0) 文件清单

- Create: `godot-buff/addons/omnibuff/runtime/core/battle_executor.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_battle_executor_minimal.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_battle_executor_minimal.gd.uid`
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`（新增普攻加成 buff + defend buff）
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`（新增 2 个 scenario）

---

## Task 1：写 failing tests（RED）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_battle_executor_minimal.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_battle_executor_minimal.gd.uid`

- [ ] **Step 1: 测试文件骨架**

```gdscript
extends GutTest

const TestDataset := preload(\"res://addons/omnibuff/tests/helpers/test_dataset.gd\")
const TestBattle := preload(\"res://addons/omnibuff/tests/helpers/test_battle.gd\")
const Executor := preload(\"res://addons/omnibuff/runtime/core/battle_executor.gd\")
const CommandContext := preload(\"res://addons/omnibuff/runtime/core/command_context.gd\")
const ReplayScript := preload(\"res://addons/omnibuff/runtime/core/replay.gd\")

func test_executor_attack_basic_attack_bonus_applies() -> void:
    pass
```

- [ ] **Step 2: 3 个用例（初始应失败）**

1) 普攻加成：
- attacker 挂 `buff_basic_attack_add_base_5`
- 执行 ATTACK（skill_basic_attack_1，targets=[defender]）
- 断言 DamageContext.base_damage / final_damage 增加

2) 取消逃跑：
- actor 挂 `buff_cmd_cancel_escape`
- 执行 ESCAPE
- 断言 canceled=true、escaped=false

3) 道具过滤：
- actor 挂 `buff_cmd_use_item_mark`（item_id=2001）
- 执行 USE_ITEM item_id=2001
- 断言 mark 被挂上

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_battle_executor_minimal.gd addons/omnibuff/tests/rpg/test_battle_executor_minimal.gd.uid
git -C godot-buff commit -m \"test(executor): add failing coverage for minimal battle executor\"
```

---

## Task 2：实现 OmniBattleExecutor（GREEN）

**Files:**
- Create: `godot-buff/addons/omnibuff/runtime/core/battle_executor.gd`

- [ ] **Step 1: 定义 ExecuteResult + execute_command()**

实现要点：
- 在函数开始：`ctx.set_meta(\"runtime\", runtime)`
- 触发 `buff_actor.emit_event(\"COMMAND\",\"CMD_BEFORE\", ctx)`
- 若 `ctx.cancel==true`：返回 canceled=true（不执行真实逻辑）
- 按 ctx.command_kind 分发：
  - ATTACK/CAST_SKILL：取 targets[0]，构造 tags_mask（从 sources.skill_defs 查 skill.tags），调用 pipeline.deal_damage
  - USE_ITEM：根据 item_id（2001/2002）直接改 HP/SHIELD（add_base），然后 emit CMD_AFTER
  - DEFEND：给自己 apply `buff_defend_1t`（或等价），然后 emit CMD_AFTER
  - ESCAPE：若未 cancel，result.escaped=true

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/battle_executor.gd
git -C godot-buff commit -m \"feat(executor): add minimal battle executor bridging command to damage\"
```

---

## Task 3：补齐 rpg_tests 数据（普攻加成与防御 buff）

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 增加 buff_basic_attack_add_base_5**

- event: DAMAGE / BEFORE_DEAL
- filters: tag_mask_any=[BASIC_ATTACK]
- action: ADD_BASE_DAMAGE(value=5)

- [ ] **Step 2: 增加 buff_defend_1t（示例）**

最小：给自己 `DMG_REDUCE` 或 `SHIELD`（任选其一），duration=TURNS(1)。

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add data/rpg_tests/buff_defs.json
git -C godot-buff commit -m \"test(executor): add rpg_tests buffs for basic attack bonus and defend\"
```

---

## Task 4：补齐 demo scenarios

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: executor_attack_basic**
展示：COMMAND before/after + DAMAGE before_deal + base_damage 被加成

- [ ] **Step 2: executor_escape_cancel**
展示：CMD_BEFORE 被 CANCEL_COMMAND 改写 cancel=true

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m \"feat(demo): add minimal battle executor scenarios\"
```

---

## 最终验证

- [ ] 跑 `test_battle_executor_minimal.gd` 全绿
- [ ] 抽样跑 2 个旧 rpg_tests 仍绿
- [ ] demo 场景可复现

