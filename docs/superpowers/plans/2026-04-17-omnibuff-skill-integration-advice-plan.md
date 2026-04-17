# OmniBuff Skill Integration Advice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `integrator_guide.md` 增加《技能系统接入建议》章节，提供 roll_key/skill_id/damage_type/element/tags_mask 的约定与完整示例，帮助后续技能与战斗系统接入 OmniBuff。

**Architecture:** 仅文档变更：在 Integrator Guide 追加章节；必要时在 `api.md` 增加到该章节的链接。

**Tech Stack:** Markdown。

---

## Task 1：更新 Integrator Guide（新增第 9 章）

**Files:**
- Modify: `godot-buff/addons/omnibuff/docs/integrator_guide.md`

- [ ] **Step 1: 增加目录项**

在文档目录加入：
- `9. 技能系统接入建议（skill_id/damage_type/element/tags_mask/roll_key）`

- [ ] **Step 2: 新增章节内容（建议结构）**

新增：

### 9.1 建议你在技能系统里维护的“编译表”
- `skill_id`（int）：用于 filters.skill_id
- `damage_type`（int）：用于 filters.damage_type_any（与 enums.json 对齐）
- `element`（int）：用于 filters.element_any（与 enums.json 对齐）
- `tags_mask`（int）：用于 tag_mask_any 与回放识别（建议包含 `BUFF/SKILL/BONUS_DAMAGE` 等 tag）

### 9.2 roll_key：确定性 RNG 的“唯一键”

给出模板（纯函数）：

```gdscript
func make_roll_key(cast_seq: int, target_index: int, hit_index: int, kind: int) -> int:
	# kind: 0=base_hit, 1=bonus, 2=dot_trigger, 3=proc
	return cast_seq * 100000 + kind * 10000 + target_index * 100 + hit_index
```

并强调：
- target_index 必须来自稳定排序（eid 升序）
- 多段/多目标/追加必须保证 roll_key 不冲突

### 9.3 多段/多目标（ALL）的调用模板

给出循环模板（伪代码）：
- 目标列表稳定排序
- 每段调用一次 `deal_damage_v1`（或 `deal_damage` 并显式传 roll_key/skill_id/damage_type/element）

### 9.4 BONUS_DAMAGE 与不递归 guard

说明两种情况：
1) 由 buff action BONUS_DAMAGE 触发：必须配置 `require_not_bonus_damage=true`，并由 pipeline 自动传 `is_bonus_damage` 给事件系统
2) 若技能脚本直接调用 `deal_damage` 作为 bonus：必须传 `is_bonus_damage=true`，并建议 tags_mask 包含 `BONUS_DAMAGE`

### 9.5 完整示例：多目标 + 多段 + bonus（可复制）

提供一个函数 `cast_triple_slash_all(...)` 示例：
- 输入：caster_id、targets(Array[int])、cast_seq、ds/enums_rt、pipe、replay、runtime、buffs/stats 映射
- 行为：对 targets（eid 排序）三段伤害；第二段额外触发一次 bonus hit（is_bonus_damage=true）

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/docs/integrator_guide.md
git -C godot-buff commit -m "docs: add skill integration advice"
```

---

## Task 2：可选更新 api.md（加链接）

**Files:**
- Modify: `godot-buff/addons/omnibuff/docs/api.md`

- [ ] **Step 1: 在 0.4 扩展能力索引补一条链接**

新增一行：
- `技能系统接入建议：integrator_guide.md#9-技能系统接入建议`

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/docs/api.md
git -C godot-buff commit -m "docs: link skill integration advice from api"
```

