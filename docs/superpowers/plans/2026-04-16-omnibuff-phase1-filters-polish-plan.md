# OmniBuff Phase 1 Filters Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补齐 Phase 1 filters 的“可交付完成度”：完善 skill_id/min_absorbed_shield 的端到端覆盖（tests + demo + docs），并增加更多负例回归，降低后续 Phase 1 action/events 扩展的回归风险。

**Architecture:** 在既有 filters 运行时实现基础上做增量：扩展测试用 buff_defs 与 rpg_tests 用例；补齐 demo scenario；更新 README 的 filters 清单与阶段说明。核心 runtime 仅做必要的小修（如果发现边界不一致）。

**Tech Stack:** Godot 4.7 + GDScript + OmniDamagePipeline + OmniBuffCore + GUT。

---

## 0) 文件清单

- Modify: `godot-buff/addons/omnibuff/tests/rpg/test_event_filters_extended.gd`
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`
- Modify: `godot-buff/addons/omnibuff/README.md`

（可选）若发现 validators 需要更强提示：
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`

---

## Task 1：测试补齐（RED）

**Files:**
- Modify: `godot-buff/addons/omnibuff/tests/rpg/test_event_filters_extended.gd`

- [ ] **Step 1: 新增 skill_id 过滤测试（正例 + 反例）**

新增测试：
```gdscript
func test_skill_id_filter() -> void:
    # defender 挂一个：filters.skill_id=1001 才触发的 buff（例如 APPLY_BUFF buff_dummy_mark_1）
    # 1) skill_id=1001 -> 触发
    # 2) skill_id=2002 -> 不触发
```

- [ ] **Step 2: 新增 min_absorbed_shield 测试（正例 + 反例）**

新增测试：
```gdscript
func test_min_absorbed_shield_filter() -> void:
    # defender 初始 shield=0，并挂 buff：AFTER_TAKE + min_absorbed_shield=20 -> APPLY_BUFF mark
    # A) shield=10, damage=10 => absorbed=10 < 20 -> 不触发
    # B) shield=50, damage=30 => absorbed=30 >= 20 -> 触发
```

- [ ] **Step 3: 运行并确认 RED（本地）**

运行：
```bash
./run_gut_tests.sh addons/omnibuff/tests/rpg/test_event_filters_extended.gd
```
Expected：FAIL（因为测试引用的 buff_id 尚未加入 buff_defs.json）。

- [ ] **Step 4: Commit（仅测试）**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_event_filters_extended.gd
git -C godot-buff commit -m "test(filters): add coverage for skill_id and min_absorbed_shield"
```

---

## Task 2：补齐测试用 buff_defs（GREEN）

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 新增两个测试 buff**

1) `buff_filter_skill_id_apply_mark`：
- event: DAMAGE / AFTER_TAKE
- filters: `skill_id: 1001`
- action: `APPLY_BUFF(buff_dummy_mark_1)`

2) `buff_filter_min_absorbed_shield_apply_mark`：
- event: DAMAGE / AFTER_TAKE
- filters: `min_absorbed_shield: 20`
- action: `APPLY_BUFF(buff_dummy_mark_1)`

> 注意：scope 选择 `SOURCE`（把 mark 挂到攻击者）或 `SELF`（挂到自己）二选一；测试里按所选一致断言。

- [ ] **Step 2: 运行测试确认 GREEN（本地）**

同 Task 1 Step 3 命令，Expected：PASS。

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add data/rpg_tests/buff_defs.json
git -C godot-buff commit -m "test(filters): add rpg_tests buff defs for skill_id and min_absorbed_shield"
```

---

## Task 3：补齐 demo scenario（验证可视化）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: 新增两个 scenario**

1) `filters_skill_id`：
- 运行两次 deal_damage：一次 skill_id=1001（应触发 mark），一次 skill_id=2002（不触发）
- HUD Listeners 能看到 skill_id=1001

2) `filters_min_absorbed_shield`：
- 先设置 shield=10 再打 10（不触发）
- 再设置 shield=50 再打 30（触发）
- HUD Listeners 能看到 min_absorbed>=20

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m "feat(demo): add scenarios for skill_id and min_absorbed_shield filters"
```

---

## Task 4：文档补齐（README filters 清单）

**Files:**
- Modify: `godot-buff/addons/omnibuff/README.md`

- [ ] **Step 1: 增加 filters 支持列表与阶段说明**

在 README 增加类似：
- require_hit / require_crit（全阶段可用）
- skill_id / damage_type_any / element_any（全阶段可用）
- min_final_damage（建议 APPLY/AFTER_*）
- absorbed_shield / min_absorbed_shield（建议 AFTER_TAKE）

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/README.md
git -C godot-buff commit -m "docs: document supported trigger filters and phases"
```

