# OmniBuff Phase 2 Numerics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 Phase 2 数值表达升级：① stat_defs 派生/转换属性（derived）；② 明确 bucket/phase 管线并保持旧语义；③ 曲线（curve）最小集（DR/EXP/LOG）；④ validators + tests 完整覆盖。

**Architecture:** 扩展 `stat_defs.json` 协议；在 `DatasetCompiler` 把派生规则编译为依赖图与拓扑序写入 `OmniCompiledDataset`；`OmniStatsCore` 增加 `computed_base` 并实现 dirty 传播与派生重算；曲线在 POST_FINAL 阶段应用；同时提供 `get_breakdown()` 产出 base/bonus/final 给属性面板 UI；最后以 GUT tests 回归与新增覆盖验收。

**Tech Stack:** Godot 4.x / GDScript / GUT / OmniBuff runtime。

---

## 0) 文件清单（目标落点）

**Schema / Validate**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Modify: `godot-buff/data/base_demo/stat_defs.json`
- Modify: `godot-buff/data/rpg_tests/stat_defs.json`

**Compiler / Dataset**
- Modify: `godot-buff/addons/omnibuff/config/compiler/dataset_compiler.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/compiled_data.gd`

**Runtime**
- Modify: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/components/stats_component.gd`

**Tests**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_phase2_numerics_derived_and_buckets.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_phase2_numerics_derived_and_buckets.gd.uid`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_phase2_numerics_curves.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_phase2_numerics_curves.gd.uid`

---

## Task 1：validators 支持 stat_defs 的 derived/curve（RED）

**Files:**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`

- [ ] **Step 1: 允许 stat_defs 新字段**

在 `_validate_stat_defs` 内的 `allowed` 集合加入：

```gdscript
var allowed := {"id": true, "default": true, "min": true, "max": true, "clamp": true, "derived": true, "curve": true}
```

并新增子结构字段白名单：

```gdscript
var allowed_derived := {"type": true, "from": true, "ratio": true, "expr": true, "inputs": true, "round": true}
var allowed_curve := {"type": true, "k": true, "a": true, "b": true, "c": true, "d": true, "apply_at": true}
```

- [ ] **Step 2: 派生/曲线校验**

加入校验逻辑（伪代码可直接粘贴实现）：

```gdscript
if s.has("derived"):
	var d: Dictionary = s.get("derived", {})
	_unknown_fields(file, p + ".derived", id, d, allowed_derived, strict, issues)
	var dt := String(d.get("type", "")).to_upper()
	if dt != "LINEAR" and dt != "EXPR":
		_add_issue(issues, error(file, "path=" + p + ".derived.type", id, "derived.type must be LINEAR/EXPR"), strict)
	if dt == "LINEAR":
		var from := String(d.get("from", ""))
		if from == "":
			_add_issue(issues, error(file, "path=" + p + ".derived.from", id, "LINEAR requires from"), strict)
		var ratio_v: Variant = d.get("ratio", null)
		if ratio_v == null:
			_add_issue(issues, error(file, "path=" + p + ".derived.ratio", id, "LINEAR requires ratio"), strict)
	if dt == "EXPR":
		var ex := String(d.get("expr", "")).strip_edges()
		if ex == "" or ex.length() > 256:
			_add_issue(issues, error(file, "path=" + p + ".derived.expr", id, "expr must be non-empty and <=256"), strict)
		var inputs: Array = d.get("inputs", [])
		if inputs.is_empty():
			_add_issue(issues, error(file, "path=" + p + ".derived.inputs", id, "EXPR requires non-empty inputs[]"), strict)
```

对于 `inputs[]` 的 stat id 存在性校验：复用 `_validate_stat_defs` 已构建的 `seen` stat id 表。

曲线：

