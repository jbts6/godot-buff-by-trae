# OmniBuff UI Demo Error Highlighting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `buff_ui_demo` 中实现“错误行标红 + 错误汇总列表 + RunAll 自动定位第一条错误”。

**Architecture:** `RichTextLabel` 使用 BBCode 输出并按 matcher 标红；新增 `ErrorList(ItemList)` 记录错误行与 LogBox 行号映射；RunAll 结束自动选中并跳转。

**Tech Stack:** Godot 4.x，GDScript，RichTextLabel BBCode，ItemList metadata。

---

## 0) 文件清单

- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.tscn`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

---

## Task 1：更新 UI（新增 ErrorList 区域）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.tscn`

- [ ] **Step 1: 将右侧 LogBox 外层包一层 VBox，并新增 ErrorList**

在 `Margin/VBox/Main` 下，把原来的：

```ini
[node name="LogBox" type="RichTextLabel" parent="Margin/VBox/Main" ...]
```

替换为：

```ini
[node name="Right" type="VBoxContainer" parent="Margin/VBox/Main"]
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 3

[node name="ErrorList" type="ItemList" parent="Margin/VBox/Main/Right"]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 120)
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 0

[node name="LogBox" type="RichTextLabel" parent="Margin/VBox/Main/Right" unique_id=803866688]
unique_name_in_owner = true
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 3
focus_mode = 2
selection_enabled = true
bbcode_enabled = true
```

> 备注：保留 LogBox 的 `unique_name_in_owner=true` 与 `unique_id`，确保 `%LogBox` 不变。

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.tscn
git -C godot-buff commit -m "feat(demo): add ErrorList panel to buff_ui_demo"
```

---

## Task 2：实现错误判定 + BBCode 标红 + ErrorList 收集

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: 新增节点引用与错误缓存**

```gdscript
@onready var error_list: ItemList = %ErrorList

var _error_count: int = 0

const ERROR_MATCHERS := [
	{"mode": "contains", "text": "Error"},
	{"mode": "contains", "text": "Invalid"},
	{"mode": "prefix", "text": "E 0:"},
	{"mode": "prefix", "text": "E "},
]
```

- [ ] **Step 2: 实现 helper**

```gdscript
func _is_error_line(msg: String) -> bool:
	for m in ERROR_MATCHERS:
		var mode := String((m as Dictionary).get("mode", ""))
		var text := String((m as Dictionary).get("text", ""))
		if text == "":
			continue
		if mode == "contains":
			if msg.findn(text) >= 0:
				return true
		elif mode == "prefix":
			if msg.begins_with(text):
				return true
	return false

func _bb_escape(s: String) -> String:
	# RichTextLabel bbcode 最小转义
	return s.replace("[", "\\[")

func _push_error(msg: String, line_index: int) -> void:
	if msg.length() > 200:
		msg = msg.substr(0, 200) + "..."
	var idx := error_list.add_item(msg)
	error_list.set_item_metadata(idx, line_index)
	_error_count += 1
```

- [ ] **Step 3: 改造 _log(msg)**

```gdscript
func _log(msg: String) -> void:
	var line_index := log_box.get_line_count()
	_log_buffer += msg + "\n"

	var safe := _bb_escape(msg)
	if _is_error_line(msg):
		log_box.append_bbcode("[color=#ff4d4d]" + safe + "[/color]\n")
		_push_error(msg, line_index)
	else:
		log_box.append_bbcode(safe + "\n")

	log_box.scroll_to_line(log_box.get_line_count())
```

- [ ] **Step 4: ErrorList 点击跳转**

在 `_ready()` 中绑定：

```gdscript
error_list.item_selected.connect(func(idx: int):
	var line_index := int(error_list.get_item_metadata(idx))
	log_box.scroll_to_line(line_index)
)
```

同时：
- `_reset_state()` 不清理 ErrorList（因为它会在每个 scenario 调用）；错误汇总应由 RunAll/RunSelected 控制清理
- 增加 `_clear_errors()`，在 `_run_all()` / `_run_selected()` 开头调用：

```gdscript
func _clear_errors() -> void:
	_error_count = 0
	error_list.clear()
	error_list.visible = false
```

- [ ] **Step 5: RunAll 结束自动定位**

```gdscript
func _run_all() -> void:
	_clear_errors()
	for s in _visible_scenarios:
		_run_scenario(s)
	if error_list.item_count > 0:
		error_list.visible = true
		error_list.select(0)
		var line_index := int(error_list.get_item_metadata(0))
		log_box.scroll_to_line(line_index)
		lbl_status.text = "发现 %s 条错误，已定位第一条" % [error_list.item_count]
```

`_run_selected()` 同理：先 `_clear_errors()`，跑完若有错误同样自动定位。

- [ ] **Step 6: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m "feat(demo): highlight errors and add jump list"
```

---

## 最终手动验证（在编辑器里）

- [ ] 打开 `res://addons/omnibuff/demo/buff_ui_demo.tscn`
- [ ] 点击“运行全部”，观察：
  - LogBox 中错误行变红
  - ErrorList 出现错误行
  - 自动滚动到第一条错误

