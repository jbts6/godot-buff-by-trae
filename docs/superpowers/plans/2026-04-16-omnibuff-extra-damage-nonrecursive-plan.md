# OmniBuff Bonus Damage (Non-recursive) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现一个可配置的“追加伤害（BONUS_DAMAGE）”事件动作，并通过 `ctx.meta.is_bonus_damage` + filter `require_not_bonus_damage` 保证追加不递归触发追加；支持 multi-hit/multi-target，并提供 tests+demo 验收。

**Architecture:** 追加伤害挂在 `DAMAGE/AFTER_DEAL`；动作内部通过 runtime 取到 `pipeline/ds/enums_rt`，再调用一次 `deal_damage` 产生新的 DamageContext，并在其 meta 中标记 `is_bonus_damage=true`。过滤链上新增 `require_not_bonus_damage` 来跳过 bonus damage 的触发器。

**Tech Stack:** Godot 4.7 + GDScript + OmniBuffCore + OmniDamagePipeline + validators + GUT + buff_ui_demo。

---

## 0) 文件清单

- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`（Listener 新字段：filter + action payload）
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`（解析 filters/action + emit_event 执行 + BONUS_DAMAGE 实现）
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`（白名单与规则）
- Modify: `godot-buff/addons/omnibuff/runtime/core/battle_executor.gd`（runtime 注入 pipeline/ds/enums_rt）
- Modify: `godot-buff/data/base_demo/enums.json`（action_kind 增加 BONUS_DAMAGE；可选新增 tag BONUS_DAMAGE）
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`（新增测试 buff）
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_bonus_damage_nonrecursive.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_bonus_damage_nonrecursive.gd.uid`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

---

## Task 1：写 failing tests（RED）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_bonus_damage_nonrecursive.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_bonus_damage_nonrecursive.gd.uid`

- [ ] **Step 1: 写测试**

场景：
- attacker 对 defender 造成一次伤害（base_damage=10）
- attacker 挂 buff：DAMAGE/AFTER_DEAL → BONUS_DAMAGE(value=3) 且 filters.require_not_bonus_damage=true
- 断言：
  - replay.damage_traces +2（原伤害+追加）
  - 不会变成 +3（追加不再触发追加）

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_bonus_damage_nonrecursive.gd addons/omnibuff/tests/rpg/test_bonus_damage_nonrecursive.gd.uid
git -C godot-buff commit -m "test(bonus): add failing coverage for non-recursive bonus damage"
```

---

## Task 2：enums 增量（BONUS_DAMAGE）

**Files:**
- Modify: `godot-buff/data/base_demo/enums.json`

- [ ] **Step 1: action_kind 增加 BONUS_DAMAGE**
- [ ] **Step 2 (可选): tags 增加 BONUS_DAMAGE**

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add data/base_demo/enums.json
git -C godot-buff commit -m "feat(enums): add bonus damage action"
```

---

## Task 3：EventIndex Listener 扩展字段

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`

- [ ] **Step 1: filters**
新增：
- `filter_require_not_bonus_damage: bool = false`

- [ ] **Step 2: action payload**
新增：
- `action_bonus_tags_mask_any: int = 0`（由 tags_mask_any 编译得来）
- `action_bonus_scope: String = "TARGET"`

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/event_index.gd
git -C godot-buff commit -m "feat(event): extend listener for bonus damage"
```

---

## Task 4：BuffCore 解析 + 执行动作

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 注册解析**
在 `_register_triggers_for_instance`：
- 解析 `filters.require_not_bonus_damage`
- 解析 `action.tags_mask_any`（转 bitmask 存到 listener.action_bonus_tags_mask_any）
- 解析 `action.scope`（存到 listener.action_bonus_scope）

- [ ] **Step 2: emit_event filter**
在 emit_event 中：
- 若 `l.filter_require_not_bonus_damage` 为 true 且 `ctx.get_meta("is_bonus_damage")==true` → continue

- [ ] **Step 3: 实现 BONUS_DAMAGE**
新增 `_bonus_damage_from_event(l, ctx)`：
- 从 ctx.meta["runtime"] 取：stats_by_entity/buff_by_entity/pipeline/ds/enums_rt
- 目标：用 `l.action_bonus_scope` 解析到 entity_id（TARGET/SELF/SOURCE）
- 调用 `pipeline.deal_damage(..., base_damage=l.action_value, roll_key=ctx.roll_key+10000, skill_id=ctx.skill_id, tags_mask=ctx.tags_mask | l.action_bonus_tags_mask_any)`
- 在新 ctx 上 set_meta("is_bonus_damage", true)

- [ ] **Step 4: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff commit -m "feat(bonus): implement non-recursive bonus damage action"
```

---

## Task 5：BattleExecutor runtime 注入

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/battle_executor.gd`

- [ ] **Step 1: runtime 扩展**
在 `ctx.set_meta("runtime", runtime)` 前，构造一个扩展 runtime（复制字典）：
- stats_by_entity
- buff_by_entity
- pipeline
- ds
- enums_rt
- turn_index

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/battle_executor.gd
git -C godot-buff commit -m "feat(bonus): inject pipeline into runtime for event actions"
```

---

## Task 6：validators + rpg_tests buff_defs

**Files:**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: validators**
- 放行 filter `require_not_bonus_damage`
- 放行 action kind `BONUS_DAMAGE` 及字段（value/tags_mask_any/scope）

- [ ] **Step 2: rpg_tests 新增 buff**
新增 `buff_bonus_damage_3_nonrecursive`：
- event: DAMAGE/AFTER_DEAL
- filters: require_not_bonus_damage=true
- action: BONUS_DAMAGE(value=3, tags_mask_any=["BONUS_DAMAGE"])

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/config/compiler/validators.gd data/rpg_tests/buff_defs.json
git -C godot-buff commit -m "feat(validate): support bonus damage and add test buff"
```

---

## Task 7：Demo scenario

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: 新增 scenario bonus_damage_nonrecursive**
用 executor 触发一次攻击，展示日志中 damage trace +2，且第二条为 bonus（tags 或 meta 标记）

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m "feat(demo): add non-recursive bonus damage scenario"
```

---

## 最终验证

- [ ] `test_bonus_damage_nonrecursive.gd` 全绿
- [ ] 抽样跑 `test_battle_executor_multihit_multitarget.gd` 仍绿
- [ ] demo 场景可复现并能解释“为什么不递归”

