# DOT TURN_START Default Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 DOT 结算点从 TURN_END 改为 TURN_START（目标回合开始结算），并同步更新运行时、数据集（base_demo + rpg_tests）、demo 与现有 GUT 用例，保证全套测试通过；随后实现整回合脚本式集成测试（护盾→三连→每段挂DOT→TurnStart结算→驱散→免疫）。

**Architecture:** 在 `BuffCore.on_turn_start()` 实现 DOT tick（与 on_turn_end 共享一套内部函数），`TurnComponent` 增加 `on_turn_start(...)` 并在测试/脚本里按回合调用。数据层将 `duration.tick_phase` 与 `dot.tick_phase` 统一为 `TURN_START`。测试中显式调用 TurnStart 结算，以符合“挂上后到目标回合才掉血”的语义。

**Tech Stack:** Godot 4.7 + GDScript + GUT。

---

## 0) 文件清单

**运行时：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/components/turn_component.gd`

**数据集：**
- Modify: `godot-buff/data/base_demo/buff_defs.json`
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

**测试与 demo：**
- Modify: `godot-buff/addons/omnibuff/demo/demo_runner.gd`（DOT 示例改为 TurnStart）
- Modify: `godot-buff/addons/omnibuff/tests/test_dot_multi_source_trace.gd`
- Modify: `godot-buff/addons/omnibuff/tests/rpg/test_multihit_each_hit_applies_dot.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_full_turn_script_battle.gd`

---

## Task 1：运行时实现 TURN_START DOT tick

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/components/turn_component.gd`

- [ ] **Step 1: 在 BuffCore 中抽取 DOT tick 内部函数**

在 `buff_core.gd` 增加：
```gdscript
func _tick_dots(turn_index: int, tick_phase: String, stats_by_entity: Dictionary, buff_by_entity: Dictionary, pipeline: OmniDamagePipeline, dataset: OmniCompiledDataset, replay: RefCounted) -> void:
    # 从 dots_by_target[owner_entity_id] 取出 dot 列表
    # 仅处理 d.tick_phase == tick_phase
    # 每个 dot：
    #   - 读取 source_stat_value
    #   - 计算 damage
    #   - pipeline.deal_damage_with_tags(...) 或等价路径扣血（注意 tags_mask）
    #   - replay.trace_dot_tick(...)
    #   - remaining_turns -= 1，<=0 则移除
```

