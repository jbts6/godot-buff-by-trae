# OmniBuff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Goal:** 在 Godot 4.x 中落地“万物皆Buff”的 Buff/Stat/DamagePipeline 插件（addons 形式）+ 可运行 demo + CSV/JSON 数据加载（manifest/enums 权威源）+ 性能硬规则（StatCache + EventIndex）。
>
> **Architecture:** 数据侧：manifest→enums→raw defs→validate→compile（int索引/bitmask/紧凑数组）→CompiledDataset（只读）。运行时：StatsCore（StatCache+Dirty）+ BuffCore（实例/叠加/持续/驱散/事件索引）+ DamagePipeline（固定阶段骨架）+ Replay/Trace（命令流/追帧）。
>
> **Tech Stack:** Godot 4.x / GDScript / JSON+CSV 解析（FileAccess + JSON + 自写CSV reader）/ 不生成派生缓存文件。

---

## 0) 现状与工作目录约定

- 代码根目录：`godot-buff/`（已有 `project.godot`）
- 本计划将创建：`addons/omnibuff/**`、`data/base_demo/**`
- 约定：所有脚本使用 `class_name` 注册（便于引用/调试）。

### 0.1) 执行期修订（与初版计划的差异说明）

为贴近真实项目与解决 Godot 4 开发期常见问题，执行过程中发生了以下“计划外但必要”的工程化调整：

1. **全局类可见性/缓存问题**  
   - 现象：`class_name OmniReplay` 在某些情况下不会立刻进入全局类表，导致解析期报 `Identifier not declared`。  
   - 处理：增加工程侧 `Autoload`：`OmniBuffBootstrap`（`res://addons/omnibuff/omnibuff_bootstrap.gd`）启动时 `preload()` 关键脚本，降低缓存不同步风险；同时 demo 里对关键类采用显式 `preload()`。
2. **Schema 校验增强（M9扩展）**  
   - 已实现“深度未知字段治理（JSONPath 逐层）”与“触发链循环/过深检测”。  
   - 新增 `enums.action_kind` 作为触发器 `action.kind` 白名单（严格模式阻断）。
3. **事件动作扩展**  
   - 在 `EventIndex` 与 `BuffCore.emit_event()` 中增加 `APPLY_BUFF/CHANCE_APPLY_BUFF` 的运行时行为（除 `ADD_BASE_DAMAGE` 外）。
   - 为避免强耦合，在 `DamageContext` 上通过 `meta.runtime` 传入运行时字典（`stats_by_entity/buff_by_entity`）供事件动作定位目标。

---

## 1) 文件结构（将创建/修改哪些文件）

### 1.1 将创建的主要文件

