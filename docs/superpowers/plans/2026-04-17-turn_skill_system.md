# turn_skill_system Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `res://addons/turn_skill_system/` 实现一个 Godot 4.7 插件：以 JSON 为权威的技能系统（active/passive/aura），带 Editor Dock 编辑器、index+lazy load 缓存、公式系统、3×3 网格站位 targeting，并与 `addons/omnibuff` 集成（damage 必须走 DamagePipeline，buff 必须走 BuffCore）。

**Architecture:** 插件启用时安装 Autoload（运行时上下文单例），但运行时 API 仍以 `class_name SkillRuntime` 的静态入口为主；`SkillDB` 负责 index 与懒加载；`TargetingRegistry/EffectRegistry` 负责可扩展规则；`OmniBuffAdapter` 封装所有与 omnibuff 的交互；`BattleEventBus` 提供对外领域事件。

**Tech Stack:** Godot 4.7, GDScript, EditorPlugin + Dock，OmniBuff（已存在），JSON 文件 IO。

---

## 0) File structure（本计划将创建/修改的文件）

### Create（插件）
- [ ] `addons/turn_skill_system/plugin.cfg`
- [ ] `addons/turn_skill_system/plugin.gd`（EditorPlugin：注册 Dock + 安装/卸载 Autoload）
- [ ] `addons/turn_skill_system/runtime/skill_autoload.gd`（Autoload：持有运行时上下文）
- [ ] `addons/turn_skill_system/runtime/skill_db.gd`
- [ ] `addons/turn_skill_system/runtime/skill_runtime.gd`
- [ ] `addons/turn_skill_system/runtime/battle_event_bus.gd`
- [ ] `addons/turn_skill_system/runtime/grid.gd`
- [ ] `addons/turn_skill_system/runtime/formula.gd`
- [ ] `addons/turn_skill_system/runtime/omni_buff_adapter.gd`
- [ ] `addons/turn_skill_system/runtime/skill_validator.gd`
- [ ] `addons/turn_skill_system/runtime/json_io.gd`
- [ ] `addons/turn_skill_system/runtime/index_builder.gd`
- [ ] `addons/turn_skill_system/runtime/targeting/targeting_registry.gd`
- [ ] `addons/turn_skill_system/runtime/targeting/first_enemy_targeting.gd`
- [ ] `addons/turn_skill_system/runtime/targeting/all_enemies_targeting.gd`
- [ ] `addons/turn_skill_system/runtime/targeting/single_cell_targeting.gd`
- [ ] `addons/turn_skill_system/runtime/targeting/cross_targeting.gd`
- [ ] `addons/turn_skill_system/runtime/effects/effect_registry.gd`
- [ ] `addons/turn_skill_system/runtime/effects/damage_effect.gd`
- [ ] `addons/turn_skill_system/runtime/effects/apply_buff_effect.gd`
- [ ] `addons/turn_skill_system/runtime/effects/remove_buff_effect.gd`
- [ ] `addons/turn_skill_system/runtime/effects/heal_effect.gd`（可选：先返回 predicted_deltas + demo 简单加 HP；后续再纳入 omnibuff）
- [ ] `addons/turn_skill_system/runtime/aura_manager.gd`
- [ ] `addons/turn_skill_system/runtime/passive_manager.gd`
- [ ] `addons/turn_skill_system/runtime/event_names.gd`（集中管理事件字符串常量）

### Create（编辑器）
- [ ] `addons/turn_skill_system/editor/skill_editor_dock.tscn`
- [ ] `addons/turn_skill_system/editor/skill_editor_dock.gd`

### Create（数据）
- [ ] `addons/turn_skill_system/data/skills/index.json`
- [ ] `addons/turn_skill_system/data/skills/active/act_demo_single.json`
- [ ] `addons/turn_skill_system/data/skills/active/act_demo_cross.json`
- [ ] `addons/turn_skill_system/data/skills/aura/aur_demo_front_row_atk.json`
- [ ] `addons/turn_skill_system/data/skills/passive/pas_demo_turn_start_buff.json`

### Create（demo）
- [ ] `addons/turn_skill_system/demo/demo_battle.tscn`
- [ ] `addons/turn_skill_system/demo/demo_battle.gd`
- [ ] `addons/turn_skill_system/demo/demo_unit.gd`

