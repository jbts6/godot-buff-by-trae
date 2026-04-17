# OmniBuff Public API Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 README 与 `addons/omnibuff/docs/api.md` 中补齐对外 Public API/Stable API 文档（OmniBuff singleton、deal_damage_v1、BONUS_DAMAGE value/ratio/expr、不递归 guard、常见坑）。

**Architecture:** README 只加一节 TL;DR + 链接；api.md 扩写成权威文档，包含签名、示例与 pitfalls。文档内容以当前实现为准，并在示例中统一用 OmniBuff singleton 与 v1 wrapper。

**Tech Stack:** Markdown（无代码变更；仅文档）。

---

## 0) 文件清单

- Modify: `godot-buff/addons/omnibuff/README.md`
- Modify: `godot-buff/addons/omnibuff/docs/api.md`

---

## Task 1：扩写 api.md（权威文档）

**Files:**
- Modify: `godot-buff/addons/omnibuff/docs/api.md`

- [ ] **Step 1: 增加“OmniBuff singleton”章节**
列出并示例：
- `OmniBuff.BuffCore`
- `OmniBuff.DamagePipeline`
- `OmniBuff.Replay`
- `OmniBuff.BattleExecutor`
- `OmniBuff.CommandContext`
- `OmniBuff.ExprContext`

- [ ] **Step 2: 增加“Stable API：deal_damage_v1”章节**
示例（强调命名参数优先）：

```gdscript
var pipe := OmniBuff.DamagePipeline.new()
var ctx := pipe.deal_damage_v1(
    attacker_stats,
    defender_stats,
    attacker_buffs,
    defender_buffs,
    ds,
    10.0,
    replay,
    1,          # turn_index
    0,          # tags_mask
    runtime,
    0,          # roll_key
    -1,         # skill_id
    0,          # damage_type
    0           # element
)
```

- [ ] **Step 3: BONUS_DAMAGE 文档**
分别给出：
- value
- ratio
- expr
并强调互斥与 `filters.require_not_bonus_damage`（不递归）

- [ ] **Step 4: pitfalls**
列出：
- 不要依赖 class_name（用 OmniBuff.Xxx / preload）
- 不要到处位置参数调用易变签名（用 deal_damage_v1）

- [ ] **Step 5: Commit**

```bash
git -C godot-buff add addons/omnibuff/docs/api.md
git -C godot-buff commit -m "docs(api): document public and stable APIs"
```

---

## Task 2：README TL;DR（Quickstart + 链接）

**Files:**
- Modify: `godot-buff/addons/omnibuff/README.md`

- [ ] **Step 1: 新增一节 Public API / Stable API（TL;DR）**
包含：
- 1 个最小示例（创建 pipeline + 调用 deal_damage_v1）
- 1 个最小 BONUS_DAMAGE 示例（JSON 片段）
- 链接到 `addons/omnibuff/docs/api.md`

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/README.md
git -C godot-buff commit -m "docs(readme): add public API quickstart"
```

---

## 最终检查

- [ ] README 示例不引用 class_name（全用 OmniBuff.Xxx）
- [ ] api.md 对 value/ratio/expr/guard 的说明与 validators 现状一致（互斥规则）

