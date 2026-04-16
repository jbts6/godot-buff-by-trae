# OmniBuff Debug HUD Listeners Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `addons/omnibuff/demo/debug_hud.*` 新增 Listeners 面板，展示当前实体的事件监听列表（按 event_type/event_phase 分组）以及 `last_triggered_inst_ids`，用于快速定位“为什么触发/为什么没触发”。

**Architecture:** HUD 从 demo runtime 注入的 `buff_by_entity[eid]` 拿到 `OmniBuffCore`，再读 `buffs.event_index.listeners + listener_data` 与 `get_triggered_inst_ids_last_emit()`；以纯文本分组输出到 RichTextLabel（可复制）。

**Tech Stack:** Godot 4.7 + GDScript + OmniBuff（OmniEventIndex/OmniBuffCore）。

---

## 0) 文件清单

- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.tscn`
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`

（可选）若发现缺少 int->string 的 enum 反查接口：
- Modify: `godot-buff/addons/omnibuff/runtime/core/enums_runtime.gd`（仅增加只读 helper）

---

## Task 1：写一个 failing 测试/复现路径（最小）

> 本仓库的 HUD 是 demo UI，缺少 headless godot 运行环境时无法在 CI 中自动跑 UI 测试。
> 因此这里用“手工复现步骤 + 最小自检函数”替代严格自动化。

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`

- [ ] **Step 1: 添加一个临时自检方法（仅调试期）**

在 debug_hud.gd 增加：
```gdscript
func _self_check_listeners_format() -> void:
    # 当 runtime 为空时，_format_listeners() 应返回非崩溃的字符串（例如 "[Listeners] none"）
```

- [ ] **Step 2: 手工验证 RED**

打开 `buff_ui_demo.tscn`，运行一个包含 AFTER_DEAL 的 scenario（例如 multihit/dot），打开 HUD：
- 预期：Listeners tab 为空或报错（当前未实现）

---

## Task 2：在 Scene 中新增 Listeners Tab

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.tscn`

- [ ] **Step 1: 增加 Tab**

在 `TabContainer` 下新增：
- `Listeners`（ScrollContainer）
- `ListenersBox`（RichTextLabel，`selection_enabled=true`，`fit_content=true`）

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/demo/debug_hud.tscn
git -C godot-buff commit -m "ui(debug): add listeners tab to debug hud"
```

---

## Task 3：实现 Listeners 输出（分组 + last_triggered）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`

- [ ] **Step 1: 接入 onready 引用 + refresh**

```gdscript
@onready var listeners_box: RichTextLabel = %ListenersBox
```

并在 `clear()` / `_refresh_views()` 中同步清空与刷新：
```gdscript
listeners_box.text = _format_listeners()
```

- [ ] **Step 2: 实现 _format_listeners()**

推荐实现骨架（必须可在缺少 ds/enums_rt 时降级）：
```gdscript
func _format_listeners() -> String:
    if _runtime.is_empty() or _selected_eid < 0: return ""
    var buffs = _runtime.get("buff_by_entity", {}).get(_selected_eid, null)
    if buffs == null: return "[Listeners] none"

    var last := buffs.get_triggered_inst_ids_last_emit()
    var out := []
    out.append("[LastTriggered] inst_ids=" + str(last))

    var ei = buffs.event_index
    if ei == null: return "\\n".join(out) + "\\n\\n[Listeners] none"

    # 遍历 key: 0..ei.listeners.size()-1
    for key in range(ei.listeners.size()):
        var lids: PackedInt32Array = ei.listeners[key]
        if lids.is_empty(): continue
        out.append("")
        out.append("== key=" + str(key) + " ==")
        for lid in lids:
            var l = ei.listener_data[int(lid)]
            out.append(_format_one_listener(buffs, l))
    return "\\n".join(out)
```

- [ ] **Step 3: 实现 _format_one_listener(buffs, l)**

需要反查 buff_id：
```gdscript
var inst = buffs.instances_by_id.get(l.inst_id, null)
var buff_id_str = "?"
if inst != null and ds != null: buff_id_str = ds.buff_defs[inst.buff_def_id].id
```

Filters/action 的摘要拼接：
- filter_tag_mask（能反查 tags 就反查，否则打印 mask int/hex）
- require_hit / stat_threshold（scope/stat/op/value）
- action_kind + payload（buff_id/add_stacks 或 stat/value 或 dot_xxx）

- [ ] **Step 4: 手工验证 GREEN**

打开 `buff_ui_demo.tscn`，运行一个会挂 DOT 的 scenario（例如 multi-hit），打开 HUD：
- Listeners tab 能看到 AFTER_DEAL 的 listener
- last_triggered 在每次触发后会变化（至少非崩溃、可读）

- [ ] **Step 5: 提交**

```bash
git -C godot-buff add addons/omnibuff/demo/debug_hud.gd
git -C godot-buff commit -m "feat(debug): show listeners and last-triggered in hud"
```

---

## Task 4（可选）：更可读的 event key 名称

如果 `enums_rt` 提供 int->string 反查接口，则把 `key` 解码成：
`event_type=<NAME> phase=<NAME>`，替代纯 key 数字。

若缺接口，新增只读 helper（不影响运行时）：
- `OmniEnumsRuntime.enum_name(enum_id: String, v: int) -> String`

提交：
```bash
git -C godot-buff add addons/omnibuff/runtime/core/enums_runtime.gd addons/omnibuff/demo/debug_hud.gd
git -C godot-buff commit -m "feat(debug): pretty-print event type/phase names"
```