### Create（文档）
- [ ] `addons/turn_skill_system/README.md`

---

## Task 1: Scaffold 插件 + Autoload 安装（最小可启用）

**Files:**
- Create: `addons/turn_skill_system/plugin.cfg`
- Create: `addons/turn_skill_system/plugin.gd`
- Create: `addons/turn_skill_system/runtime/skill_autoload.gd`

- [ ] **Step 1: 创建 plugin.cfg**

```ini
[plugin]
name="Turn Skill System"
description="JSON-driven skill system integrated with OmniBuff"
author="YourName"
version="0.1.0"
script="res://addons/turn_skill_system/plugin.gd"
```

- [ ] **Step 2: 创建 Autoload 脚本（skill_autoload.gd）**

实现要点：
- `@tool` 不需要（runtime 用）
- 持有 `db/event_bus/targeting/effects/omnibuff_adapter/passive_manager/aura_manager`
- 提供 `ensure_ready()`：第一次使用时初始化（延迟加载）

代码骨架：
```gdscript
extends Node
class_name SkillAutoload

var db
var event_bus
var targeting
var effects
var omnibuff
var passive_manager
var aura_manager

func ensure_ready() -> void:
	if db != null:
		return
	# 这里 new 各模块（在后续任务实现具体脚本后补全 preload 路径）
```

- [ ] **Step 3: 创建 EditorPlugin（plugin.gd）并安装/卸载 Autoload**

需求：
- `_enter_tree`：添加 Dock；安装 autoload（名称建议 `TurnSkillRuntime`）
- `_exit_tree`：移除 Dock；移除 autoload

关键片段（与 omnibuff plugin.gd 风格一致）：
```gdscript
@tool
extends EditorPlugin

const AUTOLOAD_NAME := "TurnSkillRuntime"
const AUTOLOAD_PATH := "res://addons/turn_skill_system/runtime/skill_autoload.gd"

func _enter_tree() -> void:
	_install_autoload()
	# add_control_to_dock(...) 在 Task 6 实现

func _exit_tree() -> void:
	# remove_control_from_docks(...) 在 Task 6 实现
	_remove_autoload()

func _install_autoload() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		return
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	ProjectSettings.save()

func _remove_autoload() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		return
	remove_autoload_singleton(AUTOLOAD_NAME)
	ProjectSettings.save()
```

- [ ] **Step 4: 手动验证插件可启用**

在 Godot 编辑器：
1. Project Settings → Plugins → 勾选 `Turn Skill System`
2. 检查 Project Settings → Autoload：出现 `TurnSkillRuntime`
3. 取消勾选插件后，Autoload 被移除

---

## Task 2: SkillDB（index + lazy load + cache）+ IndexBuilder

**Files:**
- Create: `addons/turn_skill_system/runtime/skill_db.gd`
- Create: `addons/turn_skill_system/runtime/index_builder.gd`
- Create: `addons/turn_skill_system/runtime/json_io.gd`
- Create: `addons/turn_skill_system/runtime/skill_validator.gd`

- [ ] **Step 1: 创建 json_io.gd（稳定序列化 + 读写）**

必须能力：
- `read_json(path) -> {ok, data, error}`
- `write_json_stable(path, data, preferred_order:Array[String])`
- “稳定输出”策略：递归重排 key（优先字段序 + unknown keys 字母序），缩进 2 spaces

核心函数骨架：
```gdscript
extends RefCounted
class_name JsonIO

static func read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "open_failed:" + path}
	var txt := f.get_as_text()
	var parsed := JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY and typeof(parsed) != TYPE_ARRAY:
		return {"ok": false, "error": "parse_failed:" + path}
	return {"ok": true, "data": parsed}
```

- [ ] **Step 2: 创建 skill_validator.gd（strict/lenient + field_path 报错）**

接口：
```gdscript
extends RefCounted
class_name SkillValidator

static func validate_skill(skill: Dictionary, file_path: String, strict: bool) -> Array[Dictionary]:
	# return issues: [{severity,file_path,field_path,message}]
```

必须校验（strict）：
- `version:int`
- `id:string`
- `type in ["active","passive","aura"]`
- active: `on_cast:Array` + `on_hit:Array`（允许为空数组，但字段必须存在）
- passive: `triggers:Array`（至少存在；可为空）
- aura: `aura:Dictionary` + `aura.on_enter/on_exit:Array`
- targeting: 允许 string（FIRST/ALL）或 object（rule/params...）

