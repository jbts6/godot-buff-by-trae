# OmniBuff Debug HUD Stat Modifiers Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Debug HUD 中新增 `StatMods` Tab，按 stat 分组展示 `modifiers_by_stat` 的贡献项，并能反查到 `source_inst_id -> buff_id`，用于解释“为什么该属性是这个数”。

**Architecture:** HUD 从 runtime 注入拿到 `stats_by_entity[eid]` 与 `buff_by_entity[eid]`、`ds`；遍历常用 stat_id，读取 `stats.core` 中的 base/final/dirty 与 `modifiers_by_stat[stat_id]`；每条 modifier 通过 `source_inst_id` 反查 buff_def_id 与 buff_id，最终输出纯文本到 RichTextLabel，并纳入 Copy dump。

**Tech Stack:** Godot 4.7 + GDScript + OmniStatsCore/OmniModifierRef + OmniBuffCore。

---

## 0) 文件清单

- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.tscn`
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`

---

## Task 1：Scene 增加 StatMods Tab

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.tscn`

- [ ] **Step 1: 增加 Tab**

在 `TabContainer` 下新增：
- `StatMods`（ScrollContainer）
- `StatModsBox`（RichTextLabel，`selection_enabled=true`，`fit_content=true`）

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/debug_hud.tscn
git -C godot-buff commit -m "ui(debug): add stat modifiers tab"
```

---

## Task 2：HUD 实现 _format_stat_mods()

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`

- [ ] **Step 1: onready 引用 + 刷新**

```gdscript
@onready var stat_mods_box: RichTextLabel = %StatModsBox
```

在 `clear()` / `_refresh_views()` 更新：
```gdscript
stat_mods_box.text = _format_stat_mods()
```

- [ ] **Step 2: 实现 _format_stat_mods()**

实现要点：
- 若 runtime/ds/stats/core 缺失则降级输出，不崩溃
- 遍历一个固定 `stat_names` 列表（与 Stats tab 同步）
- 对每个 stat：
  - `sid = ds.stat_id(name)`；sid<0 跳过
  - base = stats.core.base_values[sid]
  - final = stats.get_final(sid)（确保是最终值）
  - dirty = stats.core.dirty[sid]
  - mods = stats.core.modifiers_by_stat[sid]

将 mods 转成结构化行，并按 `source_inst_id` 升序排序：
```gdscript
mods.sort_custom(func(a,b): return int(a.source_inst_id) < int(b.source_inst_id))
```

每条输出字段：
- `op/phase/value/layer/priority/source_inst_id`
- buff_id：用 `_buff_id_from_inst_id(buffs, ds, source_inst_id)`

实现 helper：
```gdscript
func _buff_id_from_inst_id(buffs, ds, inst_id:int) -> String:
    var inst = buffs.instances_by_id.get(inst_id, null)
    if inst==null: return "?"
    var def = ds.buff_defs[int(inst.buff_def_id)]
    return String(def.get("id","?"))
```

- [ ] **Step 3: Copy dump 增加 stat_mods 分区**

在 `_make_dump()` 追加：
```gdscript
parts.append("")
parts.append(_format_stat_mods())
```

- [ ] **Step 4: 手工验证**

打开 `buff_ui_demo.tscn`，运行一个会改变 ATK 的 scenario（例如 stats_percent_layers）：
- StatMods tab 能看到 ATK 的 modifiers 列表
- 每条都能反查出 buff_id（不是全是 ?）

- [ ] **Step 5: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/debug_hud.gd
git -C godot-buff commit -m "feat(debug): show stat modifiers grouped by stat"
```

---

## Task 3（可选）：输出更可读（phase/op 分组）

若需要更强可读性：
- 把每个 stat 的 mods 先按 phase 分段输出（FLAT/PERCENT/FINAL/OVERRIDE）
- 并标注 percent layer 的合并（同 layer 的多个 pct 可显示 sum）

该任务仅在你们觉得当前文本过于冗长时再做。