```gdscript
if s.has("curve"):
	var c: Dictionary = s.get("curve", {})
	_unknown_fields(file, p + ".curve", id, c, allowed_curve, strict, issues)
	var ct := String(c.get("type", "")).to_upper()
	var ok := (ct == "" or ct == "NONE" or ct == "DR_SOFTCAP" or ct == "EXP" or ct == "LOG")
	if not ok:
		_add_issue(issues, error(file, "path=" + p + ".curve.type", id, "curve.type must be NONE/DR_SOFTCAP/EXP/LOG"), strict)
	if ct == "DR_SOFTCAP":
		var k := float(c.get("k", 0.0))
		if k <= 0.0:
			_add_issue(issues, error(file, "path=" + p + ".curve.k", id, "DR_SOFTCAP requires k>0"), strict)
```

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/config/compiler/validators.gd
git -C godot-buff commit -m "feat(validate): allow stat derived/curve definitions"
```

---

## Task 2：扩展 OmniCompiledDataset（派生图编译产物）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/compiled_data.gd`

- [ ] **Step 1: 增加字段**

```gdscript
var derived_defs_by_stat: Array[Dictionary] = []
var derived_inputs_by_stat: Array = [] # Array[PackedInt32Array]
var derived_dependents_by_stat: Array = [] # Array[PackedInt32Array]
var derived_topo_order: PackedInt32Array = PackedInt32Array()
```

- [ ] **Step 2: 在 DatasetCompiler.compile 初始化这些数组长度=stat_count**
（见 Task 3 的 Step 2）

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/compiled_data.gd
git -C godot-buff commit -m "feat(dataset): add derived graph fields"
```

---

## Task 3：DatasetCompiler 编译派生依赖图（含循环检测）

**Files:**
- Modify: `godot-buff/addons/omnibuff/config/compiler/dataset_compiler.gd`

- [ ] **Step 1: 解析 derived 并生成输入边**

在 stats 构建完成后（`ds.stat_defs.append(s)` 循环之后）追加：

```gdscript
var n := ds.stat_defs.size()
ds.derived_defs_by_stat.resize(n)
ds.derived_inputs_by_stat.resize(n)
ds.derived_dependents_by_stat.resize(n)
for i in range(n):
	ds.derived_defs_by_stat[i] = {}
	ds.derived_inputs_by_stat[i] = PackedInt32Array()
	ds.derived_dependents_by_stat[i] = PackedInt32Array()

for sid in range(n):
	var sdef: Dictionary = ds.stat_defs[sid]
	if not sdef.has("derived"):
		continue
	var d: Dictionary = sdef.get("derived", {})
	ds.derived_defs_by_stat[sid] = d
	var inputs := PackedInt32Array()
	var dt := String(d.get("type", "")).to_upper()
	if dt == "LINEAR":
		var from := int(ds.stat_id(String(d.get("from", ""))))
		if from >= 0:
			inputs.append(from)
	elif dt == "EXPR":
		for name in d.get("inputs", []):
			var dep := int(ds.stat_id(String(name)))
			if dep >= 0:
				inputs.append(dep)
	ds.derived_inputs_by_stat[sid] = inputs
	for dep in inputs:
		var arr: PackedInt32Array = ds.derived_dependents_by_stat[int(dep)]
		arr.append(int(sid))
		ds.derived_dependents_by_stat[int(dep)] = arr
```

- [ ] **Step 2: 拓扑排序 + 循环检测**

实现一个最小 Kahn：

```gdscript
var indeg := PackedInt32Array()
indeg.resize(n)
for sid in range(n):
	indeg[sid] = 0
for sid in range(n):
	for dep in ds.derived_inputs_by_stat[sid]:
		indeg[sid] += 1

var q: Array[int] = []
for sid in range(n):
	if indeg[sid] == 0:
		q.append(sid)

var order := PackedInt32Array()
while not q.is_empty():
	var cur := int(q.pop_front())
	order.append(cur)
	for nxt in ds.derived_dependents_by_stat[cur]:
		indeg[int(nxt)] -= 1
		if indeg[int(nxt)] == 0:
			q.append(int(nxt))

if order.size() != n:
	# 说明存在环（或孤立 indeg 无法归零），这里先用最小策略：把 topo_order 置空，交给 validators 阻断
	# 更严格：在 validate 阶段直接 error；Phase2 实现时可把 cycle 信息返回到 issues
	order = PackedInt32Array()
