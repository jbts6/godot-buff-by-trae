# OmniBuff Tutorial Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为未做过 Buff 系统的 Godot 开发者编写一套可读、可运行、可查阅的 OmniBuff Tutorial（多章节 Markdown + Mermaid 图），并放在 `addons/omnibuff/tutorial/` 下。

**Architecture:** 以章节拆分讲清“为什么这样设计 → 怎么跑起来 → 数据链路 → 运行时核心 → 调试与扩展”，并从 README 建立入口。

**Tech Stack:** Markdown + Mermaid（代码块 ` ```mermaid `）。

---

## 0) 文件清单

**Create（new tutorial folder）**
- `godot-buff/addons/omnibuff/tutorial/00_index.md`
- `godot-buff/addons/omnibuff/tutorial/01_why_and_principles.md`
- `godot-buff/addons/omnibuff/tutorial/02_quickstart_run_a_hit.md`
- `godot-buff/addons/omnibuff/tutorial/03_data_pipeline.md`
- `godot-buff/addons/omnibuff/tutorial/04_stats_system.md`
- `godot-buff/addons/omnibuff/tutorial/05_buff_and_events.md`
- `godot-buff/addons/omnibuff/tutorial/06_damage_dot_turn_replay.md`
- `godot-buff/addons/omnibuff/tutorial/07_debug_and_extend.md`

**Modify**
- `godot-buff/addons/omnibuff/README.md`（增加 tutorial 入口）

---

## Task 1：创建 tutorial 目录 + index

**Files:**
- Create: `godot-buff/addons/omnibuff/tutorial/00_index.md`

- [ ] **Step 1: 创建目录**

Run:
```bash
mkdir -p godot-buff/addons/omnibuff/tutorial
```

- [ ] **Step 2: 编写 00_index.md**

必须包含：
- 推荐阅读路径（新手 → 进阶）
- “先跑起来”指向：`buff_ui_demo.tscn`、`demo_scene.tscn`、GUT tests
- 本 tutorial 与 `docs/api.md` / `docs/integrator_guide.md` 的关系

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/tutorial/00_index.md
git -C godot-buff commit -m "docs(tutorial): add index"
```

---

## Task 2：写 01 设计思想（Why & Principles）

**Files:**
- Create: `godot-buff/addons/omnibuff/tutorial/01_why_and_principles.md`

- [ ] **Step 1: Mermaid 架构图（组件边界）**
必须包含：Dataset pipeline / Runtime core / Demo+Tests 三块。

- [ ] **Step 2: 核心设计原则讲解**
必须覆盖：
- 数据驱动边界（Compiler vs Runtime）
- 性能约束（EventIndex 子集遍历、StatCache）
- 不依赖 class_name 的原因（autoload 命名空间入口）
- 确定性与回归（roll_key、Replay output-only）

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/tutorial/01_why_and_principles.md
git -C godot-buff commit -m "docs(tutorial): add principles chapter"
```

---

## Task 3：写 02 Quickstart（跑通一次伤害）

**Files:**
- Create: `godot-buff/addons/omnibuff/tutorial/02_quickstart_run_a_hit.md`

- [ ] **Step 1: 最小可运行代码**
必须使用：
- `ManifestLoader.load_dataset_full`
- `EnumsRuntime.from_enums_json`
- `DatasetCompiler.compile`
- `DamagePipeline.deal_damage_v1`
- `StatsComponent.get_final` 与 `get_breakdown`

- [ ] **Step 2: Mermaid（时序图）**
展示：load → compile → create objects → apply buff → deal_damage。

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/tutorial/02_quickstart_run_a_hit.md
git -C godot-buff commit -m "docs(tutorial): add quickstart chapter"
```

---

## Task 4：写 03 数据链路（Data Pipeline）

**Files:**
- Create: `godot-buff/addons/omnibuff/tutorial/03_data_pipeline.md`

- [ ] **Step 1: Mermaid（flowchart）**
manifest → enums/sources → validate → compile → runtime uses ds。

- [ ] **Step 2: 解释每份文件的角色**
`manifest.json` / `enums.json` / `stat_defs.json` / `buff_defs.json`

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/tutorial/03_data_pipeline.md
git -C godot-buff commit -m "docs(tutorial): add data pipeline chapter"
```

---

## Task 5：写 04 Stats 系统（Cache + layers + breakdown + derived/curve）

**Files:**
- Create: `godot-buff/addons/omnibuff/tutorial/04_stats_system.md`

- [ ] **Step 1: 解释 base/flat/pct(layer)/override/final_add/curve/clamp 的顺序**
- [ ] **Step 2: 展示 get_breakdown 在 UI 面板如何用**
- [ ] **Step 3: derived/curve 示例（用 rpg_tests 的 stat_defs）**
- [ ] **Step 4: Commit**

```bash
git -C godot-buff add addons/omnibuff/tutorial/04_stats_system.md
git -C godot-buff commit -m "docs(tutorial): add stats system chapter"
```

---

## Task 6：写 05 Buff + EventIndex（监听子集、filters/actions、LIFE/STACKS）

**Files:**
- Create: `godot-buff/addons/omnibuff/tutorial/05_buff_and_events.md`

- [ ] **Step 1: Mermaid（事件分发图）**
emit_event → listeners subset → filters → action exec。

- [ ] **Step 2: scope/runtime dict & LIFE 示例**
- [ ] **Step 3: stacks actions 示例（ADD_STACKS/SET_STACKS）**
- [ ] **Step 4: Commit**

```bash
git -C godot-buff add addons/omnibuff/tutorial/05_buff_and_events.md
git -C godot-buff commit -m "docs(tutorial): add buff and events chapter"
```

---

## Task 7：写 06 Damage/DOT/Turn/Replay

**Files:**
- Create: `godot-buff/addons/omnibuff/tutorial/06_damage_dot_turn_replay.md`

- [ ] **Step 1: Mermaid（DamagePipeline stages）**
- [ ] **Step 2: DOT 生命周期（DotInstance 权威）**
- [ ] **Step 3: TurnComponent 的 TURN_START tick 约定**
- [ ] **Step 4: Replay output-only 与 roll_key 的关系**
- [ ] **Step 5: Commit**

```bash
git -C godot-buff add addons/omnibuff/tutorial/06_damage_dot_turn_replay.md
git -C godot-buff commit -m "docs(tutorial): add damage dot turn replay chapter"
```

---

## Task 8：写 07 Debug & Extend（demo/hud/tests/扩展清单）

**Files:**
- Create: `godot-buff/addons/omnibuff/tutorial/07_debug_and_extend.md`

- [ ] **Step 1: buff_ui_demo / DebugHUD / ErrorList 的使用方式**
- [ ] **Step 2: 如何新增 scenario 与 tests 的推荐流程**
- [ ] **Step 3: 扩展 checklist（新增 action/filter/stat/buff 时要改哪些地方）**
- [ ] **Step 4: Commit**

```bash
git -C godot-buff add addons/omnibuff/tutorial/07_debug_and_extend.md
git -C godot-buff commit -m "docs(tutorial): add debug and extension chapter"
```

---

## Task 9：README 增加 tutorial 入口 + 最终检查

**Files:**
- Modify: `godot-buff/addons/omnibuff/README.md`

- [ ] **Step 1: README 增加 tutorial 链接**
例如在“文档导航”中加入：
- `res://addons/omnibuff/tutorial/00_index.md`

- [ ] **Step 2: 最终检查**
- 目录结构正确
- 所有 mermaid 代码块闭合
- `git status` 干净

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/README.md
git -C godot-buff commit -m "docs: link tutorial entry from readme"
```