- [ ] **Step 2: 实现 on_turn_start 调用 _tick_dots(..., \"TURN_START\", ...)**

```gdscript
func on_turn_start(turn_index: int, stats_by_entity: Dictionary, buff_by_entity: Dictionary, pipeline: OmniDamagePipeline, dataset: OmniCompiledDataset, replay: RefCounted = null) -> void:
    _tick_dots(turn_index, "TURN_START", stats_by_entity, buff_by_entity, pipeline, dataset, replay)
```

- [ ] **Step 3: on_turn_end 改为调用 _tick_dots(..., \"TURN_END\", ...)**

确保旧接口仍可用，但默认数据将切到 TURN_START。

- [ ] **Step 4: TurnComponent 增加 on_turn_start(...)**

在 `turn_component.gd` 增加与 `on_turn_end` 对称的方法：
```gdscript
func on_turn_start(entity_ids: PackedInt32Array, buff_by_entity: Dictionary, stats_by_entity: Dictionary, pipe: OmniDamagePipeline, ds: OmniCompiledDataset, replay: RefCounted = null) -> void:
    for eid in entity_ids:
        var b = buff_by_entity.get(int(eid), null)
        if b != null:
            b.on_turn_start(_turn_index, stats_by_entity, buff_by_entity, pipe, ds, replay)
```

- [ ] **Step 5: 提交**

```bash
git add godot-buff/addons/omnibuff/runtime/core/buff_core.gd godot-buff/addons/omnibuff/runtime/components/turn_component.gd
git commit -m "feat(dot): add TURN_START dot ticking (default)"
```

---

## Task 2：数据集默认切换到 TURN_START

**Files:**
- Modify: `godot-buff/data/base_demo/buff_defs.json`
- Modify: `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 将所有 DOT buff 的 duration.tick_phase 与 dot.tick_phase 改为 TURN_START**

示例：
```json
"duration": { "type": "TURNS", "turns": 3, "tick_phase": "TURN_START" },
"dot": { "tick_phase": "TURN_START", ... }
```

- [ ] **Step 2: 提交**

```bash
git add godot-buff/data/base_demo/buff_defs.json godot-buff/data/rpg_tests/buff_defs.json
git commit -m "chore(data): switch DOT tick_phase to TURN_START"
```

---

## Task 3：同步更新 demo 与现有测试（从 TurnEnd 改为 TurnStart）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/demo_runner.gd`
- Modify: `godot-buff/addons/omnibuff/tests/test_dot_multi_source_trace.gd`
- Modify: `godot-buff/addons/omnibuff/tests/rpg/test_multihit_each_hit_applies_dot.gd`

- [ ] **Step 1: 更新 base_demo DOT 多来源测试**

将 `turn.on_turn_end(...)` 改为 `turn.on_turn_start(...)`，并保持 trace 数量断言不变。

- [ ] **Step 2: 更新 rpg 多段每段挂 DOT 测试**

将 TurnEnd tick 改为 TurnStart tick，并确保：
- 挂 DOT 的回合不会产出 dot trace
- 下一回合开始（TurnStart）产生 dot trace

- [ ] **Step 3: 更新 demo_runner 的 DOT 示例**

将原本的 TurnEnd 结算改为 TurnStart 结算，输出/trace 打印位置同步调整。

- [ ] **Step 4: 提交**

```bash
git add godot-buff/addons/omnibuff/demo/demo_runner.gd godot-buff/addons/omnibuff/tests/test_dot_multi_source_trace.gd godot-buff/addons/omnibuff/tests/rpg/test_multihit_each_hit_applies_dot.gd
git commit -m "test(demo): migrate DOT ticks to TURN_START"
```

---

## Task 4：新增整回合脚本式集成测试（TURN_START 语义）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_full_turn_script_battle.gd`

- [ ] **Step 1: 编写测试骨架（脚本式 helper 函数）**

```gdscript
extends GutTest

const ReplayScript := preload("res://addons/omnibuff/runtime/core/replay.gd")
const TestDataset := preload("res://addons/omnibuff/tests/helpers/test_dataset.gd")
const TestBattle := preload("res://addons/omnibuff/tests/helpers/test_battle.gd")

func test_full_turn_script_battle_dot_turn_start_dispel_and_immunity():
    var loaded := TestDataset.load_rpg_tests(true)
    var ds = loaded.ds
    var enums_rt = loaded.enums_rt
    var pipe := OmniDamagePipeline.new()
    var replay := ReplayScript.new()
    var turn := OmniTurnComponent.new()

    var attacker_id := 9001
    var defender_id := 9002
    var a := TestBattle.make_entity(attacker_id, ds, enums_rt)
    var d := TestBattle.make_entity(defender_id, ds, enums_rt)
    var runtime := TestBattle.make_runtime([a, d])
    var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))
    var entity_ids := PackedInt32Array([attacker_id, defender_id]); entity_ids.sort()

    # Turn1: defender 上盾
    d.buffs.apply_buff(d.stats, "buff_shield_50", defender_id)
    assert_eq(d.stats.get_final(ds.stat_id("SHIELD")), 50.0)
    assert_eq(d.stats.get_final(ds.stat_id("HP")), 100.0)

    # Turn2: attacker 三连 + 每段挂 DOT
    a.buffs.apply_buff(a.stats, "buff_on_hit_apply_dot", attacker_id)
    var hits := [12.0, 14.0, 18.0]
    for i in range(hits.size()):
        pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, float(hits[i]), replay, 200 + i, tags_mask, runtime)
    assert_eq(d.buffs.inst_ids.size(), 3) # 3个DOT实例

    # Turn3 start: DOT 第一次结算（3条trace）
    var before := replay.dot_traces.size()
    turn.on_turn_start(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
    var after := replay.dot_traces.size()
    assert_eq(after - before, 3)

    # Turn3: 驱散 DEBUFF，应移除 DOT
    var removed := d.buffs.dispel_by_tag(d.stats, "DEBUFF", false)
    assert_gt(removed, 0)

    # Turn4 start: 不再结算 DOT（trace不增加）
    before = replay.dot_traces.size()
    turn.on_turn_start(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
    after = replay.dot_traces.size()
    assert_eq(after - before, 0)

    # Turn4: 再挂3个DOT，并设置对DEBUFF免疫，驱散应失败
    for i in range(hits.size()):
        pipe.deal_damage(a.stats, d.stats, a.buffs, d.buffs, ds, float(hits[i]), replay, 400 + i, tags_mask, runtime)
    d.buffs.target_dispel_immunity_mask |= int(enums_rt.tag_mask(["DEBUFF"]))
    removed = d.buffs.dispel_by_tag(d.stats, "DEBUFF", false)
    assert_eq(removed, 0)

    # Turn5 start: DOT仍结算（trace+3）
    before = replay.dot_traces.size()
    turn.on_turn_start(entity_ids, runtime.buff_by_entity, runtime.stats_by_entity, pipe, ds, replay)
    after = replay.dot_traces.size()
    assert_eq(after - before, 3)
```

- [ ] **Step 2: 提交**

```bash
git add godot-buff/addons/omnibuff/tests/rpg/test_full_turn_script_battle.gd
git commit -m "test(rpg): add full-turn script battle integration test (TURN_START dot)"
```

