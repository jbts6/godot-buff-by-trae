# OmniBuff UI Demo：错误高亮 + 错误汇总列表（设计）

## 背景

`res://addons/omnibuff/demo/buff_ui_demo.tscn` 作为 scenario runner，经常用于点击“运行全部”快速回归。当前 LogBox 仅追加纯文本，遇到错误（例如 `[ERROR] ...` 或 Godot 输出的 `E 0:...`）时，定位成本高。

## 目标

1) **LogBox 内高亮**：命中“错误规则”的行自动标红（便于扫一眼发现）
2) **错误汇总列表**：在 LogBox 上方/旁边提供 ErrorList，仅收集错误行；点击可跳转到 LogBox 对应行
3) **RunAll 结束自动定位**：点击“运行全部”后，如果存在错误，自动选中第一条错误并滚动到该位置，同时 StatusLabel 提示错误条数
4) **可配置匹配规则**：错误识别基于可配置列表（未来可扩展 warning/info 颜色）

## 非目标

- 不做复杂的“日志等级解析器”（例如结构化 JSON 日志）
- 不改 scenario 的执行逻辑/回放逻辑，仅增强日志可观测性

---

## UI 设计

在右侧日志区域（原 LogBox 单控件）上方新增一个 **ErrorList 区域**：
- `ErrorList`：`ItemList`
  - 默认隐藏；当错误条数 > 0 时显示
  - 每条 item 文本为该错误行的原始 msg（可截断）
  - `metadata` 存储该错误在 LogBox 内对应的 `line_index`（用于点击跳转）

LogBox 保持原有唯一名 `%LogBox`，避免破坏现有引用。

---

## 日志高亮策略

### 1) 错误判定（可配置）

在 `buff_ui_demo.gd` 顶部维护配置：

- `ERROR_MATCHERS: Array[Dictionary]`
  - `{"mode":"contains","text":"Error"}`
  - `{"mode":"contains","text":"Invalid"}`
  - `{"mode":"prefix","text":"E "}`
  - `{"mode":"prefix","text":"E 0:"}`

判定函数 `_is_error_line(msg: String) -> bool`：
- `contains`: `msg.findn(text) >= 0`
- `prefix`: `msg.begins_with(text)` 或 `msg.strip_edges(true,false).begins_with(text)`（可选）

### 2) RichTextLabel 输出

- 开启 `log_box.bbcode_enabled = true`
- 所有日志通过 `append_bbcode()` 输出
- 错误行包裹颜色：
  - `[color=#ff4d4d]...[/color]`
- 为防止日志中出现 `[` `]` 影响 bbcode，需要在写入前做最小转义：
  - `[` → `\[`

---

## RunAll 快速定位

`_run_all()`：
- 开始前清空 ErrorList
- 执行完成后：
  - 如果 ErrorList 非空：自动选中第 0 项，调用跳转函数滚动 LogBox，并更新 StatusLabel（例如：`发现 3 条错误，已定位第一条`）

---

## 验收标准

- [ ] 任意包含 `Error`/`Invalid`/以 `E ` 开头的行在 LogBox 中显示为红色
- [ ] ErrorList 会收集错误行；点击能跳转到对应的 LogBox 行
- [ ] “运行全部”结束若存在错误，自动定位第一条错误并提示数量
- [ ] 不影响现有复制日志、清空日志等功能

