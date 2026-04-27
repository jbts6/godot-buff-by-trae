# 04 — Stats 系统：StatCache、分层、breakdown、derived/curve

本章目标：
- 让你理解“属性是怎么被算出来的”
- 让你知道为什么必须通过 `get_final()`（而不是自己算）
- 让你能在 UI 面板展示 `base/bonus/final`
- 让你理解 Phase 2 的 `derived/curve` 是怎么接进来的

---

## 1. 组件与职责

- `StatsComponent`：面向实体（Actor/Unit）的外壳，提供 OOP API
- `StatsCore`：真正的缓存与重算逻辑（base/final/dirty/modifiers）

代码位置：
- `res://addons/omnibuff/runtime/components/stats_component.gd`
- `res://addons/omnibuff/runtime/core/stats_core.gd`

---

## 2. 为什么要做 StatCache（dirty + recompute）

如果每次读取 HP/ATK 都遍历全部 buff/modifier：
- 一场战斗会产生大量重复计算
- 性能随着“buff 数量 × 读取次数”爆炸

StatCache 的策略：
- **写入时标记 dirty**
- **读取时按需重算**
- 非 dirty 时直接读缓存

```mermaid
flowchart TD
  W[base/modifier 发生变化] --> D[mark_dirty(stat_id)]
  D --> R[get_final(stat_id)]
  R -->|dirty=1| C[recompute(stat_id)]
  R -->|dirty=0| V[return cached final]
  C --> V
```

---

## 3. 当前 Stats 计算管线（Phase/bucket 顺序）

OmniBuff 当前实现的关键顺序（与代码一致）：

1) `BASE`：`base_values + computed_base(derived)`  
2) `FLAT`：累加 `ADD/FLAT`  
3) `PERCENT`：按 `layer` 聚合并按 layer 升序依次乘：`v *= (1+pct[layer])`  
4) `OVERRIDE`：`OVERRIDE/FINAL` 取 priority 最大（同 priority 取 source_inst_id 最大）  
5) `FINAL_ADD`：累加 `ADD/FINAL`  
6) `CURVE`：曲线变换（默认 POST_FINAL，在 clamp 前）  
7) `CLAMP`：若定义 `clamp/min/max`，最后 clamp  

示意图：

```mermaid
flowchart LR
  A[BASE] --> B[+FLAT]
  B --> C[*PERCENT layers]
  C --> D[OVERRIDE?]
  D --> E[+FINAL_ADD]
  E --> F[CURVE]
  F --> G[CLAMP]
  G --> OUT[final]
```

---

## 4. modifiers 从哪里来？

`BuffCore` 在 buff 激活/失活时，会把该 buff 的 effects（modifier）注入到 StatsCore：
- 注入到 `modifiers_by_stat[stat_id]`
- 并对相关 stat 调用 `mark_dirty(stat_id)`

你在 runtime 里不需要“查所有 buff 再算一遍”，因为 StatsCore 已经维护了 per-stat 的 modifier 聚合列表。

---

## 5. UI 面板：get_breakdown(base/bonus/final)

Phase 2 提供：
- `StatsComponent.get_breakdown(stat_id) -> {"base","bonus","final"}`

定义：
- `base = base_values + computed_base(derived)`
- `final = 完整管线后的值`
- `bonus = final - base`

示例：

```gdscript
var hp_id := ds.stat_id("HP")
var bd := actor_stats.get_breakdown(hp_id)
ui.set_hp_final(float(bd["final"]))
ui.set_hp_detail(float(bd["base"]), float(bd["bonus"]))
```

> 注意：如果某个 stat 配置了曲线（例如 DR_SOFTCAP），bonus 会包含曲线变换造成的差值，这是预期的“最终相对基础的变化”。

---

## 6. derived（派生/转换）是怎么工作的？

Phase 2 允许在 `stat_defs.json` 上写：

```jsonc
{ "id": "HP", "default": 100, "derived": { "type":"LINEAR", "from":"STR", "ratio":20.0 } }
```

语义：`HP.base += STR.final * ratio`

实现要点：
- DatasetCompiler 会把 derived 规则编译成依赖图（inputs/dependents/topo_order）
- StatsCore 在重算某个 stat 时，会先根据 derived 规则更新 `computed_base[stat_id]`
- 并且对依赖传播 dirty：STR 变化会让 HP dirty

---

## 7. curve（曲线/DR）是怎么工作的？

Phase 2 支持最小曲线集：
- `DR_SOFTCAP`：`x/(x+k)`
- `EXP`、`LOG`（用于更自由的数值曲线）

它们在 recompute 的末尾（clamp 前）应用。

例子（DR）：

```jsonc
{ "id":"DMG_REDUCE_RATING", "default":0, "curve": { "type":"DR_SOFTCAP", "k":100 } }
```

当 base=100 时：`100/(100+100)=0.5`

---

## 本章小结

你现在应该能：
- 理解为什么 Stats 必须走缓存
- 理解 flat/pct(layer)/override/final_add/curve/clamp 的顺序
- 在 UI 面板展示 base/bonus/final
- 理解 derived/curve 为什么属于“Phase 2 数值表达能力”

下一章：Buff 与事件系统（EventIndex、filters/actions、LIFE/STACKS）。  
继续阅读：`05_buff_and_events.md`

