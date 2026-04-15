# Docs (K1~K3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收尾 K（文档）：补齐 README（K1）、新增 API 契约文档（K2）、补齐版本与兼容策略（K3），并同步更新 checklist。

**Architecture:** 先更新 README（校对结构与命令），再新增 `api.md`，最后更新 checklist 勾选 K1~K3。

**Tech Stack:** Markdown + Git。

---

## 0) 文件清单

**README：**
- Modify: `godot-buff/addons/omnibuff/README.md`

**API 文档：**
- Create: `godot-buff/addons/omnibuff/docs/api.md`

**checklist：**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

---

## Task 1：更新 README（K1 + K3）

**Files:**
- Modify: `godot-buff/addons/omnibuff/README.md`

- [ ] **Step 1: 校对测试目录结构**
把测试结构描述与你现在的目录对齐（例如：`tests/base/`、`tests/rpg/`、`tests/helpers/`）。

- [ ] **Step 2: 增加 Compatibility 小节（K3）**

在 README 末尾或合适位置新增：
```md
## Compatibility / Versioning

- Godot: 4.7 baseline (headless/CI should use the same major/minor)
- GUT: vendored at `res://addons/gut/` (repo version is the source of truth)
- Dataset schema_version: currently `1`
  - Upgrade strategy: online migration via `OmniMigrate.migrate(schema_from, schema_to, obj)` (no write-back)
- Tag codes: `tags.code` is a compatibility contract (only add, never reuse codes)
```

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add addons/omnibuff/README.md
git -C godot-buff commit -m "docs(k1/k3): refresh README and compatibility notes"
```

---

## Task 2：新增 API 契约文档（K2）

**Files:**
- Create: `godot-buff/addons/omnibuff/docs/api.md`

- [ ] **Step 1: 写文档（直接粘贴以下骨架并按需微调）**

```md
# OmniBuff API Contract (K2)

## 1) Load dataset (manifest → validate → compile)

```gdscript
var result = OmniBuff.ManifestLoader.load_dataset_full("res://data/base_demo/manifest.json", true)
var enums_rt = OmniBuff.EnumsRuntime.from_enums_json(result.enums)
var ds = OmniBuff.DatasetCompiler.compile(result.manifest, enums_rt, result.sources)
```

## 2) Runtime dict contract

Many event actions require a runtime dictionary to locate entities.

```gdscript
var runtime := {
  "stats_by_entity": { 101: attacker_stats, 202: defender_stats },
  "buff_by_entity":  { 101: attacker_buffs, 202: defender_buffs }
}
```

Requirements:
- `stats_by_entity`: `Dictionary[int, OmniStatsComponent]`
- `buff_by_entity`: `Dictionary[int, OmniBuffCore]`

## 3) Event scope semantics

Triggers use `scope` to resolve which entity is affected:
- `SELF`: the buff owner entity
- `SOURCE`: event source entity (attacker in DAMAGE)
- `TARGET`: event target entity (defender in DAMAGE)

## 4) DamageContext fields (used by Replay / filters / assertions)

`DamagePipeline.deal_damage(...)` produces `DamageContext` with at least:
- `attacker_id`, `defender_id`
- `hit`, `crit`
- `base_damage`, `final_damage`
- `tags_mask`

## 5) Replay/Trace is output-only

`OmniReplay` stores traces for debugging/regression and must not drive game logic.
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/docs/api.md
git -C godot-buff commit -m "docs(k2): add omnibuff api contract"
```

---

## Task 3：更新 checklist 勾选 K1~K3

**Files:**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

- [ ] **Step 1: 勾选 K1~K3 为 [x]**
- [ ] **Step 2: 提交**

```bash
git -C godot-buff add docs/superpowers/checklists/omnibuff-done-definition.md
git -C godot-buff commit -m "docs(checklist): mark K complete"
```

