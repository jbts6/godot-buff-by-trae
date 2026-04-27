# 07 — 调试与扩展：把插件变成“人人能维护”

本章目标：
- 让你会用 UI demo / Debug HUD / ErrorList 快速定位问题
- 让你知道“新增一个能力点”应该改哪些文件（扩展 checklist）
- 让你能把新增能力变成可回归（tests + scenario）

---

## 1. 推荐调试入口：buff_ui_demo（Scenario Runner）

场景：
- `res://addons/omnibuff/demo/buff_ui_demo.tscn`

为什么推荐它？
- 左侧 scenario，右侧日志输出：非常适合复现与沟通
- 有 ErrorList：错误高亮 + 汇总列表跳转（RunAll 结束自动定位第一条错误）
- 能切换 dataset（base_demo / rpg_tests）
- 一键打开 Debug HUD

当你遇到“buff 没生效”的问题，优先做：
1) 找一个最接近的 scenario 先复现  
2) 看 ErrorList 有没有配置/校验错误  
3) 打开 HUD 看 Stats/StatMods/Listeners/Dots  

---

## 2. Debug HUD：应该看什么

HUD：
- `res://addons/omnibuff/demo/debug_hud.tscn`

你最常用的三个面板：

1) **StatMods**
- 回答：某个 stat 的加成到底来自哪些 buff？
- 重点看：op/phase/value/layer/priority/source_inst_id

2) **Listeners**
- 回答：某个事件有没有 listener？为什么没触发？
- 重点看：filters 摘要、last_triggered_inst_ids

3) **Dots**
- 回答：DOT 为什么还在跳/为什么不跳？
- 重点看：DotInstance 的 turns/stacks 才是权威

---

## 3. 扩展策略：每个能力点都要“三件套”

OmniBuff 推荐的工程化习惯是：

```mermaid
flowchart LR
  A[新增能力点] --> B[写最小 GUT 测试]
  B --> C["让测试先红<br/>RED"]
  C --> D[实现 runtime/compiler/validators]
  D --> E["测试变绿<br/>GREEN"]
  E --> F[加一个 UI demo scenario 方便 QA/复现]
```

这样做的收益：
- 逻辑正确性由 tests 保证
- 可视化复现由 scenario 保证
- 远程沟通只需要发“scenario id + 日志 + dump”

---

## 4. 扩展 checklist（新增 action/filter/stat/buff 时要改什么）

### 4.1 新增一个 action_kind

你通常至少要改：

1) `data/*/enums.json`
- 在 `action_kind` 里新增枚举值（否则 validators 会报错）

2) `addons/omnibuff/config/compiler/validators.gd`
- 允许该 action 的字段，并做必要校验（缺字段时报错）

3) `addons/omnibuff/runtime/core/event_index.gd`
- Listener 结构里需要为该 action/filters 增加字段（若需要预编译）

4) `addons/omnibuff/runtime/core/buff_core.gd`
- 在执行 action 的分发处实现具体效果（例如改 stacks / apply buff / 改 stat）

5) tests + scenario
- `addons/omnibuff/tests/rpg/test_xxx.gd`
- `addons/omnibuff/demo/buff_ui_demo.gd` 增加 scenario

### 4.2 新增一个 filter

典型要改：
- enums.json（若是枚举类 filter）
- validators.gd（允许字段 + 校验）
- event_index.gd（Listener 增字段，编译期把 filter 解析成更快的数据结构）
- buff_core.gd（emit_event 时判断该 filter）
- tests + scenario

### 4.3 新增/修改 stat_defs 的字段（例如 Phase2 的 derived/curve）

典型要改：
- validators.gd（schema 治理）
- dataset_compiler.gd（compile 到 ds）
- compiled_data.gd（ds 持久字段）
- stats_core.gd（运行时计算）
- tests（强烈建议）

---

## 5. 回归测试（GUT）：把“可维护”落到工具链

测试目录：
- `res://addons/omnibuff/tests/base`
- `res://addons/omnibuff/tests/rpg`

建议：
- 新增能力点优先在 `tests/rpg` 写
- 修 bug 必须补回归用例（否则很容易再复发）

Headless 运行脚本（仓库根目录 `godot-buff/`）：

```bash
GODOT_BIN="/path/to/godot" ./run_gut_tests.sh
```

---

## 本章小结

你现在应该能：
- 用 UI demo + ErrorList + HUD 快速定位问题
- 按 checklist 扩展 action/filter/stat
- 把每个能力点做成“tests + scenario”的可回归资产

到此为止，你已经拥有读懂 OmniBuff 代码的完整心智模型。  
如果你要进一步深入，请直接对照源码路径阅读：
- `runtime/core/*`、`config/compiler/*`、`demo/*`、`tests/*`
