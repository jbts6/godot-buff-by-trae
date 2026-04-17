# OmniBuff Debug & QA Guide（调试与回归）

> 目标：把“为什么生效/为什么不生效”从读代码变成可复现、可观测、可回归。

## 目录

- [1. UI Demo（Scenario Runner）](#1-ui-demoscenario-runner)
- [2. Debug HUD（面板解释）](#2-debug-hud面板解释)
- [3. 如何新增一个 scenario（对齐 tests）](#3-如何新增一个-scenario对齐-tests)
- [4. GUT 回归测试](#4-gut-回归测试)

---

## 1. UI Demo（Scenario Runner）

场景：
- `res://addons/omnibuff/demo/buff_ui_demo.tscn`

用途：
- 左侧选择 scenario，右侧查看日志输出
- 每个 scenario 尽量与 `addons/omnibuff/tests/rpg/` 的语义对齐（用于复现与回归）

### 1.1 基本操作

1) DatasetSelect：选择数据集（`base_demo` / `rpg_tests`）  
2) `加载`：加载并编译数据集（strict=true）  
3) `运行选中`：只跑当前选中的 scenario  
4) `运行全部`：跑当前数据集下的全部 scenario  
5) `复制日志`：复制 LogBox 的纯文本缓冲（适合贴 issue）  
6) `清空日志`：清空 LogBox 与错误列表  

### 1.2 错误高亮与 ErrorList

为提升定位效率：
- LogBox 中命中错误关键字的行会标红
- 上方 `ErrorList` 会汇总错误行
- 点击 ErrorList 的某条会滚动到 LogBox 对应位置
- “运行全部/运行选中”结束如果存在错误，会自动定位第一条错误

错误关键字可在脚本中配置：
- `res://addons/omnibuff/demo/buff_ui_demo.gd` 的 `ERROR_MATCHERS`

---

## 2. Debug HUD（面板解释）

按钮：`Debug HUD`  
实现：`res://addons/omnibuff/demo/debug_hud.tscn` / `debug_hud.gd`

HUD 接收 demo 传入的 runtime（只做展示，不参与逻辑）：

```gdscript
runtime = { "stats_by_entity": {eid: StatsComponent}, "buff_by_entity": {eid: BuffCore} }
```

### 2.1 Stats

展示常用 stat 的 `get_final(stat_id)`：
- ATK/DEF/HP/SHIELD/HIT_RATE/EVADE/CRIT_RATE/CRIT_DMG/DMG_REDUCE

> 若你需要 UI 面板展示 base/bonus/final，请用 `StatsComponent.get_breakdown(stat_id)`（Phase 2）。

### 2.2 StatMods

按 stat 分组展示 modifiers 的贡献项，用于回答：
- “这个 ATK+10 是谁加的？”
- “为什么被 OVERRIDE 了？”
- “percent layer 乘法顺序是什么？”

### 2.3 Buffs

列出当前实体的 BuffInst：
- `buff_id`（从 ds 反查）
- `type/tags/source/stacks/remaining_turns/active`

注意：
- 对于 DOT，`BuffInst.remaining_turns` **不权威**（会显示 `N/A(DOT)`）
- DOT 的权威 turns/stacks 在 `Dots` 面板（DotInstance）

### 2.4 Dots

列出 `DotInstance`（DOT 的权威数据结构）：
- `dot_inst_id`
/- `source_entity_id / target_entity_id`
- `stacks / remaining_turns / tick_phase`
- `owner_buff_inst_id`（对应哪个 buff 实例）

### 2.5 Listeners

按 event_type/event_phase 分组展示 EventIndex listeners：
- filters 摘要
- action 摘要
- 最近一次触发命中的 inst_id（用于定位“为什么没触发”）

---

## 3. 如何新增一个 scenario（对齐 tests）

文件：
- `res://addons/omnibuff/demo/buff_ui_demo.gd`

### 3.1 注册入口

在 `_register_scenarios()` 中新增条目：

```gdscript
{
  "id": "my_new_case",
  "title": "My Case / description",
  "dataset": "rpg_tests",
  "covers": ["test_xxx.gd (optional note)"],
  "fn": Callable(self, "_sc_my_new_case")
}
```

### 3.2 编写场景函数

新增 `_sc_my_new_case()`：
- 用 `_mk_actor(eid)` 构造实体（stats+buffs）
- 用 `_mk_runtime([actors...])` 构造 runtime
- 调用 `pipe.deal_damage(...)` 或 `turn.on_turn_start/end(...)` 或 `buffs.emit_event(...)`
- 用 `_log(...)` 输出关键观测点

### 3.3 建议同步补 tests

如果这是“新能力”或“曾经出过 bug 的行为”，建议同步补一个 `addons/omnibuff/tests/rpg/test_xxx.gd`：
- 测试保证逻辑正确性
- scenario 负责可视化复现与 QA 工作流

---

## 4. GUT 回归测试

### 4.1 启用 GUT

仓库已 vendor：
- `res://addons/gut/`

启用：
- `Project → Project Settings → Plugins → GUT`

### 4.2 目录

建议在 GUT 面板添加：
- `res://addons/omnibuff/tests/base`
- `res://addons/omnibuff/tests/rpg`

### 4.3 Headless（脚本）

仓库根目录 `godot-buff/`：

```bash
GODOT_BIN="/path/to/godot" ./run_gut_tests.sh
```

