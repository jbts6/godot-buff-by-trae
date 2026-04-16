# OmniBuff Demo Debug HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增一个 Demo-only 的 Debug HUD（`debug_hud.tscn/.gd`）并集成到 `buff_ui_demo`，用于可视化查看 Stats/Buffs/DOT，并支持“复制当前实体 dump”到剪贴板。

**Architecture:** HUD 只依赖 demo 传入的 `runtime` 字典（stats_by_entity/buff_by_entity）；UI 以 Tab 分区显示；dump 由 HUD 自行生成纯文本。先交付 MVP（Stats+Buffs+Copy），再补 DOT 与 listeners/replay。

**Tech Stack:** Godot 4.7 + GDScript + OmniBuff 运行时对象。

---

## 0) 文件清单

**HUD：**
- Create: `godot-buff/addons/omnibuff/demo/debug_hud.tscn`
- Create: `godot-buff/addons/omnibuff/demo/debug_hud.gd`
- Create: `godot-buff/addons/omnibuff/demo/debug_hud.gd.uid`

**集成：**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.tscn`（新增按钮 Debug HUD）
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`（创建 HUD 实例、传 runtime、默认选中）

**文档：**
- Modify: `godot-buff/addons/omnibuff/README.md`（可选：补充 Debug HUD 使用方式）

---

## Task 1：HUD Scene 骨架（Stats + Buffs + Copy Dump）

**Files:**
- Create: `godot-buff/addons/omnibuff/demo/debug_hud.tscn`
- Create: `godot-buff/addons/omnibuff/demo/debug_hud.gd`

- [ ] **Step 1: 创建 debug_hud.tscn**

布局建议：
- Root: `Window`（或 `PanelContainer`，若你不想用窗口）
- TopBar: `HBoxContainer`
  - `EntitySelect` (OptionButton)
  - `BtnCopyDump` (Button)
  - `BtnClose` (Button)
- Tabs: `TabContainer`
  - `StatsTab`（ScrollContainer + VBox，用 Label 列表）
  - `BuffsTab`（RichTextLabel 或 ItemList）

> MVP 先用 `RichTextLabel` 输出多行文本，省去表格控件。

- [ ] **Step 2: 实现 debug_hud.gd（runtime 接口）**

必须提供这些 API：
```gdscript
func set_runtime(runtime: Dictionary) -> void
func set_selected_entity(entity_id: int) -> void
func set_preferred_entities(attacker_id: int, defender_id: int) -> void
func clear() -> void
```

内部字段：
```gdscript
var _runtime: Dictionary = {}
var _selected_eid: int = -1
var _preferred_attacker: int = -1
var _preferred_defender: int = -1
```

EntitySelect 更新逻辑：
- 从 `_runtime.stats_by_entity.keys()` 取 keys，排序
- 默认选择：preferred_attacker > 最小 id

- [ ] **Step 3: 复制 dump（必须非空）**

实现：
```gdscript
func _make_dump() -> String:
    # 输出 stats + buffs（至少）
func _copy_dump() -> void:
    DisplayServer.clipboard_set(_make_dump())
```

- [ ] **Step 4: 提交**

```bash
git -C godot-buff add addons/omnibuff/demo/debug_hud.tscn addons/omnibuff/demo/debug_hud.gd addons/omnibuff/demo/debug_hud.gd.uid
git -C godot-buff commit -m "feat(demo): add omnibuff debug hud (mvp)"
```

---

## Task 2：集成到 buff_ui_demo（按钮开关 + runtime 注入）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.tscn`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`

- [ ] **Step 1: 在顶栏 Buttons 增加按钮**
新增 `BtnToggleHud`，文本“Debug HUD”。

- [ ] **Step 2: buff_ui_demo.gd 里实例化 HUD**

在脚本中：
```gdscript
const DebugHudScene = preload("res://addons/omnibuff/demo/debug_hud.tscn")
var _hud: Window = null
```

点击按钮：
- 若 `_hud==null`：instantiate + add_child + show
- 否则 toggle visible

- [ ] **Step 3: 在每次 run_scenario 后把 runtime 传给 HUD**

在 `_run_scenario` 中，在执行 scenario 前/后：
```gdscript
if _hud != null:
    _hud.set_runtime(current_runtime)
    _hud.set_preferred_entities(attacker_id, defender_id) # 若当前 scenario 有
```

> 初版可以只传当前 scenario 构造的 runtime；如果 scenario 内部构造多个 runtime，则在场景末尾选最核心的那一个。

- [ ] **Step 4: 提交**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.tscn addons/omnibuff/demo/buff_ui_demo.gd
git -C godot-buff commit -m "feat(demo): integrate debug hud into buff ui demo"
```

---

## Task 3：补 DOT Tab（Week2 内容）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.tscn`
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`

- [ ] **Step 1: 增加 DOT Tab**
用 RichTextLabel 输出：
- dot_buff_id（字符串）
- source_entity_id
- stacks / remaining_turns
- tick_phase

- [ ] **Step 2: dump 也追加 dots**

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add addons/omnibuff/demo/debug_hud.tscn addons/omnibuff/demo/debug_hud.gd
git -C godot-buff commit -m "feat(demo): show dots in debug hud"
```

---

## Task 4：补 listeners / 最近触发（Week3 内容，最小可用）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.tscn`
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`

- [ ] **Step 1: 先做“最近触发 inst_id 列表”**
从 `buffs.get_triggered_inst_ids_last_emit()` 读取并显示。

- [ ] **Step 2: listeners 展示（若 EventIndex 无公开接口，则先用 BuffCore.debug_dump_* 替代）**
优先做到“可用”，不强求结构化表格。

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add addons/omnibuff/demo/debug_hud.tscn addons/omnibuff/demo/debug_hud.gd
git -C godot-buff commit -m "feat(demo): show listeners and last triggered inst ids"
```

---

## Task 5：README 补充入口（可选）

**Files:**
- Modify: `godot-buff/addons/omnibuff/README.md`

- [ ] **Step 1: 写 Debug HUD 的使用方式（Demo-only）**

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/README.md
git -C godot-buff commit -m "docs: document debug hud usage"
```