ds.derived_topo_order = order
```

> 注意：这里的循环检测最好最终由 validators 阻断（返回 Issue），plan 的后续任务会在 validators 加入“编译失败提示”。

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/config/compiler/dataset_compiler.gd
git -C godot-buff commit -m "feat(compile): build derived stat graph"
```

---

## Task 4：StatsCore：computed_base + dirty 传播 + buckets 重算

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`

- [ ] **Step 1: 增加 computed_base 并初始化**

```gdscript
var computed_base: PackedFloat32Array
```

在 `_init` 里：

```gdscript
computed_base = PackedFloat32Array()
computed_base.resize(n)
for i in range(n):
	computed_base[i] = 0.0
```

- [ ] **Step 2: mark_dirty 做依赖传播（最小版）**

```gdscript
func mark_dirty(stat_id: int) -> void:
	dirty[stat_id] = 1
	if ds.derived_dependents_by_stat.size() == 0:
		return
	var deps: PackedInt32Array = ds.derived_dependents_by_stat[stat_id]
	for sid in deps:
		dirty[int(sid)] = 1
```

- [ ] **Step 3: 派生计算（最小支持 LINEAR）**

新增：

```gdscript
func _recompute_computed_base_for(stat_id: int) -> void:
	if ds.derived_defs_by_stat.size() == 0:
		computed_base[stat_id] = 0.0
		return
	var d: Dictionary = ds.derived_defs_by_stat[stat_id]
	if d.is_empty():
		computed_base[stat_id] = 0.0
		return
	var dt := String(d.get("type", "")).to_upper()
	if dt == "LINEAR":
		var from_id := int(ds.stat_id(String(d.get("from", ""))))
		var ratio := float(d.get("ratio", 0.0))
		if from_id >= 0 and ratio != 0.0:
			computed_base[stat_id] = get_final(from_id) * ratio
			return
	computed_base[stat_id] = 0.0
```

> EXPR + curve 会在后续任务补齐；此任务先把机制跑通。

- [ ] **Step 4: recompute(stat_id) 使用 base_values + computed_base**

把：

```gdscript
var base := base_values[stat_id]
```

改为：

```gdscript
_recompute_computed_base_for(stat_id)
var base := base_values[stat_id] + computed_base[stat_id]
```

并保持现有 flat/pct/override/final_add/clamp 顺序不变（先保证兼容）。

- [ ] **Step 5: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/stats_core.gd
git -C godot-buff commit -m "feat(stats): computed_base and derived dirty propagation"
```

---

## Task 4.5：StatsComponent/StatsCore 提供 base/bonus/final（属性面板）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/components/stats_component.gd`

- [ ] **Step 1: StatsCore 增加 get_breakdown(stat_id)**

在 `OmniStatsCore` 增加：

```gdscript
func get_breakdown(stat_id: int) -> Dictionary:
	# 确保 final 已刷新
	var final_v := get_final(stat_id)
	# base = base_values + computed_base（computed_base 由 Phase2 derived 维护）
	var base_v := float(base_values[stat_id])
	if computed_base.size() > 0:
		base_v += float(computed_base[stat_id])
	return {
		"base": base_v,
		"final": final_v,
		"bonus": final_v - base_v
	}
```

> 备注：更细的 flat/pct/override/final_add/curve/clamp breakdown 可在后续迭代补齐；本轮只保证 UI 需要的 base/bonus/final。

- [ ] **Step 2: StatsComponent 增加 get_breakdown(stat_id)**

```gdscript
func get_breakdown(stat_id: int) -> Dictionary:
	return core.get_breakdown(stat_id)
```

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/stats_core.gd addons/omnibuff/runtime/components/stats_component.gd
git -C godot-buff commit -m "feat(stats): expose base/bonus/final breakdown"
```

---

## Task 5：曲线（curve）最小集实现（DR/EXP/LOG）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`

- [ ] **Step 1: 添加曲线函数**

