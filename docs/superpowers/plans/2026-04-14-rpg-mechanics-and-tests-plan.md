# RPG Mechanics + Complex GUT Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 扩展 OmniBuff 的运行时以支持更贴近真实 RPG 的机制（百分比加成、护盾吸收、减伤、命中/暴击确定性 RNG），并新增一个独立测试数据集 `data/rpg_tests/` 与一组更复杂的 GUT 回归用例（包含“多段攻击每段附加 DOT”可选项）。

**Architecture:** 采用 TDD：每个机制先写 failing test（GUT），再做最小实现让测试通过；测试数据与 demo 数据隔离（`data/rpg_tests`），测试 helper 增加 `load_rpg_tests`；DamagePipeline 在 resolve/apply 处扩展护盾/减伤/命中/暴击，StatsCore 扩展 ADD/FLAT + MUL/PERCENT 的聚合重算。所有热路径仍遵守 StatCache + EventIndex 约束。

**Tech Stack:** Godot 4.7 + GDScript + GUT（`res://addons/gut`）+ headless（可选）+ 数据驱动（manifest/enums/stat_defs/buff_defs）。

---

## 0) 文件结构（将创建/修改哪些文件）

### 0.1 新建（测试数据集）
- Create: `godot-buff/data/rpg_tests/manifest.json`
- Create: `godot-buff/data/rpg_tests/stat_defs.json`
- Create: `godot-buff/data/rpg_tests/buff_defs.json`
- Create: `godot-buff/data/rpg_tests/skill_defs.json`（仅用于测试“多段每段附加 DOT”描述；运行时仍由测试脚本执行）
- Create: `godot-buff/data/rpg_tests/damage_pipeline.json`（可复用 base_demo 的结构，避免 validators 报缺失）

### 0.2 修改（运行时机制）
- Modify: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`（effects 支持 MUL/PERCENT）
- Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`（命中/暴击/减伤/护盾）
- Modify: `godot-buff/addons/omnibuff/runtime/core/replay.gd`（DamageTrace 增加 hit/crit 记录）

### 0.3 修改（测试 helper）
- Modify: `godot-buff/addons/omnibuff/tests/helpers/test_dataset.gd`（增加 load_rpg_tests）