**插件与运行时：**
- Create: `godot-buff/addons/omnibuff/plugin.cfg`
- Create: `godot-buff/addons/omnibuff/omnibuff.gd`
- Create: `godot-buff/addons/omnibuff/runtime/core/enums_runtime.gd`
- Create: `godot-buff/addons/omnibuff/runtime/core/compiled_data.gd`
- Create: `godot-buff/addons/omnibuff/runtime/core/expr_vm.gd`
- Create: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`
- Create: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`
- Create: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- Create: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`
- Create: `godot-buff/addons/omnibuff/runtime/core/replay.gd`
- Create: `godot-buff/addons/omnibuff/runtime/components/*.gd`（Stats/Buff/Skill/Equipment/Turn）

**配置加载与编译：**
- Create: `godot-buff/addons/omnibuff/config/manifest_loader.gd`
- Create: `godot-buff/addons/omnibuff/config/parsers/csv_reader.gd`
- Create: `godot-buff/addons/omnibuff/config/parsers/json_reader.gd`
- Create: `godot-buff/addons/omnibuff/config/compiler/dataset_compiler.gd`
- Create: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Create: `godot-buff/addons/omnibuff/config/compiler/migrate.gd`

**demo 与测试：**
- Create: `godot-buff/addons/omnibuff/demo/demo_scene.tscn`
- Create: `godot-buff/addons/omnibuff/demo/demo_runner.gd`
- Create: `godot-buff/addons/omnibuff/demo/tests/test_runner.gd`
- Create: `godot-buff/addons/omnibuff/demo/tests/assert.gd`

**数据集（附件B最小闭环）：**
- Create: `godot-buff/data/base_demo/manifest.json`
- Create: `godot-buff/data/base_demo/enums.json`
- Create: `godot-buff/data/base_demo/stat_defs.json`
- Create: `godot-buff/data/base_demo/buff_defs.json`
- Create: `godot-buff/data/base_demo/equipment.csv`
- Create: `godot-buff/data/base_demo/set_bonus.json`
- Create: `godot-buff/data/base_demo/skill_defs.json`
- Create: `godot-buff/data/base_demo/damage_pipeline.json`

### 1.2 将修改的文件
- Modify: `godot-buff/project.godot`（设置主场景为 demo_scene，或添加 autoload（可选））

---

## 2) Task 1（M0）：插件骨架 + demo可运行空场景

**Files:**
- Create: `godot-buff/addons/omnibuff/plugin.cfg`
- Create: `godot-buff/addons/omnibuff/omnibuff.gd`
- Create: `godot-buff/addons/omnibuff/demo/demo_scene.tscn`
- Create: `godot-buff/addons/omnibuff/demo/demo_runner.gd`
- Modify: `godot-buff/project.godot`

- [ ] **Step 1: 创建 plugin.cfg**

```ini
[plugin]
name="OmniBuff"
description="All is Buff/Modifier: high-performance turn-based buff/stat system."
author="SOLO"
version="0.1.0"
script="res://addons/omnibuff/omnibuff.gd"
```

- [ ] **Step 2: 创建 omnibuff.gd（最小 EditorPlugin）**

```gdscript
@tool
extends EditorPlugin

func _enter_tree() -> void:
    print("[OmniBuff] plugin enabled")

func _exit_tree() -> void:
    print("[OmniBuff] plugin disabled")
```

- [ ] **Step 3: 创建 demo_scene.tscn + demo_runner.gd**

`demo_scene.tscn`：
```text
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://addons/omnibuff/demo/demo_runner.gd" id="1"]

[node name="Demo" type="Node"]
script = ExtResource("1")
```

`demo_runner.gd`：
```gdscript
extends Node

func _ready() -> void:
    print("[OmniBuffDemo] boot")
```

- [ ] **Step 4: 设定主场景（project.godot）**

把主场景设为：
`res://addons/omnibuff/demo/demo_scene.tscn`

- [ ] **Step 5: 运行验证**

在 Godot Editor 中运行项目（F5）。  
Expected：输出包含 `[OmniBuffDemo] boot`（控制台）。

- [ ] **Step 6: Commit**

```bash
git add godot-buff/addons/omnibuff godot-buff/project.godot
git commit -m "chore(omnibuff): add plugin skeleton and demo scene"
```

---

## 3) Task 2（M1）：manifest/enums 加载 + 覆盖冲突报告 + strict/lenient

**Files:**
- Create: `godot-buff/addons/omnibuff/config/manifest_loader.gd`
- Create: `godot-buff/addons/omnibuff/config/parsers/json_reader.gd`
- Create: `godot-buff/addons/omnibuff/config/parsers/csv_reader.gd`
- Create: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Create: `godot-buff/addons/omnibuff/config/compiler/migrate.gd`
- Create: `godot-buff/data/base_demo/*`（见 Task 3）
- Modify: `godot-buff/addons/omnibuff/demo/demo_runner.gd`（加载数据）

- [ ] **Step 1: JSON reader**

```gdscript
class_name OmniJson
extends RefCounted

static func load_dict(path: String) -> Dictionary:
    var txt := FileAccess.get_file_as_string(path)
    var obj := JSON.parse_string(txt)
    if obj == null or typeof(obj) != TYPE_DICTIONARY:
        push_error("[OmniJson] parse failed: " + path)
        return {}
    return obj
```

- [ ] **Step 2: CSV reader（支持行号，用于错误定位）**

```gdscript
class_name OmniCsv
extends RefCounted

class Row:
    var line_no: int
    var cols: PackedStringArray

static func load_rows(path: String) -> Array[Row]:
    var rows: Array[Row] = []
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        push_error("[OmniCsv] open failed: " + path)
        return rows
    var line_no := 0
    while not f.eof_reached():
        var line := f.get_line()
        line_no += 1
        if line_no == 1 and line.begins_with("\uFEFF"):
            line = line.substr(1)
        if line.strip_edges() == "" or line.strip_edges().begins_with("#"):
            continue
        var cols := line.split(",", false)
        var r := Row.new()
        r.line_no = line_no
        r.cols = cols
        rows.append(r)
    return rows
```

- [ ] **Step 3: validators（strict/lenient + 错误定位结构）**

```gdscript
class_name OmniValidate
extends RefCounted

enum Level { INFO, WARNING, ERROR }

class Issue:
    var level: int
    var file: String
    var loc: String # "line=12" or "path=$.buffs[0].effects[1]"
    var id: String
    var message: String

static func error(file: String, loc: String, id: String, msg: String) -> Issue:
    var i := Issue.new()
    i.level = Level.ERROR
    i.file = file
    i.loc = loc
    i.id = id
    i.message = msg
    return i
```

- [ ] **Step 4: manifest_loader（只加载manifest+enums，并检查顺序与required）**

```gdscript
class_name OmniManifestLoader
extends RefCounted

class Result:
    var manifest: Dictionary
    var enums: Dictionary
    var issues: Array[OmniValidate.Issue] = []

static func load_dataset(manifest_path: String, strict: bool) -> Result:
    var res := Result.new()
    res.manifest = OmniJson.load_dict(manifest_path)
    if res.manifest.is_empty():
        res.issues.append(OmniValidate.error(manifest_path, "root", "", "manifest empty/invalid"))
        return res

    if not res.manifest.has("files"):
        res.issues.append(OmniValidate.error(manifest_path, "$.files", "", "missing files[]"))
        return res

    var enums_path := ""
    for f in res.manifest["files"]:
        if f.get("type","") == "enums":
            enums_path = _resolve_relative(manifest_path, f.get("path",""))
            break

    if enums_path == "":
        res.issues.append(OmniValidate.error(manifest_path, "$.files", "", "enums.json required"))
        return res

    res.enums = OmniJson.load_dict(enums_path)
    if res.enums.is_empty():
        res.issues.append(OmniValidate.error(enums_path, "root", "", "enums parse failed"))
        return res

    # strict: 枚举/Tag缺失直接阻断；lenient: 记录warning
    if strict:
        if not res.enums.has("enums") or not res.enums.has("tags"):
            res.issues.append(OmniValidate.error(enums_path, "root", "", "missing enums/tags"))
    return res

static func _resolve_relative(base_file: String, rel: String) -> String:
    var base_dir := base_file.get_base_dir()
    return base_dir.path_join(rel)
```

- [ ] **Step 5: demo_runner 里加载 dataset 并打印问题**

```gdscript
extends Node

func _ready() -> void:
    print("[OmniBuffDemo] boot")
    var result := OmniManifestLoader.load_dataset("res://data/base_demo/manifest.json", true)
    for issue in result.issues:
        push_error("%s %s %s %s: %s" % [issue.level, issue.file, issue.loc, issue.id, issue.message])
    print("[OmniBuffDemo] manifest loaded, enums keys=", result.enums.keys())
```

- [ ] **Step 6: 运行验证**

运行 demo。  
Expected：控制台打印 `manifest loaded`；且无 Error。

- [ ] **Step 7: Commit**

```bash
git add godot-buff/addons/omnibuff/config godot-buff/addons/omnibuff/demo/demo_runner.gd
git commit -m "feat(config): add manifest/enums loader with strict validation"
```

---

## 4) Task 3（M1）：写入 base_demo 数据集（附件B落地）

**Files:**
- Create: `godot-buff/data/base_demo/manifest.json`
- Create: `godot-buff/data/base_demo/enums.json`
- Create: `godot-buff/data/base_demo/stat_defs.json`
- Create: `godot-buff/data/base_demo/buff_defs.json`
- Create: `godot-buff/data/base_demo/equipment.csv`
- Create: `godot-buff/data/base_demo/set_bonus.json`
- Create: `godot-buff/data/base_demo/skill_defs.json`
- Create: `godot-buff/data/base_demo/damage_pipeline.json`

- [ ] **Step 1: 写入文件内容**

把 `buff_system_architecture.md` 的附件B内容逐文件写入到 `res://data/base_demo/`。  
（实现时将直接复制粘贴该附件B内容；以 manifest 为入口，enums required=true，load_order 固定。）

- [ ] **Step 2: 运行验证**

运行 demo。  
Expected：`manifest loaded`，enums/stat/buff 等文件无解析错误。

- [ ] **Step 3: Commit**

```bash
git add godot-buff/data/base_demo
git commit -m "chore(data): add base_demo dataset (manifest/enums/defs)"
```

---

## 5) Task 4（M2）：编译期 int索引 + tag bitmask（enums_runtime + compiled_data）

**Files:**
- Create: `godot-buff/addons/omnibuff/runtime/core/enums_runtime.gd`
- Create: `godot-buff/addons/omnibuff/runtime/core/compiled_data.gd`
- Create: `godot-buff/addons/omnibuff/config/compiler/dataset_compiler.gd`
- Modify: `godot-buff/addons/omnibuff/demo/demo_runner.gd`

- [ ] **Step 1: enums_runtime（字符串枚举→int，tag→bit）**

```gdscript
class_name OmniEnumsRuntime
extends RefCounted

var enum_tables: Dictionary = {} # name -> {str:int}
var tag_code_by_id: Dictionary = {} # tag_id -> int (bit index)
var tag_mask_by_id: Dictionary = {} # tag_id -> int mask (1<<code)

static func from_enums_json(enums_obj: Dictionary) -> OmniEnumsRuntime:
    var rt := OmniEnumsRuntime.new()
    var enums := enums_obj.get("enums", {})
    for k in enums.keys():
        var arr: Array = enums[k]
        var map := {}
        for i in range(arr.size()):
            map[String(arr[i])] = i
        rt.enum_tables[k] = map

    var tags: Array = enums_obj.get("tags", [])
    for t in tags:
        var id := String(t.get("id",""))
        var code := int(t.get("code",-1))
        rt.tag_code_by_id[id] = code
        rt.tag_mask_by_id[id] = (1 << code)
    return rt

func enum_int(enum_name: String, value: String) -> int:
    var m: Dictionary = enum_tables.get(enum_name, {})
    return int(m.get(value, -1))

func tag_mask(tags: Array) -> int:
    var m := 0
    for t in tags:
        m |= int(tag_mask_by_id.get(String(t), 0))
    return m
```

- [ ] **Step 2: CompiledDataset（最小字段：id映射 + stat defs + buff defs 直通）**

```gdscript
class_name OmniCompiledDataset
extends RefCounted

var fingerprint: String = ""

var stat_id_to_int: Dictionary = {}
var stat_defs: Array[Dictionary] = []  # 暂用Dictionary；后续再packed化

var buff_id_to_int: Dictionary = {}
var buff_defs: Array[Dictionary] = []  # 暂用Dictionary；后续再packed化

func stat_id(id_str: String) -> int:
    return int(stat_id_to_int.get(id_str, -1))

func buff_id(id_str: String) -> int:
    return int(buff_id_to_int.get(id_str, -1))
```

- [ ] **Step 3: dataset_compiler.compile（raw json→索引化）**

```gdscript
class_name OmniDatasetCompiler
extends RefCounted

static func compile(manifest: Dictionary, enums_rt: OmniEnumsRuntime, sources: Dictionary) -> OmniCompiledDataset:
    var ds := OmniCompiledDataset.new()

    # stats
    var stat_defs := sources["stat_defs"].get("stats", [])
    for i in range(stat_defs.size()):
        var s: Dictionary = stat_defs[i]
        ds.stat_id_to_int[String(s["id"])] = i
        ds.stat_defs.append(s)

    # buffs
    var buff_defs := sources["buff_defs"].get("buffs", [])
    for i in range(buff_defs.size()):
        var b: Dictionary = buff_defs[i]
        ds.buff_id_to_int[String(b["id"])] = i
        ds.buff_defs.append(b)

    return ds
```

- [ ] **Step 4: demo_runner 调用 compile**

```gdscript
var lr := OmniManifestLoader.load_dataset("res://data/base_demo/manifest.json", true)
var enums_rt := OmniEnumsRuntime.from_enums_json(lr.enums)
var sources := {
    "stat_defs": OmniJson.load_dict("res://data/base_demo/stat_defs.json"),
    "buff_defs": OmniJson.load_dict("res://data/base_demo/buff_defs.json")
}
var ds := OmniDatasetCompiler.compile(lr.manifest, enums_rt, sources)
print("[OmniBuffDemo] stat_id(ATK)=", ds.stat_id("ATK"), " buff_id(buff_atk_up_3t)=", ds.buff_id("buff_atk_up_3t"))
```

- [ ] **Step 5: 运行验证**

Expected：stat_id 与 buff_id 输出为非 -1。

- [ ] **Step 6: Commit**

```bash
git add godot-buff/addons/omnibuff/runtime/core godot-buff/addons/omnibuff/config/compiler godot-buff/addons/omnibuff/demo/demo_runner.gd
git commit -m "feat(runtime): add enums runtime + minimal compiled dataset (int ids)"
```

---

## 6) Task 5（M2）：StatsCore（StatCache + DirtyFlags + apply_phase）

**Files:**
- Create: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`
- Create: `godot-buff/addons/omnibuff/runtime/components/stats_component.gd`
- Modify: `godot-buff/addons/omnibuff/demo/demo_runner.gd`（创建实体并读写stat）

- [ ] **Step 1: StatsCore（最小：base/final/dirty + get_final）**

```gdscript
class_name OmniStatsCore
extends RefCounted

var ds: OmniCompiledDataset
var base_values: PackedFloat32Array
var final_values: PackedFloat32Array
var dirty: PackedByteArray

func _init(dataset: OmniCompiledDataset) -> void:
    ds = dataset
    var n := ds.stat_defs.size()
    base_values = PackedFloat32Array()
    base_values.resize(n)
    final_values = PackedFloat32Array()
    final_values.resize(n)
    dirty = PackedByteArray()
    dirty.resize(n)
    for i in range(n):
        base_values[i] = float(ds.stat_defs[i].get("default", 0.0))
        final_values[i] = base_values[i]
        dirty[i] = 0

func set_base(stat_id: int, v: float) -> void:
    base_values[stat_id] = v
    dirty[stat_id] = 1

func add_base(stat_id: int, dv: float) -> void:
    base_values[stat_id] += dv
    dirty[stat_id] = 1

func mark_dirty(stat_id: int) -> void:
    dirty[stat_id] = 1

func get_final(stat_id: int) -> float:
    if dirty[stat_id] == 1:
        final_values[stat_id] = base_values[stat_id] # 先不处理modifier，下一Task接入
        dirty[stat_id] = 0
    return final_values[stat_id]
```

- [ ] **Step 2: StatsComponent（Entity挂载用）**

```gdscript
class_name OmniStatsComponent
extends RefCounted

var core: OmniStatsCore
var entity_id: int

func _init(eid: int, dataset: OmniCompiledDataset) -> void:
    entity_id = eid
    core = OmniStatsCore.new(dataset)

func get_final(stat_id: int) -> float:
    return core.get_final(stat_id)

func add_base(stat_id: int, dv: float) -> void:
    core.add_base(stat_id, dv)
```

- [ ] **Step 3: demo_runner 验证 dirty 行为**

```gdscript
var atk := ds.stat_id("ATK")
var s := OmniStatsComponent.new(1, ds)
print("ATK1=", s.get_final(atk))
s.add_base(atk, 5.0)
print("ATK2=", s.get_final(atk))
print("ATK3(no recompute)=", s.get_final(atk))
```

Expected：ATK1=10，ATK2=15，ATK3=15。

- [ ] **Step 4: Commit**

```bash
git add godot-buff/addons/omnibuff/runtime/core/stats_core.gd godot-buff/addons/omnibuff/runtime/components/stats_component.gd godot-buff/addons/omnibuff/demo/demo_runner.gd
git commit -m "feat(stats): add stat cache + dirty flags (base only)"
```

---

## 7) Task 6（M3）：BuffCore（modifier-only）+ “变动时维护聚合视图” 的最小实现

**Files:**
- Create: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- Create: `godot-buff/addons/omnibuff/runtime/components/buff_component.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`（接入modifier聚合）
- Modify: `godot-buff/addons/omnibuff/demo/demo_runner.gd`

- [ ] **Step 1: 定义最小 ModifierRef（仅支持 ADD/FLAT，先跑通）**

```gdscript
class_name OmniModifierRef
extends RefCounted

var stat_id: int
var add_value: float
var source_inst_id: int
```

- [ ] **Step 2: StatsCore 增加 per-stat modifier 列表，并在重算时叠加**

```gdscript
var modifiers_by_stat: Array[Array] = [] # [stat_id] -> Array[OmniModifierRef]

func _init(dataset: OmniCompiledDataset) -> void:
    # ...原初始化...
    modifiers_by_stat.resize(n)
    for i in range(n):
        modifiers_by_stat[i] = []

func recompute(stat_id: int) -> void:
    var v := base_values[stat_id]
    for m in modifiers_by_stat[stat_id]:
        v += m.add_value
    final_values[stat_id] = v

func get_final(stat_id: int) -> float:
    if dirty[stat_id] == 1:
        recompute(stat_id)
        dirty[stat_id] = 0
    return final_values[stat_id]
```

- [ ] **Step 3: BuffCore（只实现 apply/remove：把buff effects里的 ADD/FLAT 注入 StatsCore.modifiers_by_stat）**

```gdscript
class_name OmniBuffCore
extends RefCounted

var ds: OmniCompiledDataset
var next_inst_id := 1

class BuffInst:
    var inst_id: int
    var buff_def_id: int
    var source_entity_id: int
    var stacks: int
    var remaining_turns: int
    var tag_mask: int
    var modifier_refs: Array[OmniModifierRef] = []

func _init(dataset: OmniCompiledDataset) -> void:
    ds = dataset

func apply_buff(stats: OmniStatsComponent, buff_id_str: String, source_entity_id: int) -> int:
    var bdid := ds.buff_id(buff_id_str)
    if bdid < 0:
        push_error("[Buff] unknown buff_id=" + buff_id_str)
        return -1

    var inst := BuffInst.new()
    inst.inst_id = next_inst_id
    next_inst_id += 1
    inst.buff_def_id = bdid
    inst.source_entity_id = source_entity_id
    inst.stacks = 1
    inst.remaining_turns = int(ds.buff_defs[bdid].get("duration", {}).get("turns", -1))

    var effects: Array = ds.buff_defs[bdid].get("effects", [])
    for e in effects:
        if String(e.get("kind","")) != "modifier":
            continue
        if String(e.get("op","")) != "ADD":
            continue
        if String(e.get("phase","")) != "FLAT":
            continue
        var stat_id := ds.stat_id(String(e.get("stat","")))
        var v := float(e.get("value", 0.0))
        var mr := OmniModifierRef.new()
        mr.stat_id = stat_id
        mr.add_value = v
        mr.source_inst_id = inst.inst_id
        inst.modifier_refs.append(mr)
        stats.core.modifiers_by_stat[stat_id].append(mr)
        stats.core.mark_dirty(stat_id)

    # 先不做实例列表存储，下一任务补齐（叠加/持续/驱散）
    return inst.inst_id
```

- [ ] **Step 4: demo_runner 验证：apply “装备ATK+20” 后 ATK变化，且 deal_damage 不遍历buff**

```gdscript
var buff := OmniBuffCore.new(ds)
var eid := 1
var s := OmniStatsComponent.new(eid, ds)
print("ATK=", s.get_final(ds.stat_id("ATK")))
buff.apply_buff(s, "buff_equip_weapon_001", eid)
print("ATK(after equip buff)=", s.get_final(ds.stat_id("ATK")))
```

Expected：ATK(after)=30。

- [ ] **Step 5: Commit**

```bash
git add godot-buff/addons/omnibuff/runtime/core/buff_core.gd godot-buff/addons/omnibuff/runtime/core/stats_core.gd godot-buff/addons/omnibuff/demo/demo_runner.gd
git commit -m "feat(buff): apply modifier-only buffs by maintaining stat modifier lists"
```

---

## 8) Task 7（M4）：DamagePipeline 骨架（固定阶段）+ 读取StatCache

**Files:**
- Create: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`
- Modify: `godot-buff/addons/omnibuff/demo/demo_runner.gd`

- [ ] **Step 1: DamageContext**

```gdscript
class_name OmniDamageContext
extends RefCounted

var attacker_id: int
var defender_id: int
var skill_id: int
var damage_type: int
var element: int
var tags_mask: int
var hit: bool = true
var crit: bool = false
var base_damage: float = 0.0
var final_damage: float = 0.0
```

- [ ] **Step 2: DamagePipeline（先不做事件，仅跑通阶段顺序与扣HP）**

```gdscript
class_name OmniDamagePipeline
extends RefCounted

func deal_damage(attacker: OmniStatsComponent, defender: OmniStatsComponent, ds: OmniCompiledDataset, base_damage: float) -> OmniDamageContext:
    var ctx := OmniDamageContext.new()
    ctx.attacker_id = attacker.entity_id
    ctx.defender_id = defender.entity_id
    ctx.base_damage = base_damage

    # build
    # before_deal (reserved)
    # before_take (reserved)

    # resolve
    var atk := attacker.get_final(ds.stat_id("ATK"))
    var def := defender.get_final(ds.stat_id("DEF"))
    ctx.final_damage = max(0.0, base_damage + atk - def)

    # apply
    defender.add_base(ds.stat_id("HP"), -ctx.final_damage)

    # after_deal / after_take (reserved)
    return ctx
```

- [ ] **Step 3: demo_runner 验证一次伤害**

设置 attacker ATK=30（装备buff），defender DEF=5，base_damage=20。  
Expected：final_damage=45，defender HP 从100变55。

- [ ] **Step 4: Commit**

```bash
git add godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd godot-buff/addons/omnibuff/demo/demo_runner.gd
git commit -m "feat(damage): add fixed-stage damage pipeline skeleton (no events yet)"
```

---

## 9) Task 8（M5）：EventIndex + emit_event + triggers(filters)（保证只遍历子集）

**Files:**
- Create: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`

- [ ] **Step 1: EventIndex（key=event_type*phase_count+phase）**

```gdscript
class_name OmniEventIndex
extends RefCounted

var phase_count := 16
var listeners: Array[PackedInt32Array] = []

class Listener:
    var inst_id: int
    var filter_tag_mask: int
    var action_kind: String
    var action_value: float

var listener_data: Array[Listener] = []

func _init(event_key_count: int) -> void:
    listeners.resize(event_key_count)
    for i in range(event_key_count):
        listeners[i] = PackedInt32Array()

func register_listener(key: int, l: Listener) -> int:
    var id := listener_data.size()
    listener_data.append(l)
    listeners[key].append(id)
    return id
```

- [ ] **Step 2: BuffCore 接入 EventIndex（只实现一个示例触发：BEFORE_DEAL 时 ctx.base_damage += action_value）**

触发器定义读取自 buff_defs（未来改为编译后packed）；本任务可从 JSON 直读：
```json
{"event_type":"DAMAGE","event_phase":"BEFORE_DEAL","filters":{"tag_mask_any":["DOT"]},"action":{"kind":"ADD_BASE_DAMAGE","value":5}}
```

实现要求：
- 只在 apply_buff 时注册监听
- emit_event 时只遍历 listeners[key]
- filters：至少支持 tag_mask_any（ctx.tags_mask & filter_mask != 0）

- [ ] **Step 3: DamagePipeline 在固定阶段插入 emit_event**

阶段点：
- BUILD / BEFORE_DEAL / BEFORE_TAKE / RESOLVE / APPLY / AFTER_DEAL / AFTER_TAKE

- [ ] **Step 4: demo 验证“监听子集”**

构造：
- 100个与 DAMAGE/BEFORE_DEAL 无关的buff（无 trigger）
- 只有1个buff注册 BEFORE_DEAL

Expected：
- 触发时只遍历1个listener（日志打印 listeners[key].size() == 1）

- [ ] **Step 5: Commit**

```bash
git add godot-buff/addons/omnibuff/runtime/core/event_index.gd godot-buff/addons/omnibuff/runtime/core/buff_core.gd godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd
git commit -m "feat(events): add event index and phase-based emit (subset iteration only)"
```

---

## 10) Task 9（M6）：DOT（按来源独立实例）+ TurnEnd tick（动态读取来源StatCache）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`（DotInstance池）
- Create: `godot-buff/addons/omnibuff/runtime/components/turn_component.gd`
- Modify: `godot-buff/addons/omnibuff/demo/demo_runner.gd`

- [ ] **Step 1: DotInstance 结构 + 按来源独立**

要求：
- 同种DOT：`ownership_mode=BY_SOURCE_INSTANCE` → 每次施加创建新 dot_inst
- 存储：`dots_by_target: Dictionary(target_id -> Array[DotInstance])`

- [ ] **Step 2: TurnEnd tick**

对每个 dot：
- 读取 `src_atk = stats[source_entity_id].get_final(ATK)`
- `dmg = src_atk * base_ratio`
- 走 DamagePipeline（同阶段骨架）或简化版（但必须保持事件点一致）
- `remaining_turns -= 1`，到0移除

- [ ] **Step 3: demo 验证多来源**

构造两名施法者 A/B（ATK不同）对同目标上灼烧。  
Expected：
- 目标身上有2个dot实例（不同source_entity_id）
- 每跳伤害分别基于各自施法者ATK（动态读取）

- [ ] **Step 4: Commit**

```bash
git add godot-buff/addons/omnibuff/runtime/core/buff_core.gd godot-buff/addons/omnibuff/runtime/components/turn_component.gd godot-buff/addons/omnibuff/demo/demo_runner.gd
git commit -m "feat(dot): add per-source DOT instances and TurnEnd tick reading source stat cache"
```

---

## 11) Task 10（M7）：驱散语义（按Tag/来源/类型 + 不可驱散/免疫）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- Modify: `godot-buff/addons/omnibuff/demo/demo_runner.gd`

- [ ] **Step 1: 标准接口**

```gdscript
func remove_by_instance(target_id: int, inst_id: int) -> bool
func remove_by_tag(target_id: int, tag_id: String) -> int
func remove_by_source(target_id: int, source_entity_id: int) -> int
```

- [ ] **Step 2: 语义优先级**
1) 目标免疫 tags（target immunity mask）拦截驱散（返回0）
2) buff 标记不可驱散（skip）
3) 其余按 scope 执行

- [ ] **Step 3: demo 验证**
- 给目标上 1个可驱散debuff、1个不可驱散debuff、1个隐式装备buff  
Expected：
- 按tag驱散只移除可驱散目标
- 不可驱散保留
- 隐式buff默认不在驱散范围（除非scope包含）

- [ ] **Step 4: Commit**

```bash
git add godot-buff/addons/omnibuff/runtime/core/buff_core.gd godot-buff/addons/omnibuff/demo/demo_runner.gd
git commit -m "feat(dispel): add tag/source dispel with immunity and non-dispellable rules"
```

---

## 12) Task 11（M8）：本地回放/追帧（命令流 + DamageTrace）

**Files:**
- Create: `godot-buff/addons/omnibuff/runtime/core/replay.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`
- Modify: `godot-buff/addons/omnibuff/demo/demo_runner.gd`

- [ ] **Step 1: Command 结构与记录**

记录：
- CAST_SKILL（turn, actor_id, skill_id, targets, rng）
- USE_ITEM
- EQUIP_CHANGE

- [ ] **Step 2: DamageTrace**

每次伤害记录：
- ctx 输入/输出
- triggered_inst_ids（按触发顺序）
- DOT每跳记录 source_entity_id 与读取到的源ATK快照

- [ ] **Step 3: 回放执行顺序固定**
- TurnStart tick（entity_id asc）
- commands FIFO
- TurnEnd tick（entity_id asc）

- [ ] **Step 4: Commit**

```bash
git add godot-buff/addons/omnibuff/runtime/core/replay.gd godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd godot-buff/addons/omnibuff/demo/demo_runner.gd
git commit -m "feat(replay): add local command replay and damage trace"
```

---

## 13) Task 12（M9）：校验规则补齐 + migrate 框架

**Files:**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Modify: `godot-buff/addons/omnibuff/config/compiler/migrate.gd`

- [ ] **Step 1: 实现至少12条校验（Error/Warning分级）**

必须包含（严格模式阻断）：
- ID重复
- 引用不存在（stat/buff/skill等）
- 枚举非法（不在enums.json）
- tag非法（不在enums.json.tags）
- 范围非法（duration<0、max_stack<=0）
- OVERRIDE冲突
- CLAMP冲突
- damage_pipeline阶段缺失/顺序非法
- 无filter监听DAMAGE（至少 Warning）
- 无限触发链风险（深度上限/简单环检测）
- 未知字段（strict Error / lenient Warning）
- 循环依赖（Warning）

- [ ] **Step 2: migrate(from,to) 在线迁移接口（可先空实现但必须可调用）**

```gdscript
class_name OmniMigrate
extends RefCounted

static func migrate(schema_from: int, schema_to: int, obj: Dictionary) -> Dictionary:
    if schema_from == schema_to:
        return obj
    # 示例：1->2 的字段改名/默认值填充（后续按需实现）
    return obj
```

- [ ] **Step 3: Commit**

```bash
git add godot-buff/addons/omnibuff/config/compiler/validators.gd godot-buff/addons/omnibuff/config/compiler/migrate.gd
git commit -m "feat(schema): expand validators and add migrate framework"
```

---

## 14) Plan 自检（完成后执行）

### 14.1 Spec覆盖检查（对照实现Spec章节）
- 数据：manifest/enums/fingerprint/覆盖报告（Task2~4）
- 核心：StatsCore（Task5）、BuffCore（Task6）、DamagePipeline（Task7）
- 性能：EventIndex+filters（Task8）
- DOT（Task9）
- 驱散（Task10）
- 回放追帧（Task11）
- 校验与迁移（Task12）

### 14.2 Placeholder扫描
确认无 “TODO/TBD/后续再说/适当处理” 等空洞语句；每个任务都有可落地文件与代码片段。

---

## 15) 执行交接

计划已完成。两种执行选项：

1) **Subagent-Driven（推荐）**：每个Task派一个子agent实现，我做阶段性review（更快、更稳）
2) **Inline Execution**：我在本会话中按Task逐步落地实现（每个里程碑结束做一次review）

请选择其一后开始执行。
