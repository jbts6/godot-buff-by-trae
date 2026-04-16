# OmniBuff BattleExecutor Multi-hit/Multi-target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 扩展 `OmniBattleExecutor` 支持多段（multi-hit）、多目标（multi-target）并正确递增 `roll_key`，使每段命中/暴击确定性独立可复盘；并通过 tests+demo 验证 trace 顺序稳定。

**Architecture:** 保持 COMMAND 每条指令一次；通过在 executor 内部对 targets 做稳定排序，并用双层循环（target→hit）多次调用 `DamagePipeline.deal_damage`；每次调用递增 `roll_key`。skill_defs 增加轻量字段 `hit_count/hit_base_damage/targeting` 以驱动循环次数与 base_damage。

**Tech Stack:** Godot 4.7 + GDScript + OmniBattleExecutor + OmniDamagePipeline + OmniReplay + GUT。

---

## 0) 文件清单

- Modify: `godot-buff/addons/omnibuff/runtime/core/battle_executor.gd`
- Modify: `godot-buff/data/rpg_tests/skill_defs.json`（补齐多段/多目标字段）
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_battle_executor_multihit_multitarget.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_battle_executor_multihit_multitarget.gd.uid`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

---

## Task 1：写 failing tests（RED）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_battle_executor_multihit_multitarget.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_battle_executor_multihit_multitarget.gd.uid`

- [ ] **Step 1: 新增 3 个用例（初始应失败）**

用例 1：multi-hit（3段）
- skill：`skill_triple_slash`（hit_count=3, hit_base_damage=[12,14,18], targeting=FIRST）
- targets=[defender]
- 断言：`replay.damage_traces` 新增 3 条，roll_key=0,1,2（通过 `trace.roll_key`）

用例 2：multi-target（ALL）
- skill：新增 `skill_whirlwind`（hit_count=1, targeting=ALL）
- targets=[defenderA, defenderB]
- 断言：新增 2 条 traces，且 defender_id 顺序稳定（按 entity_id 升序）

用例 3：组合（ALL + hit_count=2）
- skill：`skill_double_strike_all`（hit_count=2, targeting=ALL）
- targets=[A,B]
- 断言：新增 4 条 traces，roll_key=0..3 且顺序为 A hit0, A hit1, B hit0, B hit1

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_battle_executor_multihit_multitarget.gd addons/omnibuff/tests/rpg/test_battle_executor_multihit_multitarget.gd.uid
git -C godot-buff commit -m \"test(executor): add failing coverage for multihit and multitarget\"
```

---

## Task 2：扩展 rpg_tests skill_defs（驱动字段）

**Files:**
- Modify: `godot-buff/data/rpg_tests/skill_defs.json`

- [ ] **Step 1: 补齐 skill_triple_slash**
加入：
- `hit_count: 3`
- `hit_base_damage: [12,14,18]`
- `targeting: "FIRST"`

- [ ] **Step 2: 新增两条技能**
- `skill_whirlwind`：targeting=ALL, hit_count=1, hit_base_damage=[10]
- `skill_double_strike_all`：targeting=ALL, hit_count=2, hit_base_damage=[8,8]

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add data/rpg_tests/skill_defs.json
git -C godot-buff commit -m \"test(executor): add skill_defs for multihit and multitarget\"
```

---

## Task 3：实现 executor 双层循环 + roll_key

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/battle_executor.gd`

- [ ] **Step 1: 解析 skill_defs 字段**
从 `skill` dict 读取：
- `hit_count`（默认 1）
- `hit_base_damage`（优先级高于 base_damage）
- `targeting`（FIRST/ALL）

- [ ] **Step 2: targets 稳定排序**
对 ctx.targets 做复制并 sort（entity_id 升序），用于 ALL。

- [ ] **Step 3: 双层循环调用 deal_damage**
外层：target
内层：hit_index
每次调用：
- base_damage 取 `hit_base_damage`（若提供；支持长度=1 或 >=hit_count）
- roll_key 从 0 递增

- [ ] **Step 4: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/battle_executor.gd
git -C godot-buff commit -m \"feat(executor): support multihit, multitarget, and roll_key\" 
```

---

## Task 4：Demo scenarios

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: 新增 2 个场景**
- `executor_multihit_triple_slash`（targets 1 个）
- `executor_multitarget_all`（targets 2 个）

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m \"feat(demo): add multihit and multitarget executor scenarios\"
```

---

## 最终验证

- [ ] 跑 `test_battle_executor_multihit_multitarget.gd` 全绿
- [ ] 抽样跑 `test_battle_executor_minimal.gd` 仍绿
- [ ] demo 两个场景可复现，日志中可看到多条 DamageTrace（roll_key 递增）

