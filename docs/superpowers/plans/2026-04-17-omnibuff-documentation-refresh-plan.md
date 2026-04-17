# OmniBuff Documentation Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完善 OmniBuff 文档，面向“项目内战斗开发者”提供可接入、可查阅、可回归的插件使用指南（Stats 面板、事件/动作、数据协议速查、调试与回归）。

**Architecture:** 保持 `README.md` 作为入口；`api.md` 保持 contract；新增 3 份 docs：Integrator Guide / Schema Reference / Debug & QA，并在入口处互相链接。

**Tech Stack:** Markdown。

---

## 0) 文件清单

**Create**
- `godot-buff/addons/omnibuff/docs/integrator_guide.md`
- `godot-buff/addons/omnibuff/docs/schema_reference.md`
- `godot-buff/addons/omnibuff/docs/debug_and_qa.md`

**Modify**
- `godot-buff/addons/omnibuff/README.md`
- `godot-buff/addons/omnibuff/docs/api.md`

---

## Task 1：新增 Integrator Guide（接入主线）

**Files:**
- Create: `godot-buff/addons/omnibuff/docs/integrator_guide.md`

- [ ] **Step 1: 写文档骨架（目录 + 快速跳转）**

包含章节（建议）：
1. 接入 checklist（启用插件、autoload、数据集、runtime）
2. 最小闭环示例：load dataset → ds/enums_rt → Stats/Buff/Pipe → deal_damage_v1
3. runtime dict 契约（stats_by_entity/buff_by_entity）
4. scope 语义（SELF/SOURCE/TARGET；LIFE 的 source_id/actor_id）
5. Stats 面板（get_breakdown：base/bonus/final；derived/curve 展示建议）
6. 事件/动作最佳实践（BONUS_DAMAGE guard；ADD_STACKS/SET_STACKS；LIFE 触发方式）
7. DOT/回合推进（TURN_START tick；与 TurnComponent 对齐）

- [ ] **Step 2: 补充关键代码片段**

必须包含 3 段可复制代码：
1) 最小伤害：

```gdscript
var result := OmniBuff.ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
var enums_rt := OmniBuff.EnumsRuntime.from_enums_json(result.enums)
var ds := OmniBuff.DatasetCompiler.compile(result.manifest, enums_rt, result.sources)

var pipe := OmniBuff.DamagePipeline.new()
var replay := OmniBuff.Replay.new()

var atk := OmniBuff.StatsComponent.new(101, ds)
var def := OmniBuff.StatsComponent.new(202, ds)
var atk_buffs := OmniBuff.BuffCore.new(ds, enums_rt)
var def_buffs := OmniBuff.BuffCore.new(ds, enums_rt)

var runtime := {"stats_by_entity": {101: atk, 202: def}, "buff_by_entity": {101: atk_buffs, 202: def_buffs}}
var tags_mask := int(enums_rt.tag_mask(["BUFF"]))
var ctx := pipe.deal_damage_v1(atk, def, atk_buffs, def_buffs, ds, 10.0, replay, 1, tags_mask, runtime)
```

2) Stats 面板：

```gdscript
var hp_id := ds.stat_id("HP")
var bd := actor_stats.get_breakdown(hp_id)
print("HP base=", bd.base, " bonus=", bd.bonus, " final=", bd.final)
```

3) LIFE 事件（死亡/复活）：

```gdscript
var life := OmniLifeContext.new()
life.actor_id = victim_id
life.source_id = killer_id
life.tags_mask = int(enums_rt.tag_mask(["BUFF"]))
life.set_meta("runtime", runtime)
victim_buffs.emit_event("LIFE", "DEATH", life)
```

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/docs/integrator_guide.md
git -C godot-buff commit -m "docs: add integrator guide"
```

---

## Task 2：新增 Schema Reference（enums/stat_defs/buff_defs 速查）

**Files:**
- Create: `godot-buff/addons/omnibuff/docs/schema_reference.md`

- [ ] **Step 1: enums.json 速查**
- event_type/event_phase/action_kind/op_type/apply_phase/stack_mode 的用途与常见值

- [ ] **Step 2: stat_defs.json 速查**
- 基础字段（id/default/min/max/clamp）
- Phase2 字段（derived/curve）示例：
  - LINEAR from/ratio
  - curve DR_SOFTCAP k/apply_at

- [ ] **Step 3: buff_defs.json 速查**
- buff 基础结构：duration/stack/effects/triggers
- triggers：event_type/event_phase/filters/action/scope
- Phase1/Phase1 wrap-up 关键字段：
  - LIFE filters：actor_id/source_id
  - Stack actions：ADD_STACKS/SET_STACKS

- [ ] **Step 4: 常见配方（recipes）**
至少包含：
1) BONUS_DAMAGE（不递归）
2) 复活清 DEBUFF（LIFE REVIVE + DISPEL）
3) 死亡击杀回血（LIFE DEATH + HEAL scope=SOURCE）
4) 命中后减少某 debuff 层数（ADD_STACKS delta=-1）

- [ ] **Step 5: Commit**

```bash
git -C godot-buff add addons/omnibuff/docs/schema_reference.md
git -C godot-buff commit -m "docs: add schema reference"
```

---

## Task 3：新增 Debug & QA（buff_ui_demo / DebugHUD / 回归）

**Files:**
- Create: `godot-buff/addons/omnibuff/docs/debug_and_qa.md`

- [ ] **Step 1: buff_ui_demo 使用说明**
- dataset 切换、run selected/run all
- ErrorList：错误行高亮 + 汇总列表跳转
- 复制日志/清空日志

- [ ] **Step 2: Debug HUD 各区块解释**
- Stats / StatMods / Buffs / Dots / Listeners 的关键字段与含义

- [ ] **Step 3: 如何新增 scenario（对齐 tests）**
- 在 `buff_ui_demo.gd` 的 `_register_scenarios()` 新增条目
- 写 `_sc_xxx()` 场景函数
- 推荐同步补一个 tests/rpg（若是新增能力）

- [ ] **Step 4: GUT 回归流程**
- Editor 配置
- `run_gut_tests.sh` 的使用与目录约定

- [ ] **Step 5: Commit**

```bash
git -C godot-buff add addons/omnibuff/docs/debug_and_qa.md
git -C godot-buff commit -m "docs: add debug and QA guide"
```

---

## Task 4：更新 README 与 api.md（入口与交叉链接）

**Files:**
- Modify: `godot-buff/addons/omnibuff/README.md`
- Modify: `godot-buff/addons/omnibuff/docs/api.md`

- [ ] **Step 1: README 增加“文档导航”**
在 README 顶部增加：
- Integrator Guide
- Schema Reference
- Debug & QA
- API contract（api.md）

- [ ] **Step 2: api.md 增加“扩展能力索引”**
在 api.md 合适位置新增小节：
- Stats breakdown（get_breakdown）
- LIFE events + stacks actions（指向 schema_reference 的 recipes）
- 并补链接到 integrator/debug 文档

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/README.md addons/omnibuff/docs/api.md
git -C godot-buff commit -m "docs: link integrator/schema/debug docs from readme and api"
```

---

## 最终检查

- [ ] 打开 README，从入口能一路找到其它 3 份 docs 与 api.md
- [ ] Integrator Guide 中的代码片段与当前仓库 API 一致（例如 deal_damage_v1、get_breakdown、LifeContext）
- [ ] 文档涵盖 Phase1 wrap-up（LIFE/STACKS）与 Phase2（derived/curve/breakdown）