- [ ] **Step 3: 创建 index_builder.gd（扫描三目录生成 index.json）**

接口：
```gdscript
extends RefCounted
class_name IndexBuilder

const SKILL_ROOT := "res://addons/turn_skill_system/data/skills"

static func rebuild_index() -> Dictionary:
	# return {ok, index, issues}
```

实现要点：
- 扫描：
  - `SKILL_ROOT + "/active"`
  - `SKILL_ROOT + "/passive"`
  - `SKILL_ROOT + "/aura"`
- 只读取每个 json 的必要字段：`id,type,name,tags,version`
- mtime：用 `FileAccess.get_modified_time(path)`（Godot 4）或 `FileAccess.get_modified_time` 替代方案（若不可用则先不写 mtime，改用 hash）

- [ ] **Step 4: 创建 skill_db.gd（加载 index + lazy load）**

接口：
```gdscript
extends RefCounted
class_name SkillDB

const INDEX_PATH := "res://addons/turn_skill_system/data/skills/index.json"

var _index := {}          # id -> entry
var _cache := {}          # id -> skill dict

func reload_index() -> void: pass
func clear_cache() -> void: pass
func get_skill(skill_id: String, strict := true) -> Dictionary: pass
```

行为要求：
- `reload_index()` 只读 index.json
- `get_skill()`：
  - 未命中 index：返回 `{ok:false, errors:[...]}`
  - 命中后读目标 json，validator 严格校验
  - unknown fields 不动（只负责读取）

- [ ] **Step 5: 最小验证（index → get_skill）**

手动：
- 先写一个最小 index.json + 一个技能 json（Task 8 会补齐）
- 在 Godot 的脚本控制台执行：
```gdscript
var db := SkillDB.new()
db.reload_index()
print(db.get_skill("act_demo_single"))
```

---

## Task 3: Grid（3×3）+ TargetingRegistry（FIRST/ALL/single_cell/cross）

**Files:**
- Create: `addons/turn_skill_system/runtime/grid.gd`
- Create: `addons/turn_skill_system/runtime/targeting/targeting_registry.gd`
- Create: `addons/turn_skill_system/runtime/targeting/first_enemy_targeting.gd`
- Create: `addons/turn_skill_system/runtime/targeting/all_enemies_targeting.gd`
- Create: `addons/turn_skill_system/runtime/targeting/single_cell_targeting.gd`
- Create: `addons/turn_skill_system/runtime/targeting/cross_targeting.gd`

- [ ] **Step 1: grid.gd**

约定：cell 的 `Vector2i(row, col)`，范围 0..2。

核心接口：
```gdscript
extends RefCounted
class_name Grid

const GRID_SIZE := 3
var _units := [] # Array[Unit]

func set_units(units: Array) -> void: _units = units
func is_valid_cell(cell: Vector2i) -> bool: return cell.x>=0 and cell.x<GRID_SIZE and cell.y>=0 and cell.y<GRID_SIZE
func get_unit_at(cell: Vector2i) -> Variant: ...
func get_units_by_camp(camp: String, alive_only := true) -> Array: ...
func get_first_enemy(caster) -> Variant: ...
```

- [ ] **Step 2: targeting_registry.gd**

```gdscript
extends RefCounted
class_name TargetingRegistry

var _rules := {} # rule_id -> handler RefCounted

func register_defaults() -> void:
	register_rule("first_enemy", preload(...).new())
	...

func resolve(skill: Dictionary, caster, primary_cell, grid: Grid, extra: Dictionary) -> Array[Dictionary]:
	# return [{unit, unit_id, cell, role}]
```

- [ ] **Step 3: 实现 FIRST/ALL 兼容**

解析规则：
- 若 `skill["targeting"]` 为 `"FIRST"`：调用 `first_enemy`
- 若为 `"ALL"`：调用 `all_enemies`
- 若为 object：按 `rule`

- [ ] **Step 4: 实现 `single_cell` 与 `cross`**

`single_cell`：需要 primary_cell（或 needs_primary=false 时走 fallback）

