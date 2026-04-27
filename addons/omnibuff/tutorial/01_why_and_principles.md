# 01 — 设计原理与设计思想（Why & Principles）

本章回答三个问题：

1) 为什么要做“Buff 插件”，而不是把逻辑散落在技能/角色脚本里？  
2) OmniBuff 的设计取舍是什么（性能、数据驱动、可回归）？  
3) 你读代码时应该怎么建立心智模型（哪些是边界、哪些是热路径）？

---

## 1. 一张图看整体：数据 → 编译 → 运行时

```mermaid
flowchart TD
  subgraph Data[数据层（可编辑）]
    M[manifest.json]
    E[enums.json]
    S[stat_defs.json]
    B[buff_defs.json]
  end

  subgraph Load[加载/校验/编译（冷路径）]
    L[ManifestLoader.load_dataset_full]
    V[Validate.validate_all]
    C[DatasetCompiler.compile]
    DS[CompiledDataset (只读)]
  end

  subgraph Runtime[运行时（热路径）]
    ST[StatsComponent/StatsCore\nStatCache]
    BU[BuffCore\nBuffInst + DotInstance]
    EV[EventIndex\nlisteners subset]
    DP[DamagePipeline\nfixed stages]
    TU[TurnComponent\nTURN_START tick DOT]
    RP[Replay (output-only)]
  end

  Data --> L --> V --> C --> DS
  DS --> ST
  DS --> BU
  ST --> DP
  BU --> DP
  EV --> BU
  DP --> RP
  TU --> BU
```

核心思想：
- **数据层可变**（配置/策划可写），但进入运行时前必须 **validate + compile**  
- 运行时只依赖 `CompiledDataset`（只读结构），避免在热路径反复解析 JSON 字段

---

## 2. 为什么“万物皆 Buff”

传统项目里你常见到：
- 装备加成写在装备系统
- 被动/光环写在技能系统
- DOT 写在状态系统
- 护盾写在角色脚本

这会导致：
- 规则分散：同一类效果（例如“加攻击”）在多个系统重复实现
- 叠加顺序难维护：到底先算装备还是先算 buff？
- 很难回归：改一处可能影响所有模块，但测试/可视化不足

“万物皆 Buff”的意思是：
- 让“加成/减益/触发器/持续效果”都落到同一套 **数据驱动 + 运行时核心** 中
- 上层战斗系统只负责：**决定何时触发什么事件**（例如死亡/复活/技能命中），以及组织实体对象与回合

---

## 3. 三条硬约束（读代码一定要记住）

### 3.1 性能硬约束：禁止全量遍历

在战斗热路径中，常见的大坑是：
- 每次结算都遍历“全场 buff”或“全体单位”
- 每次读属性都临时把所有 modifier 重新算一遍

OmniBuff 的核心对策：

1) **StatCache（StatsCore）**
- 属性只允许通过 `StatsComponent.get_final(stat_id)` 读取
- dirty 才重算，否则直接读缓存

2) **EventIndex（监听子集）**
- `BuffCore.emit_event(...)` 只遍历“监听该 event_type/event_phase 的 listeners 子集”
- 明确禁止在事件中遍历 runtime 全实体 keys

你会在代码里看到类似注释：
- `PERF(J2)：禁止遍历全实体 keys`

### 3.2 数据驱动边界：Compiler vs Runtime

约定：
- Parser/Compiler 层可以读 raw JSON/CSV 字段（这是 schema 允许出现的边界）
- Runtime（Stats/Buff/Damage）只允许读 `CompiledDataset`（即 `ds`）

这样做的收益：
- 运行时逻辑更稳定：不被“字段名变更/文件格式变更”影响
- 更容易把性能优化集中在编译产物上（未来可以把 Dictionary 改成紧凑结构）

### 3.3 确定性与回归：roll_key + Replay output-only

OmniBuff 希望你能做到：
- “同输入同输出”（至少在同版本、同平台、同排序下）

关键机制：
- 命中/暴击采用确定性 RNG（xorshift32），种子组合里包含 `roll_key`
- `Replay` 只记录输出（output-only），不参与逻辑驱动

因此：
- 你写技能系统时必须认真对待 `roll_key`（见 integrator_guide 第 9 章）

---

## 4. 为什么不推荐依赖 class_name

Godot 的全局类表（class_name）由编辑器扫描/缓存生成：
- 插件开发/集成过程中，经常遇到“脚本文件存在但 class_name 尚未被缓存”的解析期报错

因此 OmniBuff 的推荐使用方式是：
- 启用插件后通过 Autoload `OmniBuff`（命名空间入口）访问 Script 资源
- 或者业务侧用 `preload("res://...")` 显式引用

---

## 5. 读代码的“入口导航”

如果你要理解插件怎么跑：

1) **数据集加载**：`config/manifest_loader.gd`  
2) **校验规则**：`config/compiler/validators.gd`  
3) **编译产物**：`config/compiler/dataset_compiler.gd` → `runtime/core/compiled_data.gd`  
4) **属性系统**：`runtime/core/stats_core.gd` + `runtime/components/stats_component.gd`  
5) **buff 系统**：`runtime/core/buff_core.gd`（包含 DotInstance / event/action 执行）  
6) **伤害流水线**：`runtime/core/damage_pipeline.gd`  
7) **回合 tick**：`runtime/components/turn_component.gd`  
8) **调试与回归**：`demo/buff_ui_demo.tscn` + `demo/debug_hud.tscn` + `tests/`

---

## 本章小结

你现在应该能回答：
- 为什么 OmniBuff 强调数据驱动边界与性能约束
- 为什么要用 EventIndex + StatCache，而不是遍历全量
- 为什么 roll_key 是“确定性”的关键

下一章：去跑通一次最小闭环（加载数据集 → 上 buff → 结算一次伤害）。  
继续阅读：`02_quickstart_run_a_hit.md`

