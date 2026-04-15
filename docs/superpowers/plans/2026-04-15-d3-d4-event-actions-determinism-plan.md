# D3/D4 (Event Actions + Determinism) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补齐 D3/D4 的测试覆盖，使 checklist 中 D3（ADD_BASE_DAMAGE/APPLY_BUFF/CHANCE_APPLY_BUFF）与 D4（概率可复盘）可打勾，并同步更新 done-definition checklist。

**Architecture:** 仅补 fixtures + tests：在 `data/rpg_tests/buff_defs.json` 增加 ADD_BASE_DAMAGE 与 CHANCE_APPLY_BUFF 的测试触发 buff；新增 2~3 个 GUT 测试文件验证 action 生效与 deterministic（同输入同输出）；最后更新 checklist 勾选 D3/D4。

**Tech Stack:** Godot 4.7 + GDScript + GUT。

---

## 0) 文件清单

**数据：**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_add_base_damage.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_chance_apply_buff_determinism.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_hit_crit_determinism.gd`

**文档：**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

---

## Task 1：补齐 rpg_tests fixtures（ADD_BASE_DAMAGE / CHANCE_APPLY_BUFF）

**Files:**
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 新增 ADD_BASE_DAMAGE fixture**

```json
{
  "id": "buff_event_add_base_damage_5",
  "name": "D3测试：事件增加基础伤害+5",
  "buff_type": "EXPLICIT",
  "tags": ["BUFF"],
  "duration": { "type": "PERMANENT" },
  "stack": { "mode": "REPLACE", "max_stack": 1, "refresh_policy": "NONE", "ownership_mode": "GLOBAL" },
  "effects": [],
  "triggers": [
    {
      "event_type": "DAMAGE",
      "event_phase": "BEFORE_DEAL",
      "scope": "SELF",
      "filters": { "tag_mask_any": ["BUFF"], "require_hit": true },
      "action": { "kind": "ADD_BASE_DAMAGE", "value": 5.0 }
    }
  ]
}
```

- [ ] **Step 2: 新增 CHANCE_APPLY_BUFF fixture（chance=0.5）**

```json
{
  "id": "buff_event_chance_apply_dot_50",
  "name": "D3/D4测试：50%概率命中后挂DOT",
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
      "filters": { "tag_mask_any": ["BUFF"], "require_hit": true },
      "action": { "kind": "CHANCE_APPLY_BUFF", "chance": 0.5, "buff_id": "buff_dot_fire_3t" }
    }
  ]
}
```

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add data/rpg_tests/buff_defs.json
git -C godot-buff commit -m "test(data): add D3/D4 event fixtures"
```

---

## Task 2：新增单测（ADD_BASE_DAMAGE）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_add_base_damage.gd`

- [ ] **Step 1: 写 failing test（应在当前实现下通过）**

```gdscript
extends GutTest

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_add_base_damage_increases_final_damage() -> void:
	var loaded := TestDataset.load_rpg_tests(true)
	var enums_rt: OmniEnumsRuntime = loaded.enums_rt
	var ds: OmniCompiledDataset = loaded.ds

	var pipe := OmniDamagePipeline.new()
	var replay := ReplayScript.new()

	var attacker_id := 8101
	var defender_id := 8102
	var attacker := TestBattle.make_entity(attacker_id, ds, enums_rt)
	var defender := TestBattle.make_entity(defender_id, ds, enums_rt)
	var runtime := TestBattle.make_runtime([attacker, defender])

	# 固定命中/暴击，避免随机干扰
	attacker.stats.add_base(ds.stat_id("HIT_RATE"), 1.0 - float(attacker.stats.get_final(ds.stat_id("HIT_RATE"))))
	attacker.stats.add_base(ds.stat_id("CRIT_RATE"), 0.0 - float(attacker.stats.get_final(ds.stat_id("CRIT_RATE"))))
	defender.stats.add_base(ds.stat_id("EVADE"), 0.0 - float(defender.stats.get_final(ds.stat_id("EVADE"))))

	# 让 ATK/DEF 不影响结果
	attacker.stats.add_base(ds.stat_id("ATK"), 0.0 - float(attacker.stats.get_final(ds.stat_id("ATK"))))
	defender.stats.add_base(ds.stat_id("DEF"), 0.0 - float(defender.stats.get_final(ds.stat_id("DEF"))))

	attacker.buffs.apply_buff(attacker.stats, "buff_event_add_base_damage_5", attacker_id)

	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
	var ctx := pipe.deal_damage(attacker.stats, defender.stats, attacker.buffs, defender.buffs, ds, 10.0, replay, 1, tags_mask, runtime)
	assert_true(ctx.hit)
	assert_eq(float(ctx.base_damage), 15.0)
	assert_eq(float(ctx.final_damage), 15.0)
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_event_add_base_damage.gd
git -C godot-buff commit -m "test(d3): add add_base_damage coverage"
```

---

## Task 3：新增单测（CHANCE_APPLY_BUFF 可复盘）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_chance_apply_buff_determinism.gd`

- [ ] **Step 1: 写测试（同输入同输出 + expected 由 seed 计算）**

要点：
- attacker 挂 `buff_event_chance_apply_dot_50`
- 通过 `inst_id` + `_event_seed/_roll01` 计算 expected
- 断言 defender 是否获得 `buff_dot_fire_3t` 与 expected 一致
- 再跑一遍同 turn_index（新 runtime），结果一致

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_event_chance_apply_buff_determinism.gd
git -C godot-buff commit -m "test(d3/d4): add chance_apply_buff determinism coverage"
```

---

## Task 4：新增单测（命中/暴击可复盘）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_hit_crit_determinism.gd`

- [ ] **Step 1: 写测试（同输入同输出）**

用非 0/1 的 HIT_RATE/CRIT_RATE，确保走随机分支，并断言：
- 同 turn_index 连续两次调用结果一致（hit/crit/final_damage）

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_hit_crit_determinism.gd
git -C godot-buff commit -m "test(d4): add hit/crit determinism coverage"
```

---

## Task 5：更新 checklist 勾选 D3/D4

**Files:**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

- [ ] **Step 1: 勾选**
- D3：ADD_BASE_DAMAGE / CHANCE_APPLY_BUFF 用例补齐后，D3 可标记完成
- D4：概率 determinism 用例补齐后，D4 可标记完成

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add docs/superpowers/checklists/omnibuff-done-definition.md
git -C godot-buff commit -m "docs(checklist): mark D3/D4 complete"
```

