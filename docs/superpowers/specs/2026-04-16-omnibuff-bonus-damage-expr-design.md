# OmniBuff：BONUS_DAMAGE 自定义表达式（expr）设计

## 背景

当前已实现：
- `BONUS_DAMAGE`（固定 `value`）
- `BONUS_DAMAGE`（按 `final_damage * ratio`）
- 防递归：`filters.require_not_bonus_damage` + `DamageContext.meta.is_bonus_damage`

你希望下一步把 BONUS_DAMAGE 做到更灵活：用 **自定义表达式 expr** 来描述追加伤害数值来源。

---

## 目标

扩展 `BONUS_DAMAGE` action：
- 新增字段 `expr: String`
- 用 expr 计算 `bonus_base_damage`
- 仍保持：
  - 不递归触发
  - 兼容 multi-hit / multi-target（每次 AFTER_DEAL 都可触发一次）
  - 兼容现有 `value`/`ratio`（但互斥：三者只能选其一）

---

## 设计方案（推荐）

### 1) 表达式引擎：使用 Godot 内置 `Expression`

原因：
- 自带解析与执行（无需自研 parser）
- 性能可接受（**注册时编译一次**，触发时只 execute）

实现要点：
- 在 `_register_triggers_for_instance` 阶段：`Expression.new().parse(expr, input_names)`；失败则 `push_error` 并把该 listener `active=false`
- 在 `_bonus_damage_from_event` 阶段：组装 inputs 数组（与 input_names 对齐），调用 `expr.execute(inputs, base_instance, true)` 得到数值

> base_instance 使用一个“安全上下文对象”，只暴露少量允许的函数（min/max/clamp/floor/ceil/round 等），避免 expression 调到不该调的方法。

---

## 协议（action schema）

### BONUS_DAMAGE（expr）

```jsonc
{
  "kind": "BONUS_DAMAGE",
  "expr": "final_damage * 0.3 + absorbed_shield",
  "min_damage": 0.0,             // 可选：<min 直接不触发（或 clamp，见实现约定）
  "max_damage": 999999.0,        // 可选：上限 clamp
  "round_mode": "NONE",          // 可选：NONE|FLOOR|ROUND|CEIL
  "tags_mask_any": ["BONUS_DAMAGE"],
  "scope": "TARGET"
}
```

互斥约束：
- `value` / `ratio` / `expr` 三者 **必须且只能**提供一个

---

## expr 可用变量（第一版：更开放）

### 伤害上下文
- `base_damage`：本次原始 base（float）
- `final_damage`：本次最终生效伤害（float；AFTER_DEAL 可用）
- `absorbed_shield`：本次被护盾吸收的量（float；没有则 0）
- `dmg_reduce_ratio`：本次减伤比例（float；没有则 0）
- `turn_index`（int）
- `roll_key`（int）

### 攻击者/受击者常用属性（final）

攻击者（attacker）：
- `atk`, `def`, `hp`, `shield`
- `crit_rate`, `crit_dmg`, `hit_rate`, `evade`, `dmg_reduce`

受击者（target）：
- `t_atk`, `t_def`, `t_hp`, `t_shield`
- `t_crit_rate`, `t_crit_dmg`, `t_hit_rate`, `t_evade`, `t_dmg_reduce`

> 说明：变量名刻意做短，方便写 expr；实际取值来自 `OmniStatsComponent.get_final(stat_id)`。

---

## expr 可用函数（第一版）

- `min(a,b)`, `max(a,b)`
- `clamp(x, lo, hi)`
- `floor(x)`, `ceil(x)`, `round(x)`
- `abs(x)`

---

## 执行语义

1) 触发位置：推荐 `DAMAGE/AFTER_DEAL`（因为需要 `final_damage`）
2) 计算 `bd = eval(expr)`
3) 应用 `min_damage/max_damage/round_mode`
4) 若 `bd <= 0` 则 no-op
5) 调用一次 `deal_damage(..., base_damage=bd, is_bonus_damage=true)`
   - roll_key 偏移：`ctx.roll_key + 30000`（与 value=10000、ratio=20000 区分）
   - tags_mask 合并：`ctx.tags_mask | action.tags_mask_any`

---

## validators 扩展

- 放行 `expr` 字段
- 校验：
  - expr 非空且长度 <= 256
  - value/ratio/expr 互斥且必须存在一个
  - round_mode 枚举合法
  - （可选）对 expr 做“字符白名单”过滤（仅允许字母数字下划线/空格/基础运算符/括号/逗号/小数点）

---

## 测试与 Demo（验收）

### Tests
新增 `test_bonus_damage_expr_nonrecursive.gd`：
- 使用 buff：`BONUS_DAMAGE(expr="final_damage*0.5")` + guard
- 断言 traces +2
- 用 tags_mask 识别 base/bonus（顺序不依赖）
- `bonus.base_damage ≈ base.final_damage * 0.5`

### Demo
新增 scenario：`bonus_damage_expr_nonrecursive`
- 打印 expr、base.final_damage、expected 与 actual

---

## 非目标

- 不开放任意对象/方法调用
- 不支持引用任意 stat 名称（如 `stat(\"ATK\")`）；第一版只支持固定变量集合

