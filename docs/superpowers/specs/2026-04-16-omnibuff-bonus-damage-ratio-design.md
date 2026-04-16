# OmniBuff：BONUS_DAMAGE 按最终伤害比例（ratio）设计

## 背景

当前已实现：
- `BONUS_DAMAGE` 事件动作（固定 value）
- `require_not_bonus_damage` 过滤 + `DamageContext.meta.is_bonus_damage` guard（防递归）

下一步你希望增强 BONUS_DAMAGE 的表达能力，优先支持：
- **按最终伤害比例**（例如 `bonus = final_damage * 0.3`）

---

## 目标

扩展 `BONUS_DAMAGE` 动作，支持两种来源：
1) `value`：固定值（现有）
2) `ratio`：按 `ctx.final_damage * ratio` 计算 bonus 基础伤害

并保持：
- 不递归（bonus 不再触发 bonus）
- 与 multi-hit / multi-target 兼容（每段都会触发一次 AFTER_DEAL，因此每段都能追加一次）

---

## 配置协议

### 1) 固定值（保持兼容）

```jsonc
{
  "kind": "BONUS_DAMAGE",
  "value": 3.0,
  "tags_mask_any": ["BONUS_DAMAGE"],
  "scope": "TARGET"
}
```

### 2) 比例（新增）

```jsonc
{
  "kind": "BONUS_DAMAGE",
  "ratio": 0.3,
  "min_damage": 1.0,              // 可选：低于阈值不触发
  "max_damage": 999999.0,         // 可选：上限 clamp
  "round_mode": "FLOOR",          // 可选：FLOOR|ROUND|CEIL|NONE（默认 NONE）
  "tags_mask_any": ["BONUS_DAMAGE"],
  "scope": "TARGET"
}
```

语义：
- `bonus_base = ctx.final_damage * ratio`
- 应用 min/max/round_mode（如配置）
- `bonus_base <= 0` 视为 no-op

---

## 运行时行为（核心）

触发位置仍建议：
- `event_type=DAMAGE`，`event_phase=AFTER_DEAL`

原因：
- AFTER_DEAL 已具备 `ctx.final_damage`
- 可表达“每次造成伤害追加xx%”的被动

计算完成后，执行一次 `deal_damage`：
- base_damage = bonus_base
- is_bonus_damage = true（在 pipeline 内提前写入 meta）
- roll_key = ctx.roll_key + 20000（与固定 value 的 +10000 区分，避免同段冲突）
- tags_mask = (ctx.tags_mask | action.tags_mask_any)

---

## validators 扩展

- action: BONUS_DAMAGE
  - `ratio`：0 < ratio <= 10（先给一个宽松上限）
  - `value` 与 `ratio` 至少出现一个；若都出现，优先 ratio（或报错，建议报错更安全）
  - round_mode 若提供必须是枚举值

---

## 测试与 Demo（验收）

### Tests
新增 `test_bonus_damage_ratio_nonrecursive.gd`：
- attacker 对 defender 造成一次伤害（例如 base_damage=40，且确保 final_damage>0）
- attacker 挂 buff：AFTER_DEAL → BONUS_DAMAGE(ratio=0.5) + require_not_bonus_damage=true
- 断言：
  - traces +2
  - 第 2 条 trace.base_damage 约等于 `trace1.final_damage * 0.5`（按 round_mode 决定比较策略）

### Demo
新增 scenario：`bonus_damage_ratio_nonrecursive`
- 展示两条 trace，并打印 `bonus_expected` 与 `bonus_actual`

---

## 非目标

- 不支持按 ATK 等 stat（下一轮）
- 不引入表达式系统

