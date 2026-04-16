# Stat 分段乘法（Percent Layers）设计（可扩展 N 段）

## 背景

当前 `OmniStatsCore.recompute()` 对百分比的处理是单桶累加：

> `final = (base + flat) * (1 + pct_sum) + final_add`

这无法表达你期望的“分段乘法/总加成乘法”：

> `(base + flat) * (1 + pct_items) * (1 + pct_total) * ...`

例如（base=10）：
- 武器 +10（flat）
- 被动 +5（flat）
- 饰品A +5%（pct_items）
- 饰品B +10%（pct_items）
- 宝物 **总**攻击力 +20%（pct_total）

期望：`(10 + 10 + 5) * (1 + 0.05 + 0.10) * (1 + 0.20) = 34.5`

---

## 目标

提供一个 **可扩展 N 段** 的百分比乘法模型，满足：

1) 支持多段乘法：`Π(1 + pct_layer_i)`
2) 对旧数据完全兼容：未设置 layer 的百分比按 layer=0 处理，行为不变
3) 数据驱动：通过 buff effect 的字段配置，无需代码加新 phase
4) 仍满足性能约束：只遍历 per-stat 的聚合 modifier 列表

---

## 方案（推荐）

### 1) 在 modifier 上新增可选字段 `layer:int`

对 `kind=modifier` 且 `op=MUL` `phase=PERCENT`：
- 新增字段：`layer`（非负 int）
- 默认：`layer=0`（字段缺省时）

示例：
```json
{ "kind":"modifier", "stat":"ATK", "op":"MUL", "phase":"PERCENT", "value":0.10, "layer":0 }
{ "kind":"modifier", "stat":"ATK", "op":"MUL", "phase":"PERCENT", "value":0.20, "layer":1 }
```

### 2) 计算规则（核心公式）

对某个 stat：
1) 累加 flat：`flat_sum`
2) 按 layer 分桶累加 percent：`pct_by_layer[layer] += value`
3) 顺序乘（layer 升序）：

```
v = base + flat_sum
for layer in sorted(pct_by_layer.keys()):
    v *= (1 + pct_by_layer[layer])
v = override? / final_add / clamp （保持现有语义）
```

### 3) 与 OVERRIDE / FINAL_ADD / clamp 的关系（保持现状）

保持当前顺序不变（只替换“百分比”部分）：

- 先算 `v = (base+flat) * Π(1+pct_layer)`
- 若存在 `OVERRIDE/FINAL`（按 priority 选胜者）：`v = override_v`
- `v += final_add`（ADD/FINAL）
- 若 stat_defs.clamp：做 clamp

---

## 兼容性策略

- 未设置 `layer` 的旧数据：视为 `layer=0`，与当前 `pct_sum` 完全等价
- validators：允许 `layer` 字段，并校验为 `int >= 0`（strict 时 error）

---

## 测试策略（必须）

新增 GUT：
- 构造实体（rpg_tests 默认 ATK=10）
- 施加 flat：+10、+5
- 施加 percent layer0：+5%、+10%
- 施加 percent layer1：+20%
- 断言 ATK 最终值约等于 34.5

---

## 非目标

- 不引入“任意表达式求值”的通用公式（expr）
- 不做性能基准（只做语义正确与兼容）