`cross`：中心=primary_cell，取（中心+上下左右）并过滤越界、空格、死亡。

- [ ] **Step 5: 最小验证**

在 demo 或脚本控制台构造 2 个单位（enemy）：
- FIRST 选到一个
- ALL 返回全部
- cross 返回十字范围内目标

---

## Task 4: BattleEventBus + 事件常量（默认命名、尽量完整）

**Files:**
- Create: `addons/turn_skill_system/runtime/event_names.gd`
- Create: `addons/turn_skill_system/runtime/battle_event_bus.gd`

- [ ] **Step 1: event_names.gd**

```gdscript
extends RefCounted
class_name EventNames

const TURN_STARTED := "turn_started"
const TURN_ENDED := "turn_ended"
const ACTION_STARTED := "action_started"
const ACTION_FINISHED := "action_finished"
const SKILL_CAST_STARTED := "skill_cast_started"
const SKILL_CAST_FINISHED := "skill_cast_finished"
const BEFORE_DAMAGE := "before_damage"
const AFTER_DAMAGE := "after_damage"
const BEFORE_HEAL := "before_heal"
const AFTER_HEAL := "after_heal"
const UNIT_DIED := "unit_died"
const UNIT_REVIVED := "unit_revived"
const UNIT_MOVED := "unit_moved"
const GRID_CHANGED := "grid_changed"
```

- [ ] **Step 2: battle_event_bus.gd**

需求：
- `signal event_emitted(event_type: String, data: Dictionary)`
- `emit_event(event_type, data)`：发信号并可选记录（用于 cast 返回 events）

```gdscript
extends RefCounted
class_name BattleEventBus

signal event_emitted(event_type: String, data: Dictionary)

var _capture := false
var _captured := [] # Array[Dictionary]

func begin_capture() -> void:
	_capture = true
	_captured.clear()

func end_capture() -> Array:
	_capture = false
	return _captured.duplicate(true)

func emit_event(event_type: String, data: Dictionary) -> void:
	if _capture:
		_captured.append({"type": event_type, "data": data})
	event_emitted.emit(event_type, data)
```

---

## Task 5: Formula（Expression + 变量追踪 + 默认 floor）

**Files:**
- Create: `addons/turn_skill_system/runtime/formula.gd`

- [ ] **Step 1: formula.gd**

接口：
```gdscript
extends RefCounted
class_name Formula

static func eval_expr(expr: String, ctx: Dictionary, rounding := "floor") -> Dictionary:
	# return {ok, value, resolved:{expr,vars,result}, error}
```

要点：
- 只暴露纯数字变量，不暴露对象；
- 支持 `a.ATK`/`t.DEF`：替换成 `a_ATK`/`t_DEF`；
- 抓取 vars：输出 `{ "a.ATK": 100, "t.DEF": 50 }`；
- rounding 缺省 `floor`（你已确认）。

---

## Task 6: OmniBuffAdapter（damage 必走 pipeline；buff 必走 BuffCore）

**Files:**
- Create: `addons/turn_skill_system/runtime/omni_buff_adapter.gd`

- [ ] **Step 1: 定义适配器接口**

```gdscript
extends RefCounted
class_name OmniBuffAdapter

var ds
var enums_rt
var runtime_dict
var pipe
var replay

func setup(dataset, enums_runtime, runtime: Dictionary) -> void:
	ds = dataset
	enums_rt = enums_runtime
	runtime_dict = runtime
	pipe = OmniBuff.DamagePipeline.new()
	replay = OmniBuff.Replay.new()
```

- [ ] **Step 2: damage（必须走 DamagePipeline）**

要求：
- 优先调用 `pipe.deal_damage(...)`
- 若因签名差异调用失败，则 fallback `deal_damage_v1(...)`
- 返回 `{ok, final_damage, trace_meta...}`

> 注意：这里 plan 不强行写死 `deal_damage(...)` 的参数表（以免与你 omnibuff 当前实现不一致导致误导）；实现时以你仓库内 `addons/omnibuff/runtime/core/damage_pipeline.gd` 的真实签名为准，且必须保留 `deal_damage_v1` 兜底路径。

- [ ] **Step 3: apply/remove buff**