### 0.4 新建（复杂 GUT 用例）
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_percent_modifier.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_shield_absorb.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_damage_reduction.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_hit_and_crit_deterministic.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_multihit_each_hit_applies_dot.gd`

---

## Task 1：创建独立测试数据集 data/rpg_tests

**Files:**
- Create: `godot-buff/data/rpg_tests/manifest.json`
- Create: `godot-buff/data/rpg_tests/stat_defs.json`
- Create: `godot-buff/data/rpg_tests/buff_defs.json`
- Create: `godot-buff/data/rpg_tests/skill_defs.json`
- Create: `godot-buff/data/rpg_tests/damage_pipeline.json`

- [ ] **Step 1: 创建 manifest.json（复用 base_demo/enums.json）**

```json
{
  "schema_version": 1,
  "files": [
    { "type": "manifest", "path": "manifest.json", "format": "json" },
    { "type": "enums", "path": "../base_demo/enums.json", "format": "json" },
    { "type": "stat_defs", "path": "stat_defs.json", "format": "json" },
    { "type": "buff_defs", "path": "buff_defs.json", "format": "json" },
    { "type": "skill_defs", "path": "skill_defs.json", "format": "json" },
    { "type": "damage_pipeline", "path": "damage_pipeline.json", "format": "json" }
  ]
}
```

- [ ] **Step 2: 创建 stat_defs.json（在 base_demo 基础上增加命中/减伤相关 stat）**

```json
{
  "stats": [
    { "id": "HP", "default": 100.0, "min": 0.0, "max": 99999.0, "clamp": true },
    { "id": "ATK", "default": 10.0, "min": 0.0, "max": 9999.0, "clamp": true },
    { "id": "DEF", "default": 5.0, "min": 0.0, "max": 9999.0, "clamp": true },
    { "id": "CRIT_RATE", "default": 0.05, "min": 0.0, "max": 1.0, "clamp": true },
    { "id": "CRIT_DMG", "default": 0.5, "min": 0.0, "max": 5.0, "clamp": true },
    { "id": "HIT_RATE", "default": 1.0, "min": 0.0, "max": 1.0, "clamp": true },
    { "id": "EVADE", "default": 0.0, "min": 0.0, "max": 1.0, "clamp": true },
    { "id": "DMG_REDUCE", "default": 0.0, "min": 0.0, "max": 0.95, "clamp": true },
    { "id": "SHIELD", "default": 0.0, "min": 0.0, "max": 99999.0, "clamp": true }
  ]
}
```

- [ ] **Step 3: 创建 buff_defs.json（新增测试用 buff）**

```json
{
  "buffs": [
    {
      "id": "buff_atk_flat_20",
      "name": "测试：ATK+20(flat)",
      "buff_type": "EXPLICIT",
      "tags": ["BUFF"],
      "duration": { "type": "PERMANENT" },
      "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
      "effects": [
        { "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 20.0 }
      ],
      "triggers": []
    },
    {
      "id": "buff_atk_pct_5",
      "name": "测试：ATK+5%(percent)",
      "buff_type": "PASSIVE",
      "tags": ["BUFF"],
      "duration": { "type": "PERMANENT" },
      "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
      "effects": [
        { "kind": "modifier", "stat": "ATK", "op": "MUL", "phase": "PERCENT", "priority": 110, "value": 0.05 }
      ],
      "triggers": []
    },
    {
      "id": "buff_def_flat_20",
      "name": "测试：DEF+20(flat)",
      "buff_type": "EXPLICIT",
      "tags": ["BUFF"],
      "duration": { "type": "PERMANENT" },
      "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
      "effects": [
        { "kind": "modifier", "stat": "DEF", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 20.0 }
      ],
      "triggers": []
    },
    {
      "id": "buff_shield_50",
      "name": "测试：护盾+50",
      "buff_type": "EXPLICIT",
      "tags": ["BUFF"],
      "duration": { "type": "PERMANENT" },
      "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
      "effects": [
        { "kind": "modifier", "stat": "SHIELD", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 50.0 }
      ],
      "triggers": []
    },
    {
      "id": "buff_dmg_reduce_20p",
      "name": "测试：受到伤害-20%",
      "buff_type": "EXPLICIT",
      "tags": ["BUFF"],
      "duration": { "type": "PERMANENT" },
      "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
      "effects": [
        { "kind": "modifier", "stat": "DMG_REDUCE", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 0.20 }
      ],
      "triggers": []
    },
    {
      "id": "buff_force_crit",
      "name": "测试：必暴击（CRIT_RATE=1）",
      "buff_type": "EXPLICIT",
      "tags": ["BUFF"],
      "duration": { "type": "PERMANENT" },
      "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
      "effects": [
        { "kind": "modifier", "stat": "CRIT_RATE", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 0.95 }
      ],
      "triggers": []
    },
    {
      "id": "buff_force_miss",
      "name": "测试：必未命中（HIT_RATE=0）",
      "buff_type": "EXPLICIT",
      "tags": ["DEBUFF"],
      "duration": { "type": "PERMANENT" },
      "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
      "effects": [
        { "kind": "modifier", "stat": "HIT_RATE", "op": "OVERRIDE", "phase": "FINAL", "priority": 100, "value": 0.0 }
      ],
      "triggers": []
    },
    {
      "id": "buff_dot_fire_3t",
      "name": "测试：灼烧DOT（3回合/回合结束结算）",
      "buff_type": "EXPLICIT",
      "tags": ["DEBUFF", "DOT", "FIRE"],
      "duration": { "type": "TURNS", "turns": 3, "tick_phase": "TURN_END" },
      "stack": { "mode": "MULTI_INSTANCE", "max_stack": 99, "refresh_policy": "RESET_TO_MAX", "ownership_mode": "BY_SOURCE_INSTANCE" },
      "dot": { "tick_phase": "TURN_END", "element": "FIRE", "base_ratio": 0.3, "read_source_stat": "ATK" },
      "effects": [],
      "triggers": []
    },
    {
      "id": "buff_on_hit_apply_dot",
      "name": "测试：AFTER_DEAL 给目标挂灼烧",
      "buff_type": "EXPLICIT",
      "tags": ["BUFF"],
      "duration": { "type": "PERMANENT" },
      "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
      "effects": [],
      "triggers": [
        {
          "event_type": "DAMAGE",
          "event_phase": "AFTER_DEAL",
          "scope": "TARGET",
          "filters": { "tag_mask_any": ["BUFF"] },
          "action": { "kind": "APPLY_BUFF", "buff_id": "buff_dot_fire_3t" }
        }
      ]
    }
  ]
}
```

> 注意：此处故意包含 `OVERRIDE/FINAL`（用于 force_miss），因此后续机制实现必须支持 OVERRIDE/FINAL；若你不希望本阶段引入 OVERRIDE，我们可以把 force_miss 改为用 `ADD` 把 HIT_RATE 扣到 0（前提默认 HIT_RATE=1.0）。

- [ ] **Step 4: 创建 damage_pipeline.json（最小合法，满足 validators）**

```json
{
  "pipeline": [
    { "stage": "build" },
    { "stage": "before_deal" },
    { "stage": "before_take" },
    { "stage": "resolve" },
    { "stage": "apply" },
    { "stage": "after_deal" },
    { "stage": "after_take" },
    { "stage": "death" }
  ]
}
```

- [ ] **Step 5: 创建 skill_defs.json（占位，避免 validators 报缺失；由测试脚本驱动多段）**

```json
{
  "skills": [
    {
      "id": "skill_triple_slash",
      "name": "三连斩（3段递增）",
      "damage_type": "PHYSICAL",
      "element": "NONE",
      "tags": ["BUFF"],
      "base_damage": 0,
      "on_cast": [],
      "on_hit": []
    }
  ]
}
```

- [ ] **Step 6: 提交**

```bash
git add godot-buff/data/rpg_tests
git commit -m "test(data): add rpg_tests dataset for complex mechanics"
```

---

## Task 2：扩展测试 helper 支持 load_rpg_tests

**Files:**
- Modify: `godot-buff/addons/omnibuff/tests/helpers/test_dataset.gd`

- [ ] **Step 1: 增加 load_rpg_tests()**

```gdscript
static func load_rpg_tests(strict: bool = true) -> Dictionary:
	var result := OmniManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", strict)
	var enums_rt := OmniEnumsRuntime.from_enums_json(result.enums)
	var ds := OmniDatasetCompiler.compile(result.manifest, enums_rt, result.sources)
	return {"result": result, "enums_rt": enums_rt, "ds": ds}
```

- [ ] **Step 2: 提交**

```bash
git add godot-buff/addons/omnibuff/tests/helpers/test_dataset.gd
git commit -m "test: add load_rpg_tests helper"
```

---

## Task 3：TDD 1/4 —— 支持 MUL/PERCENT（百分比加成）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_percent_modifier.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 写 failing test（ATK=(10+20)*1.05=31.5）**

`test_percent_modifier.gd`：
```gdscript
extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")

func test_percent_modifier_applies_after_flat() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds = loaded.ds
	var enums_rt = loaded.enums_rt

	var s := OmniStatsComponent.new(4001, ds)
	var b := OmniBuffCore.new(ds, enums_rt)
	b.apply_buff(s, "buff_atk_flat_20", 4001)
	b.apply_buff(s, "buff_atk_pct_5", 4001)

	var atk := s.get_final(ds.stat_id("ATK"))
	assert_eq(atk, 31.5)
```

- [ ] **Step 2: 扩展 BuffCore.apply_buff 接受 op=MUL & phase=PERCENT**

在 `buff_core.gd` 的 effects 处理处新增：
```gdscript
if String(e.get("kind","")) != "modifier":
	continue
var op := String(e.get("op",""))
var phase := String(e.get("phase",""))
if not ((op == "ADD" and phase == "FLAT") or (op == "MUL" and phase == "PERCENT")):
	continue
```
并在 `OmniModifierRef` 增加字段（带注释）：
```gdscript
var op: String
var phase: String
var value: float
```
将原 add_value 改为 value（或保留 add_value 兼容，但 recompute 要读 value）。

- [ ] **Step 3: 扩展 StatsCore.recompute 支持 percent_sum**

在 `stats_core.gd`：
```gdscript
var v := base_values[stat_id]
var flat := 0.0
var pct := 0.0
for m in modifiers_by_stat[stat_id]:
	if m.op == "ADD" and m.phase == "FLAT":
		flat += float(m.value)
	elif m.op == "MUL" and m.phase == "PERCENT":
		pct += float(m.value)
v = (v + flat) * (1.0 + pct)
final_values[stat_id] = v
```

- [ ] **Step 4: 跑测试并修到 PASS**

在编辑器 GUT 面板运行 `res://addons/omnibuff/tests/rpg/test_percent_modifier.gd`  
Expected：PASS

- [ ] **Step 5: 提交**

```bash
git add godot-buff/addons/omnibuff/runtime/core/stats_core.gd godot-buff/addons/omnibuff/runtime/core/buff_core.gd godot-buff/addons/omnibuff/tests/rpg/test_percent_modifier.gd
git commit -m "feat(stats): support percent modifiers (MUL/PERCENT) with tests"
```

---

## Task 4：TDD 2/4 —— 护盾吸收（SHIELD）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_shield_absorb.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`

- [ ] **Step 1: 写 failing test（单次与多段）**

```gdscript
extends GutTest
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_shield_absorbs_before_hp() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds = loaded.ds
	var enums_rt = loaded.enums_rt
	var pipe := OmniDamagePipeline.new()

	var a := TestBattle.make_entity(5001, ds, enums_rt)
	a.buffs.apply_buff(a.stats, "buff_atk_flat_20", 5001) # ATK=30
	var d := TestBattle.make_entity(5002, ds, enums_rt)
	d.buffs.apply_buff(d.stats, "buff_shield_50", 5002) # SHIELD=50

	var runtime := TestBattle.make_runtime([a, d])
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 让最终伤害=40（base=15 => 15 + 30 - 5 = 40）
	var ctx = pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, 15.0, null, 1, tags_mask, runtime)
	assert_eq(float(ctx.final_damage), 40.0)
	assert_eq(d.stats.get_final(ds.stat_id("SHIELD")), 10.0)
	assert_eq(d.stats.get_final(ds.stat_id("HP")), 100.0)
```

再加一个多段用例（两段 40/40：盾 50 -> 10 -> 0 且 HP 扣 30）。

- [ ] **Step 2: DamagePipeline APPLY 阶段实现护盾吸收**

在 `damage_pipeline.gd` apply 处：
```gdscript
var sid_shield := ds.stat_id("SHIELD")
if sid_shield >= 0:
	var shield := defender.get_final(sid_shield)
	if shield > 0.0 and ctx.final_damage > 0.0:
		var absorb := min(shield, ctx.final_damage)
		defender.add_base(sid_shield, -absorb)
		ctx.final_damage -= absorb
```
然后再扣 HP（剩余伤害）。

- [ ] **Step 3: 跑测试并修到 PASS**
- [ ] **Step 4: 提交**

---

## Task 5：TDD 3/4 —— 减伤（DMG_REDUCE）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_damage_reduction.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`

- [ ] **Step 1: 写 failing test（-20% 后再走护盾/HP）**

示例断言：raw 50 -> reduce 40（然后护盾/HP）。

- [ ] **Step 2: resolve 后 apply 前应用减伤**

```gdscript
var sid_reduce := ds.stat_id("DMG_REDUCE")
if sid_reduce >= 0:
	var r := clamp(defender.get_final(sid_reduce), 0.0, 0.95)
	ctx.final_damage = ctx.final_damage * (1.0 - r)
```

- [ ] **Step 3: 提交**

---

## Task 6：TDD 4/4 —— 命中/暴击（确定性 RNG）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_hit_and_crit_deterministic.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/replay.gd`

- [ ] **Step 1: 写 failing tests（必命中/必未命中/必暴击）**

关键断言：
- miss：`ctx.hit == false` 且 `final_damage == 0`，且不消耗护盾/不扣 HP
- crit：`ctx.crit == true` 且 `final_damage == raw*(1+CRIT_DMG)`

- [ ] **Step 2: 在 resolve 前做命中判定（稳定 seed）**

实现一个内部函数（写在 pipeline 里，带注释）：
```gdscript
func _roll01(seed: int) -> float:
	var x := seed & 0xffffffff
	x ^= (x << 13) & 0xffffffff
	x ^= (x >> 17) & 0xffffffff
	x ^= (x << 5) & 0xffffffff
	return float(x & 0x00ffffff) / float(0x01000000)
```
seed 组合：
`seed = turn_index*... ^ attacker_id*... ^ defender_id*... ^ 0xA5A5A5A5`

- [ ] **Step 3: 命中后再做暴击判定**
- [ ] **Step 4: Replay.DamageTrace 增加 hit/crit 字段并记录**
- [ ] **Step 5: 提交**

---

## Task 7（可选项）：多段攻击每段 AFTER_DEAL 附加 DOT + TurnEnd tick 验证

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_multihit_each_hit_applies_dot.gd`

- [ ] **Step 1: 写用例**
场景：
- attacker 身上有 `buff_on_hit_apply_dot`（AFTER_DEAL -> APPLY_BUFF -> DOT）
- 对 defender 做 3 段攻击（12/14/18）
- 断言：攻击结束后 defender 身上 DOT 实例数 == 3（来源同一 attacker，但每段都施加一次，属于多实例）
- 执行一次 TurnEnd：
  - 断言本次 tick 产生 3 条 DotTrace（source_entity_id 都是 attacker）

- [ ] **Step 2: 如出现“每段未触发”问题，修正 tags_mask/filters 或 runtime 注入**
- [ ] **Step 3: 提交**

---

## Self-Review（执行前检查）

- [ ] 本计划无 TBD/TODO/“适当处理”等占位语句
- [ ] 每个新增机制都有至少 1 个 failing test + 通过标准
- [ ] 运行时修改仍遵守 StatCache + EventIndex 的热路径约束

