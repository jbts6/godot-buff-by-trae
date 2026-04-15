# C（属性 phase/priority 完整化）设计（最小集）

## 目标（本轮最小集）

在不引入完整 phase 管线（BASE 等）的前提下，把属性系统做成**可预测、可回归**：

1) **priority 稳定排序**（同一 stat 的 modifiers 有确定顺序，跨平台一致）  
2) **OVERRIDE/FINAL**（表达“强制设定最终值”的常见 RPG 效果）  
3) **CLAMP**（按 `stat_defs.min/max/clamp` 对最终值裁剪，统一数值安全）  

并配套 **专门 GUT 单测**，满足“没单测就算未完成”的标准。

> OVERRIDE 冲突策略：采用 **方案 A**  
> - 选择 `priority` 最大的 OVERRIDE/FINAL 作为赢家  
> - priority 相同：选择“后施加”的（用 `source_inst_id` 更大作为 tie-break）  

---

## 现状与问题

当前 `StatsCore.recompute` 仅支持：
- `ADD/FLAT`
- `MUL/PERCENT`

并且：
- 不读取 modifier.priority
- 不支持 OVERRIDE
- 不执行 clamp（`stat_defs.clamp` 尚未生效）

因此：
- 多来源同 stat 的覆盖/互斥效果无法数据表达
- 最终值可能越界（概率类 >1、<0）
- 结果对“注入顺序/遍历顺序”敏感，难以保证可复盘

---

## 数据协议（沿用已有字段）

modifier effect 示例：

```json
{ "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 20.0 }
{ "kind": "modifier", "stat": "ATK", "op": "MUL", "phase": "PERCENT", "priority": 110, "value": 0.05 }
{ "kind": "modifier", "stat": "HIT_RATE", "op": "OVERRIDE", "phase": "FINAL", "priority": 900, "value": 0.0 }
```

本轮新增支持组合：
- `OVERRIDE/FINAL`
- （可选但低成本）`ADD/FINAL`：用于“最终伤害加成/最终命中修正”等

---

## Phase 顺序（最小集）

对单个 stat 的最终值计算顺序：

1. **FLAT**：累加 `ADD/FLAT`
2. **PERCENT**：累加 `MUL/PERCENT`，按公式应用
3. **FINAL**：
   - 选择赢家 OVERRIDE/FINAL（若存在）并覆盖
   - 然后再应用 `ADD/FINAL`（若支持）
4. **CLAMP**：若 `stat_defs[stat_id].clamp==true`，将最终值 clamp 到 `[min, max]`

公式（在 FINAL 前）：
```
v = (base + sum_flat) * (1 + sum_pct)
```

---

## priority 稳定排序规则

虽然 FLAT/PERCENT 是可交换的“求和”，但为了：
- 对 OVERRIDE/FINAL 的冲突做一致决策
- 为后续非交换操作（更多 phase/op）铺路

我们仍定义稳定排序键：

`sort_key = (phase_order, priority, source_inst_id)`

- `phase_order`: FLAT(10) < PERCENT(20) < FINAL(30) < CLAMP(40)
- `priority`: 数值越大，越“后”生效（即更强覆盖）
- `source_inst_id`: 作为 tie-break，越大表示越“后施加”（与方案 A 一致）

> 说明：当前实现可以只在 FINAL 的 OVERRIDE 选择处使用该排序，但单测会要求“选择逻辑稳定且可复盘”。

---

## OVERRIDE/FINAL 冲突策略（方案 A）

当一个 stat 同时存在多个 `OVERRIDE/FINAL`：

1) 取 `priority` 最大者  
2) priority 相同：取 `source_inst_id` 最大者（后施加覆盖先施加）  

赢家的 `value` 作为 FINAL 阶段的覆盖值：
```
v = override_value
```

然后（若实现）继续应用 `ADD/FINAL`：
```
v = v + sum_final_add
```

---

## CLAMP 语义

若 `stat_defs[stat_id]` 中：
- `clamp=true`
- 且存在 `min/max`

则在 FINAL 后执行：
```
v = clamp(v, min, max)
```

典型受益 stat：
- `CRIT_RATE`、`HIT_RATE`、`EVADE`（0..1）
- `DMG_REDUCE`（0..0.95）
- `HP`、`SHIELD`（>=0）

---

## 运行时改动点（高层）

### 1) OmniModifierRef 增加 priority 字段

- `priority: int`
- BuffCore 注入 modifier 时写入

### 2) BuffCore._rebuild_instance_modifiers 支持新组合

允许注入：
- `ADD/FLAT`
- `MUL/PERCENT`
- `OVERRIDE/FINAL`
- （可选）`ADD/FINAL`

### 3) StatsCore.recompute 实现 phase 管线 + override 选择 + clamp

对每个 stat：
- 扫描 `modifiers_by_stat[stat_id]`（只包含该 stat 的聚合列表）
- 聚合 flat/pct/final_add，并选出 override winner
- 应用公式与 clamp

---

## 测试策略（GUT，必须单测）

新增测试数据（建议放 `data/rpg_tests/buff_defs.json`）：
- `buff_c_override_hit_0_p900`（HIT_RATE OVERRIDE/FINAL=0, priority=900）
- `buff_c_override_hit_1_p800`（HIT_RATE OVERRIDE/FINAL=1, priority=800）
- `buff_c_final_add_hit_plus_0_2`（HIT_RATE ADD/FINAL +0.2, priority=950）
- `buff_c_clamp_hit_over_1`（HIT_RATE ADD/FLAT +2.0，验证最终 clamp 到 1.0）

新增测试文件（建议放 `addons/omnibuff/tests/rpg/`）：
1) `test_stat_priority_and_override.gd`
   - 两个 OVERRIDE 不同 priority：应取高 priority
   - 两个 OVERRIDE 同 priority：后施加（source_inst_id 大）应胜
2) `test_stat_clamp.gd`
   - HIT_RATE 被加到 >1：最终应 clamp 到 1
   - DMG_REDUCE 被加到 >0.95：最终 clamp 到 0.95（若 stat_defs 定义 max=0.95）

---

## 验收标准（C 最小集）

- priority 规则、OVERRIDE/FINAL、CLAMP 都有**单独 GUT**覆盖
- 现有 A/B、DamagePipeline、DOT、整回合集成测试不回归

