# OmniBuff BONUS_DAMAGE Expr Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `BONUS_DAMAGE` action 增加 `expr` 表达式，支持用 `Expression` 计算追加伤害（基于 final_damage、absorbed_shield、攻击者/受击者属性等），并保持不递归触发；提供 tests+demo 验收。

**Architecture:** 在 BuffCore 注册 trigger 时编译 expr（Expression.parse）；触发时组装变量输入并 execute 得到 base_damage，应用 min/max/round，再调用 `deal_damage(..., is_bonus_damage=true)`；validators 放行并校验 expr 与互斥规则。

**Tech Stack:** Godot 4.7 + GDScript + Expression + OmniBuffCore + OmniDamagePipeline + validators + GUT。

---

## 0) 文件清单

- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`（Listener 存 expr + 编译对象 + roll_key offset）
- Create: `godot-buff/addons/omnibuff/runtime/core/expr_context.gd`（安全 base_instance：暴露函数）
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`（解析/编译/执行 expr）
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`（放行 expr + 互斥校验）
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`（新增 expr 测试 buff）
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_bonus_damage_expr_nonrecursive.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_bonus_damage_expr_nonrecursive.gd.uid`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`（新增 expr 场景）

---

## Task 1：写 failing tests（RED）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_bonus_damage_expr_nonrecursive.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_bonus_damage_expr_nonrecursive.gd.uid`

- [ ] **Step 1: 测试用例（顺序无关）**
逻辑同 ratio 版：
- buff：`buff_bonus_damage_expr_50p_nonrecursive`（expr = "final_damage * 0.5"）
- 断言 traces +2
- 用 tags_mask(BONUS_DAMAGE) 判断哪条是 bonus
- 断言 `bonus.base_damage ~= base.final_damage * 0.5`

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_bonus_damage_expr_nonrecursive.gd addons/omnibuff/tests/rpg/test_bonus_damage_expr_nonrecursive.gd.uid
git -C godot-buff commit -m "test(bonus): add failing coverage for bonus damage expr"
```

---

## Task 2：EventIndex Listener 扩展 expr 字段

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`

- [ ] **Step 1: 新增字段**
在 Listener 增加：
- `action_bonus_expr: String = ""`
- `action_bonus_expr_inputs: PackedStringArray = PackedStringArray()`（固定变量名表）
- `action_bonus_expr_obj: RefCounted = null`（Expression 实例）

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/event_index.gd
git -C godot-buff commit -m "feat(bonus): add expr fields to listener"
```

---

## Task 3：新增安全 Expression context

**Files:**
- Create: `godot-buff/addons/omnibuff/runtime/core/expr_context.gd`

- [ ] **Step 1: 提供白名单函数**

```gdscript
class_name OmniExprContext
extends RefCounted

func min(a: float, b: float) -> float: return minf(a,b)
func max(a: float, b: float) -> float: return maxf(a,b)
func clamp(x: float, lo: float, hi: float) -> float: return clampf(x, lo, hi)
func floor(x: float) -> float: return floorf(x)
func ceil(x: float) -> float: return ceilf(x)
func round(x: float) -> float: return roundf(x)
func abs(x: float) -> float: return absf(x)
```

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/expr_context.gd
git -C godot-buff commit -m "feat(expr): add safe expression context"
```

---

## Task 4：BuffCore 编译与执行 expr

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 注册解析**
在 BONUS_DAMAGE 分支解析：
- `expr` 字符串
- 若存在 expr：创建 Expression，使用固定 inputs 列表 parse；失败则 listener.active=false 并 push_error

- [ ] **Step 2: 执行**
在 `_bonus_damage_from_event`：
- 若 `l.action_bonus_expr_obj != null`：
  - 组装 inputs 数组（与 inputs 名单对齐），包含：
    - base_damage/final_damage/absorbed_shield/dmg_reduce_ratio/turn_index/roll_key
    - atk/def/hp/shield/crit_rate/crit_dmg/hit_rate/evade/dmg_reduce
    - t_atk/...（目标）
  - `bd = expr.execute(inputs, OmniExprContext.new(), true)`
  - base_offset=30000（expr）

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff commit -m "feat(bonus): support expr-based bonus damage"
```

---

## Task 5：validators + rpg_tests buff_defs

**Files:**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: validators**
- 放行 `expr`
- 校验 value/ratio/expr 互斥且必须存在一个
- 校验 expr 非空/长度 <=256/字符白名单（可选）

- [ ] **Step 2: 新增 buff**
`buff_bonus_damage_expr_50p_nonrecursive`：
- event: DAMAGE/AFTER_DEAL
- filters: require_not_bonus_damage=true
- action: BONUS_DAMAGE(expr="final_damage*0.5", tags_mask_any=["BONUS_DAMAGE"])

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/config/compiler/validators.gd data/rpg_tests/buff_defs.json
git -C godot-buff commit -m "feat(validate): support bonus damage expr and add test buff"
```

---

## Task 6：Demo scenario

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: bonus_damage_expr_nonrecursive**
输出 expr、expected、actual，并 dump trace range。

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m "feat(demo): add bonus damage expr scenario"
```

---

## 最终验证

- [ ] `test_bonus_damage_expr_nonrecursive.gd` 全绿
- [ ] ratio/value 两个 bonus 测试仍绿
- [ ] demo 三个 bonus 场景都可复现