```gdscript
func apply_buff(target_unit, buff_id: String, source_unit) -> Dictionary:
	var inst_id := target_unit.buffs.apply_buff(target_unit.stats, buff_id, int(source_unit.entity_id))
	return {"ok": inst_id >= 0, "inst_id": inst_id}

func remove_buff(target_unit, buff_id: String, source_unit, remove_scope := "ALL") -> Dictionary:
	var source_id := int(source_unit.entity_id)
	var removed := target_unit.buffs.remove_by_buff_id(target_unit.stats, buff_id, remove_scope, source_id, false, true)
	return {"ok": removed > 0, "removed": removed}
```

- [ ] **Step 4: simulate_*（不落地）**

返回预测描述：
```gdscript
func simulate_apply_buff(target_unit, buff_id: String, source_unit) -> Dictionary:
	return {"kind":"apply_buff","buff_id":buff_id,"target_id":target_unit.entity_id,"source_id":source_unit.entity_id}
```

---

## Task 7: EffectRegistry + damage/apply_buff/remove_buff（对齐 on_cast/on_hit）

**Files:**
- Create: `addons/turn_skill_system/runtime/effects/effect_registry.gd`
- Create: `addons/turn_skill_system/runtime/effects/damage_effect.gd`
- Create: `addons/turn_skill_system/runtime/effects/apply_buff_effect.gd`
- Create: `addons/turn_skill_system/runtime/effects/remove_buff_effect.gd`

- [ ] **Step 1: effect_registry.gd**

```gdscript
extends RefCounted
class_name EffectRegistry

var _handlers := {} # kind -> handler

func register_defaults() -> void:
	_handlers["damage"] = preload("res://addons/turn_skill_system/runtime/effects/damage_effect.gd").new()
	_handlers["apply_buff"] = preload(...).new()
	_handlers["remove_buff"] = preload(...).new()

func apply_effect(effect: Dictionary, ctx: Dictionary, simulation: bool) -> Dictionary:
	var kind := String(effect.get("kind",""))
	if not _handlers.has(kind):
		return {"ok": false, "error": "unknown_effect_kind:" + kind}
	return _handlers[kind].apply(effect, ctx, simulation)
```

- [ ] **Step 2: damage_effect.gd**

行为：
- 从 `effect.params.amount` 或 `amount_expr` 求 base_damage
- 调用 `ctx.omnibuff.deal_damage(...)`
- 产出 cast 返回需要的 `effects[]` 元素（kind/value/meta）

- [ ] **Step 3: apply/remove buff effects**

从 `ctx.target` 或 `ctx.caster` 取作用对象，调用 adapter；simulate 走 simulate_*。

---

## Task 8: SkillRuntime（cast / cast_to_unit / cast_to_cell / simulate_cast）

**Files:**
- Create: `addons/turn_skill_system/runtime/skill_runtime.gd`

- [ ] **Step 1: 约定返回结构与日志开关**

`extra` 建议字段：
- `rng_seed:int`
- `log_enabled:bool`
- `turn_index:int`
- `battle_id:String`
- `runtime_dict:Dictionary`（omnibuff runtime）
- `dataset/enums_rt`（omnibuff dataset）
- `grid:Grid`（若未走 autoload 注入）
- `event_bus:BattleEventBus`（若未走 autoload 注入）

- [ ] **Step 2: cast 主流程（active）**

伪代码（实现时严格用 snake_case）：
```gdscript
static func cast(skill_id: String, caster, primary_cell := null, extra := {}) -> Dictionary:
	var rt := _get_runtime(extra) # autoload 优先
	rt.event_bus.begin_capture()
	rt.event_bus.emit_event(EventNames.SKILL_CAST_STARTED, {...})

	var skill := rt.db.get_skill(skill_id, true)
	# validate ok
	var targets := rt.targeting.resolve(skill, caster, primary_cell, rt.grid, extra)

	# on_cast
	for e in skill.get("on_cast", []):
		rt.effects.apply_effect(e, _make_ctx(...), false)

	# on_hit: target-major + hit loop
	...

	rt.event_bus.emit_event(EventNames.SKILL_CAST_FINISHED, {...})
	var events := rt.event_bus.end_capture()
	return {..., "events": events}
```

- [ ] **Step 3: simulate_cast**

同流程但：
- adapter 走 simulate_*；
- 返回 `simulation:true` + `predicted_deltas`。

