# GUT Testing Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 GUT（Godot Unit Test）以 vendor 方式引入 `res://addons/gut/`，并为 OmniBuff 增加至少 3 个自动化用例（多段攻击/防守DEF Buff/DOT多来源），支持 headless 命令行运行并用退出码表示 pass/fail。

**Architecture:** 使用 GUT 的 `extends GutTest` + `assert_*` 断言体系；测试通过 helper 直接构造 `StatsComponent/BuffCore/DamagePipeline/TurnComponent`，走真实数据集 `manifest_loader.load_dataset_full` 与编译链路；多段攻击与 DOT tick 通过 “trace range” 确认每段执行与来源归因。

**Tech Stack:** Godot 4.x + GDScript + GUT（vendor: `res://addons/gut/`）+ headless CLI（`gut_cmdln.gd`）。

---

## 0) 文件结构（将创建/修改哪些文件）

**第三方库：**
- Create (vendor): `godot-buff/addons/gut/**`（从 bitwes/Gut 拷贝 `addons/gut` 子目录）

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/helpers/test_dataset.gd`
- Create: `godot-buff/addons/omnibuff/tests/helpers/test_battle.gd`
- Create: `godot-buff/addons/omnibuff/tests/test_multihit_attack.gd`
- Create: `godot-buff/addons/omnibuff/tests/test_def_buff_reduces_damage.gd`
- Create: `godot-buff/addons/omnibuff/tests/test_dot_multi_source_trace.gd`
- Optional Create: `godot-buff/.gutconfig.json`（可选，若想固定参数）

---

## Task 1：引入 GUT（vendor 到 addons/gut）

**Files:**
- Create: `godot-buff/addons/gut/**`

- [ ] **Step 1: 下载 GUT 源码到临时目录**

Run:
```bash
rm -rf /tmp/gut && git clone --depth 1 https://github.com/bitwes/Gut.git /tmp/gut
```
Expected：`/tmp/gut/addons/gut` 存在。

- [ ] **Step 2: 拷贝 addons/gut 到项目**

Run:
```bash
rm -rf godot-buff/addons/gut
cp -R /tmp/gut/addons/gut godot-buff/addons/gut
```
Expected：项目中出现 `godot-buff/addons/gut/plugin.cfg`、`gut_cmdln.gd` 等文件。

- [ ] **Step 3: 提交 vendor 代码**

Run:
```bash
git add godot-buff/addons/gut
git commit -m "chore(test): vendor GUT into addons/gut"
```

---

## Task 2：创建测试 helper（加载 dataset + 构造 battle runtime）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/helpers/test_dataset.gd`
- Create: `godot-buff/addons/omnibuff/tests/helpers/test_battle.gd`

- [ ] **Step 1: 创建 test_dataset.gd（加载 manifest + compile dataset）**

```gdscript
class_name OmniTestDataset
extends RefCounted

## 测试 helper：统一加载 base_demo 数据集，并返回 enums_rt + compiled dataset
##
## 注意：测试应走真实链路 `load_dataset_full`，以覆盖 validators + manifest.files[] 解析。

static func load_base_demo(strict: bool = true) -> Dictionary:
	var result := OmniManifestLoader.load_dataset_full("res://data/base_demo/manifest.json", strict)
	return {
		"result": result,
		"enums_rt": OmniEnumsRuntime.from_enums_json(result.enums),
		"ds": OmniDatasetCompiler.compile(result.manifest, OmniEnumsRuntime.from_enums_json(result.enums), result.sources)
	}
```

- [ ] **Step 2: 创建 test_battle.gd（构造 stats/buff/runtime dict）**

```gdscript
class_name OmniTestBattle
extends RefCounted

## 测试 helper：构造最小 battle runtime 字典供 APPLY_BUFF/CHANCE_APPLY_BUFF 使用
## runtime = { "stats_by_entity": {eid: OmniStatsComponent}, "buff_by_entity": {eid: OmniBuffCore} }

static func make_entity(eid: int, ds: OmniCompiledDataset, enums_rt: OmniEnumsRuntime) -> Dictionary:
	var stats := OmniStatsComponent.new(eid, ds)
	var buffs := OmniBuffCore.new(ds, enums_rt)
	return {"eid": eid, "stats": stats, "buffs": buffs}

static func make_runtime(entities: Array) -> Dictionary:
	var stats_by := {}
	var buff_by := {}
	for e in entities:
		stats_by[int(e.eid)] = e.stats
		buff_by[int(e.eid)] = e.buffs
	return {"stats_by_entity": stats_by, "buff_by_entity": buff_by}
```

- [ ] **Step 3: 提交 helper**

```bash
git add godot-buff/addons/omnibuff/tests/helpers
git commit -m "test: add omnibuff GUT helpers (dataset/battle)"
```

---

## Task 3：用例 1（多段攻击递增，避免串段）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/test_multihit_attack.gd`

- [ ] **Step 1: 编写测试**

```gdscript
extends GutTest

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")

func test_multihit_damage_is_increasing_and_hp_matches():
	var loaded := OmniTestDataset.load_base_demo(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	# attacker: ATK=10 + equip(20) => 30
	var a := OmniTestBattle.make_entity(1001, ds, enums_rt)
	a.buffs.apply_buff(a.stats, "buff_equip_weapon_001", 1001)

	# defender: DEF default=5, HP default=100
	var d := OmniTestBattle.make_entity(1002, ds, enums_rt)
	var runtime := OmniTestBattle.make_runtime([a, d])
	var tags_mask := enums_rt.tag_mask(["BUFF"])

	var base_hits := [12.0, 14.0, 18.0]
	var finals := []
	for i in range(base_hits.size()):
		var ctx := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, float(base_hits[i]), replay, 10 + i, tags_mask, runtime)
		finals.append(float(ctx.final_damage))

	# 断言：三段递增（避免“第二段被当成第一段”）
	assert_gt(finals[1], finals[0], "hit2 should be > hit1")
	assert_gt(finals[2], finals[1], "hit3 should be > hit2")

	# 数值断言：final = base + ATK - DEF = base + 25 => 37/39/43，总伤害=119，HP= -19（可<0）
	assert_eq(finals[0], 37.0)
	assert_eq(finals[1], 39.0)
	assert_eq(finals[2], 43.0)
	assert_eq(d.stats.get_final(ds.stat_id("HP")), 100.0 - (37.0 + 39.0 + 43.0))
```

- [ ] **Step 2: 提交**

```bash
git add godot-buff/addons/omnibuff/tests/test_multihit_attack.gd
git commit -m "test: add multihit attack assertions"
```

---

## Task 4：用例 2（防守方 DEF Buff 降低伤害）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/test_def_buff_reduces_damage.gd`

- [ ] **Step 1: 编写测试**

```gdscript
extends GutTest

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")

func test_def_buff_reduces_each_hit_damage():
	var loaded := OmniTestDataset.load_base_demo(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	var a := OmniTestBattle.make_entity(2001, ds, enums_rt)
	a.buffs.apply_buff(a.stats, "buff_equip_weapon_001", 2001)

	# defender with DEF+20 (total DEF=25)
	var d := OmniTestBattle.make_entity(2002, ds, enums_rt)
	d.buffs.apply_buff(d.stats, "buff_def_up_20_3t", 2002)

	var runtime := OmniTestBattle.make_runtime([a, d])
	var tags_mask := enums_rt.tag_mask(["BUFF"])
	var base_hits := [12.0, 14.0, 18.0]

	var finals := []
	for i in range(base_hits.size()):
		var ctx := pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, float(base_hits[i]), replay, 20 + i, tags_mask, runtime)
		finals.append(float(ctx.final_damage))

	# final = base + ATK - DEF = base + 5 => 17/19/23
	assert_eq(finals[0], 17.0)
	assert_eq(finals[1], 19.0)
	assert_eq(finals[2], 23.0)
```

- [ ] **Step 2: 提交**

```bash
git add godot-buff/addons/omnibuff/tests/test_def_buff_reduces_damage.gd
git commit -m "test: add defender DEF buff assertions"
```

---

## Task 5：用例 3（DOT 多来源独立实例 + trace 验证）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/test_dot_multi_source_trace.gd`

- [ ] **Step 1: 编写测试**

```gdscript
extends GutTest

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")

func test_dot_multi_source_produces_two_traces_per_tick():
	var loaded := OmniTestDataset.load_base_demo(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	var src_a := OmniTestBattle.make_entity(3001, ds, enums_rt)
	src_a.buffs.apply_buff(src_a.stats, "buff_equip_weapon_001", 3001) # ATK=30

	var src_b := OmniTestBattle.make_entity(3002, ds, enums_rt)
	src_b.buffs.apply_buff(src_b.stats, "buff_equip_weapon_001", 3002) # ATK=30
	src_b.stats.add_base(ds.stat_id("ATK"), 20.0) # ATK=50

	var tgt := OmniTestBattle.make_entity(3003, ds, enums_rt)
	# 目标身上的 BuffCore 挂 DOT（按来源独立实例）
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", 3001)
	tgt.buffs.apply_buff(tgt.stats, "buff_dot_fire_3t", 3002)

	var runtime := OmniTestBattle.make_runtime([src_a, src_b, tgt])
	var turn := OmniTurnComponent.new()
	var ids := PackedInt32Array([3001, 3002, 3003])
	ids.sort()

	var before := replay.dot_traces.size()
	turn.on_turn_end(ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
	var after := replay.dot_traces.size()

	# 断言：一次 tick 产生 2 条 DotTrace（两来源）
	assert_eq(after - before, 2, "one tick should create 2 dot traces for 2 sources")

	var t1 = replay.dot_traces[before]
	var t2 = replay.dot_traces[before + 1]
	var srcs := [int(t1.source_entity_id), int(t2.source_entity_id)]
	srcs.sort()
	assert_eq(srcs, [3001, 3002])
```

- [ ] **Step 2: 提交**

```bash
git add godot-buff/addons/omnibuff/tests/test_dot_multi_source_trace.gd
git commit -m "test: add DOT multi-source trace assertions"
```

---

## Task 6：本地运行指南（headless）+ 验证

**Files:**
- Optional Create: `.gutconfig.json`
- (Docs only) README 可后续加；本计划先提供命令行。

- [ ] **Step 1: 生成导入缓存（第一次/CI必需）**

Run:
```bash
godot --headless --import --quit
```
Expected：退出码 0/正常退出；会生成 `.godot/` 导入缓存。

- [ ] **Step 2: 运行 GUT tests（目录模式）**

Run:
```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://addons/omnibuff/tests -gexit
```
Expected：控制台输出包含各测试脚本与 PASS/FAIL；若有失败则退出码非 0。

- [ ] **Step 3: 提交（若新增了配置/脚本）**

```bash
git add godot-buff/addons/omnibuff/tests
git commit -m "test: enable headless GUT runs for omnibuff"
```