```gdscript
func _apply_curve(stat_id: int, v: float) -> float:
	var def: Dictionary = ds.stat_defs[stat_id]
	if not def.has("curve"):
		return v
	var c: Dictionary = def.get("curve", {})
	var ct := String(c.get("type", "")).to_upper()
	if ct == "" or ct == "NONE":
		return v
	if ct == "DR_SOFTCAP":
		var k := float(c.get("k", 0.0))
		if k <= 0.0:
			return v
		return v / (v + k)
	if ct == "EXP":
		var a := float(c.get("a", 1.0))
		var b := float(c.get("b", 1.0))
		var cc := float(c.get("c", 0.0))
		return a * exp(b * v) + cc
	if ct == "LOG":
		var a2 := float(c.get("a", 1.0))
		var b2 := float(c.get("b", 1.0))
		var c2 := float(c.get("c", 0.0))
		var d2 := float(c.get("d", 0.0))
		return a2 * log(b2 * v + c2) + d2
	return v
```

- [ ] **Step 2: 在 clamp 前应用**

在 `recompute` 末尾 clamp 前加入：

```gdscript
v = _apply_curve(stat_id, v)
```

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/stats_core.gd
git -C godot-buff commit -m "feat(stats): support curves on final value"
```

---

## Task 6：新增 Phase2 tests（Derived + Buckets + Curves）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_phase2_numerics_derived_and_buckets.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_phase2_numerics_curves.gd`

- [ ] **Step 1: Derived 线性测试**

`test_phase2_numerics_derived_and_buckets.gd`：

```gdscript
extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_phase2_linear_derived_str_to_hp() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e := TestBattle.make_entity(12001, ds, enums_rt)
	var hp := int(ds.stat_id("HP"))
	var str := int(ds.stat_id("STR"))
	assert_true(hp >= 0 and str >= 0)

	# 约定：rpg_tests/stat_defs.json 中 HP 配置 derived LINEAR from STR ratio=20
	e["stats"].add_base(str, 5.0) # STR +=5
	var hp2 := float(e["stats"].get_final(hp))
	assert_true(hp2 > 100.0, "HP should increase after STR changes via derived")

	var bd: Dictionary = e["stats"].get_breakdown(hp)
	assert_true(bd.has("base") and bd.has("bonus") and bd.has("final"))
	assert_true(float(bd["final"]) == hp2)
	assert_true(float(bd["bonus"]) == float(bd["final"]) - float(bd["base"]))
```

- [ ] **Step 2: Curves 测试**

`test_phase2_numerics_curves.gd`：

```gdscript
extends GutTest

const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_phase2_curve_dr_softcap_is_monotonic() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var ds: OmniCompiledDataset = loaded.ds
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var e := TestBattle.make_entity(12002, ds, enums_rt)
	var sid := int(ds.stat_id("DMG_REDUCE"))
	assert_true(sid >= 0)

	e["stats"].add_base(sid, 10.0)
	var v1 := float(e["stats"].get_final(sid))
	e["stats"].add_base(sid, 10.0)
	var v2 := float(e["stats"].get_final(sid))
	assert_true(v2 >= v1, "DR curve should be monotonic non-decreasing")
```

- [ ] **Step 3: 提交 tests**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_phase2_numerics_derived_and_buckets.gd addons/omnibuff/tests/rpg/test_phase2_numerics_curves.gd
git -C godot-buff commit -m "test(phase2): add derived and curve coverage"
```

---

## Task 7：更新 rpg_tests/stat_defs.json（提供可验证数据）

**Files:**
- Modify: `godot-buff/data/rpg_tests/stat_defs.json`

- [ ] **Step 1: 为 HP 增加 derived（LINEAR from STR）**

```jsonc
{ "id": "HP", "default": 100.0, "min": 0.0, "max": 99999.0, "clamp": true,
  "derived": { "type": "LINEAR", "from": "STR", "ratio": 20.0, "round": "NONE" }
}
```

- [ ] **Step 2: 为 DMG_REDUCE 增加 curve（DR_SOFTCAP）**
若 rpg_tests 当前没有 DMG_REDUCE，先在该文件新增该 stat。

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add data/rpg_tests/stat_defs.json
git -C godot-buff commit -m "testdata(phase2): add derived and curve stat defs"
```

---

## 最终验证（本地执行）

- [ ] 在 Godot 编辑器里运行 GUT：确保新增 Phase2 tests 通过
- [ ] 回归 `test_stat_percent_layers.gd` / `test_stat_clamp.gd` 等既有 tests 仍通过