- [ ] **Step 4: cast_to_unit / cast_to_cell**

`cast_to_cell` 校验 0..2；`cast_to_unit` 使用 `primary_target.cell`。

---

## Task 9: PassiveManager + AuraManager（最小闭环）

**Files:**
- Create: `addons/turn_skill_system/runtime/passive_manager.gd`
- Create: `addons/turn_skill_system/runtime/aura_manager.gd`

- [ ] **Step 1: PassiveManager（监听 event_bus）**
- register：`register_unit_passives(unit, skill_ids:Array[String])`
- 在 `event_bus.event_emitted` 上处理 triggers

- [ ] **Step 2: AuraManager（差集 enter/exit）**
- register：`register_aura(owner_unit, aura_skill_id)`
- 在 `unit_moved/grid_changed/unit_died` 时 refresh
- 对差集调用 `aura.on_enter/on_exit` 的 effects（通常 apply/remove buff）

---

## Task 10: Editor Dock（浏览/搜索/新建/编辑/预览 + index 生成）

**Files:**
- Create: `addons/turn_skill_system/editor/skill_editor_dock.tscn`
- Create: `addons/turn_skill_system/editor/skill_editor_dock.gd`
- Modify: `addons/turn_skill_system/plugin.gd`（真正 add dock）

- [ ] **Step 1: Dock UI（最小可用）**
- 左：ItemList + 搜索框 + 类型过滤
- 右：TextEdit（编辑整份 JSON），并提供：
  - Validate
  - Save
  - New（按 type 模板）
  - Rebuild Index
  - Simulate（调用 SkillRuntime.simulate_cast 打印结果）

- [ ] **Step 2: unknown fields 保留**
- 因为直接编辑整份 JSON（TextEdit），天然保留 unknown fields；
- 保存时仍走 validator + json_io.write_json_stable（稳定缩进与字段排序）。

---

## Task 11: Demo + 示例技能 JSON + README

**Files:**
- Create: `addons/turn_skill_system/demo/demo_unit.gd`
- Create: `addons/turn_skill_system/demo/demo_battle.tscn`
- Create: `addons/turn_skill_system/demo/demo_battle.gd`
- Create: `addons/turn_skill_system/data/skills/**`
- Create: `addons/turn_skill_system/README.md`

- [ ] **Step 1: demo_unit.gd（字段契约）**

字段必须：
```gdscript
extends RefCounted
class_name DemoUnit

var entity_id: int
var camp: String
var cell: Vector2i
var stats
var buffs
```

- [ ] **Step 2: demo_battle.gd（加载 omnibuff dataset + runtime dict）**
- 使用：`res://data/rpg_tests/manifest.json`（与你参考 skill_defs.json 同源）
- 构造 2~4 个单位 stats/buffs：
  - `stats := OmniBuff.StatsComponent.new(eid, ds)`
  - `buffs := OmniBuff.BuffCore.new(ds, enums_rt)`
- runtime dict：
```gdscript
var runtime := {"stats_by_entity": {...}, "buff_by_entity": {...}}
```

- [ ] **Step 3: 示例技能 JSON（每技能一个文件）**
- active：单体（FIRST）+ 公式
- active：cross（needs_primary=true）+ 公式
- passive：turn_started 给自己上 buff
- aura：前排光环 enter/exit 上下 buff

- [ ] **Step 4: index.json（由 IndexBuilder 生成）**

- [ ] **Step 5: README**
- 启用插件
- 编辑器 Dock 用法
- cast/cast_to_unit/cast_to_cell/simulate_cast
- 扩展点：targeting/effects/conditions/triggers
- omnibuff 对接点：集中在 omni_buff_adapter.gd

---

## Self-Review（计划自检）

- **Spec 覆盖**：active/passive/aura、JSON 权威、index+lazy load、校验与报错定位、unknown fields 保留、3×3 targeting、公式系统默认 floor、omnibuff 伤害+buff 集成、Autoload、Dock、Demo —— 均有对应任务。
- **Placeholder scan**：仅 OmniBuff DamagePipeline 的“新签名”在 plan 中不写死参数表（避免与仓库实现不一致）；执行时以代码库真实签名为准，且必须保留 v1 兜底。这是刻意的“防误导”设计，而不是 TBD。

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-17-turn_skill_system.md`. Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

