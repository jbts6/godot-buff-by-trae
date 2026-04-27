# OmniBuff Tutorial（总览）

> 面向：未做过 Buff 系统的 Godot 开发者  
> 目标：理解 OmniBuff 的设计原理/设计思想，并能在自己的战斗系统里正确接入、扩展与调试。

## 你将学到什么

- 为什么 OmniBuff 强调“数据驱动 + 可回归 + 性能约束”
- Stats/Buff/Damage/DOT/Event 的职责边界
- 从零跑通：加载数据集 → 上 Buff → 结算一次伤害
- 如何写配置（buff_defs/stat_defs/enums）以及它们如何被 validate/compile
- 如何用 demo / HUD / tests 定位问题与做回归

## 推荐阅读顺序

1) **先理解整体**：`01_why_and_principles.md`  
2) **先跑起来**：`02_quickstart_run_a_hit.md`  
3) **理解数据链路**：`03_data_pipeline.md`  
4) **理解运行时核心**：
   - `04_stats_system.md`
   - `05_buff_and_events.md`
   - `06_damage_dot_turn_replay.md`
5) **学会调试与扩展**：`07_debug_and_extend.md`

如果你只想快速能用：
- 直接看 `02_quickstart_run_a_hit.md`，然后打开 UI demo：`res://addons/omnibuff/demo/buff_ui_demo.tscn`

## “先跑起来”的 3 个入口

1) **UI demo（推荐）**：`res://addons/omnibuff/demo/buff_ui_demo.tscn`  
   - 有 scenario runner（run selected/run all）
   - 有 ErrorList（错误高亮与快速跳转）
   - 有 Debug HUD

2) **控制台 demo**：`res://addons/omnibuff/demo/demo_scene.tscn`  
   - 输出到 Godot Output 面板

3) **自动化测试（GUT）**：`res://addons/omnibuff/tests/`  
   - `tests/base`：基础能力
   - `tests/rpg`：更复杂的集成语义（建议你后续扩展优先加在这里）

## 这套 tutorial 与其它文档的关系

- **API 契约（contract）**：`res://addons/omnibuff/docs/api.md`  
  更像“规范/边界/字段定义”，适合查阅。
- **战斗系统接入指南（更偏实战）**：`res://addons/omnibuff/docs/integrator_guide.md`  
  里面还有“技能系统接入建议（roll_key 等）”。
- **数据协议速查 + recipes**：`res://addons/omnibuff/docs/schema_reference.md`
- **调试与回归**：`res://addons/omnibuff/docs/debug_and_qa.md`

---

## 约定：你应该先理解的 5 个关键词

1) **Dataset（数据集）**：manifest/enums/defs 的集合，先 validate 再 compile  
2) **CompiledDataset**：编译产物，运行时只读它，不直接读 raw JSON 字段  
3) **StatCache**：属性缓存（热路径只允许 `get_final`/`get_breakdown`）  
4) **EventIndex**：事件索引（只遍历监听子集，禁止全量遍历）  
5) **roll_key**：确定性 RNG 的唯一键（多段/多目标/追加时非常重要）

