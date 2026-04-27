# OmniBuff Tutorial（面向未做过 Buff 系统的 Godot 开发者）设计

## 背景与目标读者

目标读者：
- 熟悉 Godot/GDScript 基础
- 没做过（或很少做）Buff 系统
- 需要理解 OmniBuff 的设计思想、核心结构、以及如何接入/扩展/调试

目标：
1) 让读者能从“为什么这样设计”理解到“怎么用”，最终能读懂并改得动插件代码  
2) 通过 **章节拆分 + 可复制代码片段 + Mermaid 流程图**，降低阅读成本  
3) 和仓库当前实现保持一致（Phase 0~2：EventIndex、LIFE/STACKS、derived/curve、breakdown、ErrorList 等）

---

## 交付物（目录结构）

位置：`res://addons/omnibuff/tutorial/`

文件：
- `00_index.md`：总览 + 阅读路径 + “先跑起来”
- `01_why_and_principles.md`：设计思想（数据驱动/性能约束/可回归）
- `02_quickstart_run_a_hit.md`：最小闭环（加载数据集→上 buff→打一刀）
- `03_data_pipeline.md`：数据链路（manifest/enums/defs → validate → compile）
- `04_stats_system.md`：StatsCore/Cache、percent layers、override、breakdown、derived/curve
- `05_buff_and_events.md`：BuffCore、stack、EventIndex、filters/actions、LIFE、scope
- `06_damage_dot_turn_replay.md`：DamagePipeline、DOT、TurnComponent、Replay/Trace
- `07_debug_and_extend.md`：buff_ui_demo、HUD、ErrorList、如何加 scenario、如何加 tests、扩展 checklist

并在 `addons/omnibuff/README.md` 增加 tutorial 入口链接。

---

## 章节设计要点（内容原则）

每章都遵守：
- 先给“概念图”（Mermaid），再给“关键代码入口路径”
- 用 **最小可运行代码** 解释核心 API（避免伪代码过多）
- 明确约束（性能、确定性、不要依赖 class_name）
- 结尾给 “本章小结 + 下一章阅读建议”

### 必须覆盖的关键点

1) **为什么不用遍历全 Buff/全实体**
- 解释 EventIndex（listener 子集遍历）和 StatCache 的性能约束

2) **数据驱动边界**
- Parser/Compiler 层可读 raw 字段名；Runtime 只读 `OmniCompiledDataset`

3) **scope 与 runtime dict 契约**
- `runtime = {stats_by_entity, buff_by_entity}`
- `SELF/SOURCE/TARGET` 语义 + LIFE 的 actor/source

4) **确定性与 roll_key**
- 命中/暴击 xorshift32 种子组合
- 多段/多目标/bonus 的 roll_key 约定（引用 integrator_guide 第 9 章）

5) **Phase 2 Stats 面板口径**
- `get_breakdown(base/bonus/final)` + derived/curve 的解释

6) **调试与回归工作流**
- buff_ui_demo + Debug HUD + ErrorList + GUT tests

---

## 验收标准

- [ ] tutorial 文件夹存在且含 8 个 Markdown，章节可独立阅读
- [ ] 每章至少 1 个 Mermaid 图（flowchart/sequence/state 任一）
- [ ] Quickstart 章节中的代码能直接在项目里复制运行（假设启用插件）
- [ ] 文档中引用的路径/API 与当前仓库一致（deal_damage_v1、get_breakdown、LifeContext、ErrorList 等）
- [ ] README 提供 tutorial 的入口链接

