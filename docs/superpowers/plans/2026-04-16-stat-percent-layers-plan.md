# Stat Percent Layers (N-stage Multipliers) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Stats 系统支持“分段乘法”的百分比层（percent layers），实现 `(base+flat)*Π(1+pct_layer)`，并保持旧数据兼容（默认 layer=0）。

**Architecture:** 先加 failing test（按用户例子算 ATK=34.5），再扩展 modifier 数据结构（layer 字段）+ StatsCore 计算逻辑 + validators 允许/校验 layer，最后跑全量测试确保兼容。

**Tech Stack:** Godot 4.7 + GDScript + GUT + JSON 数据。

---

## 0) 文件清单

**运行时：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`（OmniModifierRef 增字段 + 注入 layer）

**校验：**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`（允许 effect.layer + 校验）

**测试数据：**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`（新增 3 个测试专用 buff）

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_stat_percent_layers.gd`

---

## Task 1：新增 failing test（两段乘法示例 = 34.5）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_stat_percent_layers.gd`

- [ ] **Step 1: 写测试**

```gdscript
extends GutTest

const TestDataset = preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle = preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_percent_layers_apply_in_order() -> void:
	var loaded = TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var e = TestBattle.make_entity(9801, ds, enums_rt)
	var atk_id: int = int(ds.stat_id("ATK"))
	assert_true(atk_id >= 0)

	# baseline: 10
	assert_true(is_equal_approx(float(e.stats.get_final(atk_id)), 10.0))

	# flat: +10 (weapon), +5 (passive)
	e.buffs.apply_buff(e.stats, "buff_test_weapon_atk_flat_10", 9801)
	e.buffs.apply_buff(e.stats, "buff_test_passive_atk_flat_5", 9801)

	# pct layer0: +5% (trinket A), +10% (trinket B)
	e.buffs.apply_buff(e.stats, "buff_atk_pct_5", 9801) # existing layer default=0
	e.buffs.apply_buff(e.stats, "buff_test_trinket_atk_pct_10", 9801)

	# pct layer1: total atk +20% (treasure)
	e.buffs.apply_buff(e.stats, "buff_test_total_atk_pct_20", 9801)

	var expected: float = (10.0 + 10.0 + 5.0) * (1.0 + 0.05 + 0.10) * (1.0 + 0.20)
	assert_true(is_equal_approx(float(e.stats.get_final(atk_id)), expected), "expected=%s got=%s" % [expected, e.stats.get_final(atk_id)])
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_stat_percent_layers.gd
git -C godot-buff commit -m "test(stats): add percent-layers regression coverage"
```

---

## Task 2：新增测试专用 buff（flat + pct10 + total pct20(layer=1)）

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 添加 3 个 buff**

追加：
```json
{
  "id": "buff_test_weapon_atk_flat_10",
  "name": "测试：武器 ATK +10（flat）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [{ "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 10.0 }],
  "triggers": []
},
{
  "id": "buff_test_passive_atk_flat_5",
  "name": "测试：被动 ATK +5（flat）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [{ "kind": "modifier", "stat": "ATK", "op": "ADD", "phase": "FLAT", "priority": 100, "value": 5.0 }],
  "triggers": []
},
{
  "id": "buff_test_trinket_atk_pct_10",
  "name": "测试：饰品 ATK +10%（pct layer0）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [{ "kind": "modifier", "stat": "ATK", "op": "MUL", "phase": "PERCENT", "priority": 110, "value": 0.10, "layer": 0 }],
  "triggers": []
},
{
  "id": "buff_test_total_atk_pct_20",
  "name": "测试：总攻击力 +20%（pct layer1）",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [{ "kind": "modifier", "stat": "ATK", "op": "MUL", "phase": "PERCENT", "priority": 120, "value": 0.20, "layer": 1 }],
  "triggers": []
}
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add data/rpg_tests/buff_defs.json
git -C godot-buff commit -m "test(data): add percent-layer fixture buffs"
```

---

## Task 3：实现 layer 字段注入（BuffCore → StatsCore）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: OmniModifierRef 增加字段**

```gdscript
var layer: int = 0
```

- [ ] **Step 2: 注入 modifier 时读取 effect.layer（缺省=0）**

在创建 `mr` 的位置加：
```gdscript
mr.layer = int(e.get("layer", 0))
```

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff commit -m "feat(stats): add percent layer field to modifiers"
```

---

## Task 4：StatsCore 支持分段乘法（按 layer 升序）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/stats_core.gd`

- [ ] **Step 1: 把 pct 单桶改为 pct_by_layer**

将：
```gdscript
var pct := 0.0
...
elif op == "MUL" and ph == "PERCENT":
    pct += val
...
var v := (base + flat) * (1.0 + pct)
```

改为（示例实现）：
```gdscript
var pct_by_layer: Dictionary = {} # int -> float
...
elif op == "MUL" and ph == "PERCENT":
    var layer: int = int(m.layer) if m.has_method("get") else int(m.layer) # 仅示意，实际直接读字段
    if not pct_by_layer.has(layer):
        pct_by_layer[layer] = 0.0
    pct_by_layer[layer] = float(pct_by_layer[layer]) + val

var v := (base + flat)
var layers: Array = pct_by_layer.keys()
layers.sort()
for l in layers:
    v *= (1.0 + float(pct_by_layer[l]))
```

（注意：保持 override/final_add/clamp 顺序不变）

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/stats_core.gd
git -C godot-buff commit -m "feat(stats): support percent layers for multi-stage multipliers"
```

---

## Task 5：validators 允许并校验 effect.layer

**Files:**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`

- [ ] **Step 1: allowed_effect 增加 layer**
把 `allowed_effect` 加上 `"layer": true`。

- [ ] **Step 2: 校验**
当 `op=="MUL" && phase=="PERCENT"`：
- 若存在 `layer`：必须是 int 且 `>=0`

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add addons/omnibuff/config/compiler/validators.gd
git -C godot-buff commit -m "feat(validate): allow and validate percent modifier layer"
```

