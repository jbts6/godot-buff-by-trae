# OmniBuff Integrator Guide（面向战斗系统接入）

> 读者：在项目内继续开发技能与战斗系统的开发者。  
> 目标：不读源码也能把 OmniBuff 接入战斗闭环，并能正确使用 Phase 1/2 的关键能力（LIFE/Stacks、Stats breakdown、Derived/Curve）。

## 目录

- [1. 接入 Checklist](#1-接入-checklist)
- [2. 最小闭环：加载数据集 → 上 Buff → 结算一次伤害](#2-最小闭环加载数据集--上-buff--结算一次伤害)
- [3. runtime dict 契约（非常重要）](#3-runtime-dict-契约非常重要)
- [4. scope 语义（SELF/SOURCE/TARGET）与 LIFE 事件](#4-scope-语义selfsourcetarget-与-life-事件)
- [5. Stats 面板：base/bonus/final（Phase 2）](#5-stats-面板basebonusfinalphase-2)
- [6. 事件与动作最佳实践（Phase 1）](#6-事件与动作最佳实践phase-1)
- [7. DOT 与回合推进](#7-dot-与回合推进)
- [8. 推荐调试工作流（Demo + HUD）](#8-推荐调试工作流demo--hud)
- [9. 技能系统接入建议（skill_id/damage_type/element/tags_mask/roll_key）](#9-技能系统接入建议skill_iddamage_typeelementtags_maskroll_key)

---

## 1. 接入 Checklist

1) **启用插件**
- `Project → Project Settings → Plugins` 勾选 `OmniBuff`
- 启用后会自动安装 Autoload：`/root/OmniBuff`（命名空间入口）

2) **加载数据集（manifest → enums → defs）**
- 使用 `OmniBuff.ManifestLoader.load_dataset_full(manifest_path, strict)`
- 生成 `enums_rt`：`OmniBuff.EnumsRuntime.from_enums_json(...)`
- 编译 `ds`：`OmniBuff.DatasetCompiler.compile(...)`

3) **创建运行时对象**
- `StatsComponent`（每个实体一个）
- `BuffCore`（每个实体一个）
- `DamagePipeline`（可全局一个）
- `TurnComponent`（可全局一个）
- （可选）`Replay`（用于调试/回归；不参与逻辑）

4) **准备 runtime dict（事件动作需要）**
- `runtime = {"stats_by_entity": {eid: StatsComponent}, "buff_by_entity": {eid: BuffCore}}`

---

## 2. 最小闭环：加载数据集 → 上 Buff → 结算一次伤害

> 推荐用 `rpg_tests` 数据集跑通（功能覆盖更全）。

```gdscript
# 假设：你已启用 OmniBuff 插件（项目中存在 /root/OmniBuff）

func run_one_hit() -> void:
	# 1) 加载并编译数据集（strict=true：校验失败直接阻断）
	var result := OmniBuff.ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	var enums_rt := OmniBuff.EnumsRuntime.from_enums_json(result.enums)
	var ds := OmniBuff.DatasetCompiler.compile(result.manifest, enums_rt, result.sources)

	# 2) 构造运行时对象
	var pipe := OmniBuff.DamagePipeline.new()
	var replay := OmniBuff.Replay.new()

	# 3) 构造实体（纯数据，不依赖场景树）
	var attacker := OmniBuff.StatsComponent.new(101, ds)
	var defender := OmniBuff.StatsComponent.new(202, ds)
	var buff_attacker := OmniBuff.BuffCore.new(ds, enums_rt)
	var buff_defender := OmniBuff.BuffCore.new(ds, enums_rt)

	# 4) runtime：用于事件动作跨实体定位
	var runtime := {
		"stats_by_entity": {101: attacker, 202: defender},
		"buff_by_entity":  {101: buff_attacker, 202: buff_defender},
	}
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 5) 示例：上 buff（也可以不加）
	buff_attacker.apply_buff(attacker, "buff_atk_flat_20", attacker.entity_id)

	# 6) 结算一次伤害
	var ctx = pipe.deal_damage_v1(attacker, defender, buff_attacker, buff_defender, ds, 10.0, replay, 1, tags_mask, runtime)
	print("final=", ctx.final_damage, " defender_hp=", defender.get_final(ds.stat_id("HP")))
```

---

## 3. runtime dict 契约（非常重要）

OmniBuff 的事件动作（例如 `APPLY_BUFF` / `DISPEL` / `ADD_STACKS`）需要在运行时按 entity_id 精确取到目标实体对象，因此你必须维护一个最小的 runtime 环境：

```gdscript
runtime = {
  "stats_by_entity": { eid: OmniStatsComponent },
  "buff_by_entity":  { eid: OmniBuffCore }
}
```

约束：
- key 必须是 **int entity_id**
- 值必须是你当前战斗中那一份 `StatsComponent` / `BuffCore` 实例引用
- 插件内部不会遍历全实体做逻辑（性能约束），只会“按 id 取对象”

---

## 4. scope 语义（SELF/SOURCE/TARGET）与 LIFE 事件

### 4.1 scope 的核心含义

同一条配置（trigger/action）在不同上下文中需要稳定表达“对谁生效”，因此引入 scope：

- `SELF`：当前 BuffCore 的 owner（谁在接收事件，SELF 就是谁）
- `SOURCE`：伤害/事件来源（DAMAGE 里通常等价 attacker；LIFE 里优先 source_id）
- `TARGET`：伤害/事件目标（DAMAGE 里通常等价 defender；LIFE 里可退化为 actor_id）

### 4.2 LIFE（DEATH / REVIVE）

LIFE 不会由 DamagePipeline 自动触发，需要上层战斗系统在关键节点显式触发：

#### 触发 DEATH（死亡/被击杀）

```gdscript
const LifeContext = preload("res://addons/omnibuff/runtime/core/life_context.gd")

func emit_death(victim_id: int, killer_id: int, victim_buffs: RefCounted, enums_rt: RefCounted, runtime: Dictionary) -> void:
	var life := LifeContext.new()
	life.actor_id = victim_id
	life.source_id = killer_id
	life.tags_mask = int(enums_rt.tag_mask(["BUFF"]))
	life.set_meta("runtime", runtime)
	victim_buffs.emit_event("LIFE", "DEATH", life)
```

#### 触发 REVIVE（复活）

```gdscript
func emit_revive(actor_id: int, actor_buffs: RefCounted, enums_rt: RefCounted, runtime: Dictionary) -> void:
	var life := LifeContext.new()
	life.actor_id = actor_id
	life.source_id = -1
	life.tags_mask = int(enums_rt.tag_mask(["BUFF"]))
	life.set_meta("runtime", runtime)
	actor_buffs.emit_event("LIFE", "REVIVE", life)
```

---

## 5. Stats 面板：base/bonus/final（Phase 2）

`StatsComponent.get_breakdown(stat_id)` 返回：
- `base`：基础值（含 Phase2 的 derived computed_base）
- `final`：完整流水线后的最终值（flat/pct/override/final_add/curve/clamp）
- `bonus = final - base`

示例（UI 层可以直接用）：

```gdscript
var hp_id := ds.stat_id("HP")
var bd: Dictionary = actor_stats.get_breakdown(hp_id)
print("HP base=", bd["base"], " bonus=", bd["bonus"], " final=", bd["final"])
```

建议 UI 展示方式：
- 面板大字显示 `final`
- 可折叠/tooltip 显示 `base` 与 `bonus`
- 若曲线（DR/Softcap）存在，bonus 可能包含曲线带来的差值：这是预期的“最终相对基础的变化”

---

## 6. 事件与动作最佳实践（Phase 1）

### 6.1 BONUS_DAMAGE 的不递归 guard

追加伤害必须配置 `filters.require_not_bonus_damage=true`，否则追加伤害会递归触发追加伤害。

### 6.2 stacks actions（ADD_STACKS / SET_STACKS）

用于“改层/清层/直接设为 0 触发移除”等效果：

- `ADD_STACKS`：`{buff_id, delta, min_stack, max_stack}`
- `SET_STACKS`：`{buff_id, value, min_stack, max_stack}`

常见：命中后把某个 debuff 减 1 层、或直接设为 0 清除。

### 6.3 LIFE filters

在 buff_defs 中可用：
- `filters.actor_id`：只对特定 actor_id 生效（LIFE 专用）
- `filters.source_id`：只对特定 source_id 生效（LIFE 专用）

---

## 7. DOT 与回合推进

关键约定：**DOT 默认在 TURN_START 结算**。

运行时接口：
- `TurnComponent.on_turn_start(...)`：回合开始（会 tick DOT）
- `TurnComponent.on_turn_end(...)`：回合结束（默认不 tick DOT）

---

## 8. 推荐调试工作流（Demo + HUD）

1) 打开 `res://addons/omnibuff/demo/buff_ui_demo.tscn`  
2) 选择 `rpg_tests` 数据集，运行对应 scenario  
3) 打开 Debug HUD：
   - `Dots`：DOT 的 turns/stacks（DotInstance 才是权威）
   - `Listeners`：有哪些监听者、最近触发命中了哪些 inst
   - `StatMods`：某个 stat 的 modifier 贡献项（可反查 buff_id）
4) 用“复制日志 / 复制 dump”把信息贴到 issue 或发给同事

---

## 9. 技能系统接入建议（skill_id/damage_type/element/tags_mask/roll_key）

> 本章目标：给技能系统一套“稳定注入 DamageContext 字段”的约定，确保：
> - filters（skill_id/element/damage_type）能稳定命中
> - 多段/多目标/追加伤害的命中/暴击与概率行为可复盘（roll_key 确定性）
> - tags_mask 能用于筛选与回放识别（尤其 BONUS_DAMAGE）

### 9.1 建议你在技能系统里维护的“编译表”（Skill Compile Table）

建议为每个技能（或每个 skill entry）维护一份“编译后”的运行时结构（伪结构）：

- `skill_id: int`
  - 用于 `filters.skill_id`
  - 建议：用你自己的技能表索引（稳定 int），不要直接用字符串
- `damage_type: int`
  - 用于 `filters.damage_type_any`
  - 建议：与 `enums.json` 的 damage_type 代码对齐（例如 0=PHYSICAL，1=MAGIC，2=TRUE）
- `element: int`
  - 用于 `filters.element_any`
  - 建议：与 `enums.json` 的 element 代码对齐（例如 0=FIRE，1=ICE）
- `tags: Array[String]`
  - 运行时用 `enums_rt.tag_mask(tags)` 生成 `tags_mask`
  - 建议：默认包含 `"SKILL"`，若是普攻包含 `"ATTACK"`；若是额外结算包含 `"BONUS_DAMAGE"`

> 注意：tag 不是“随便写字符串”，它依赖 enums.json 的 tag 表；推荐把常用 tag 做成常量列表并在数据集里统一维护。

### 9.2 roll_key：确定性 RNG 的“唯一键”（强烈建议遵守）

OmniDamagePipeline 的命中/暴击采用确定性 RNG：
- seed 由 `turn_index + roll_key + attacker_id + defender_id + salt` 组合而来
- 因此：**同一回合内每个独立结算点必须使用唯一 roll_key**

推荐模板（纯函数，不依赖随机数）：

```gdscript
func make_roll_key(cast_seq: int, target_index: int, hit_index: int, kind: int) -> int:
	# kind: 0=base_hit, 1=bonus, 2=dot_trigger, 3=proc
	# cast_seq: 本场战斗内“施法序号”（同一施法实例内保持一致）
	# target_index: 目标在稳定排序列表中的索引（eid 升序）
	# hit_index: 多段中的段序号（从 0 开始）
	return cast_seq * 100000 + kind * 10000 + target_index * 100 + hit_index
```

关键约束：
- `targets` 必须稳定排序（例如 eid 升序），否则 target_index 会漂移，导致复盘不一致
- bonus/proc 需要与 base hit 使用不同 kind（或不同 offset），避免 roll_key 冲突

### 9.3 多段/多目标（ALL）的调用模板

建议策略：
- 多目标：先对目标 eid 升序排序
- 多段：每段一次 `deal_damage_v1` / `deal_damage` 调用
- 每次调用都明确传入：`roll_key/skill_id/damage_type/element/tags_mask`

伪代码：

```gdscript
targets.sort()
for ti in range(targets.size()):
	for hi in range(hit_count):
		var rk := make_roll_key(cast_seq, ti, hi, 0) # base hit
		pipe.deal_damage_v1(attacker_stats, target_stats, atk_buffs, tgt_buffs, ds,
			base_damage_per_hit[hi], replay, turn_index, tags_mask, runtime,
			rk, skill_id, damage_type, element
		)
```

### 9.4 BONUS_DAMAGE 与不递归 guard（两种来源都要注意）

#### 情况 A：由 Buff action `BONUS_DAMAGE` 触发（推荐数据驱动）

必须配置：
- `filters.require_not_bonus_damage=true`

原因：
- BONUS_DAMAGE 的内部实现会再走一次 DamagePipeline；若不加 guard 会无限递归

#### 情况 B：技能脚本直接调用 `deal_damage(..., is_bonus_damage=true)` 作为额外伤害

建议：
- `is_bonus_damage=true`
- `tags_mask` 里包含 `BONUS_DAMAGE`
- `roll_key` 使用 `kind=1`（bonus namespace）

这样可以让：
- filters.require_not_bonus_damage 生效（避免“额外伤害触发额外伤害”）
- replay 里能用 tags_mask 区分 bonus hit（而非依赖 trace 顺序）

### 9.5 完整示例：多目标 + 三段 + 第二段额外 bonus hit

> 说明：
> - 这是“技能系统侧”的推荐组织方式，不依赖任何新 runtime 类型。
> - 目标排序稳定（eid 升序）。
> - 第二段在命中时额外结算一次 bonus hit（演示 is_bonus_damage 与 roll_key namespace）。

```gdscript
func cast_triple_slash_all(
	caster_id: int,
	target_ids: Array[int],
	cast_seq: int,
	turn_index: int,
	skill_id: int,
	damage_type: int,
	element: int,
	enums_rt: RefCounted,
	ds: RefCounted,
	pipe: RefCounted,
	replay: RefCounted,
	runtime: Dictionary
) -> void:
	# 1) 稳定排序（保证确定性）
	target_ids.sort()

	# 2) 计算 tags_mask（建议 SKILL + 其它 tag）
	var base_tags_mask := int(enums_rt.tag_mask(["SKILL"]))
	var bonus_tags_mask := int(enums_rt.tag_mask(["SKILL", "BONUS_DAMAGE"]))

	# 3) 多段伤害配置（示例）
	var hits := [8.0, 8.0, 12.0] # 三段基础伤害

	for ti in range(target_ids.size()):
		var tid := int(target_ids[ti])
		var atk_stats = runtime["stats_by_entity"].get(caster_id, null)
		var atk_buffs = runtime["buff_by_entity"].get(caster_id, null)
		var tgt_stats = runtime["stats_by_entity"].get(tid, null)
		var tgt_buffs = runtime["buff_by_entity"].get(tid, null)
		if atk_stats == null or atk_buffs == null or tgt_stats == null or tgt_buffs == null:
			continue

		for hi in range(hits.size()):
			var rk := make_roll_key(cast_seq, ti, hi, 0) # base hit
			pipe.deal_damage(
				atk_stats, tgt_stats,
				atk_buffs, tgt_buffs,
				ds, float(hits[hi]), replay,
				turn_index, base_tags_mask, runtime,
				rk, skill_id, damage_type, element,
				false # is_bonus_damage
			)

			# 第二段：额外触发一次 bonus hit（示例：30% 追加伤害）
			if hi == 1:
				var bonus_rk := make_roll_key(cast_seq, ti, hi, 1) # kind=1 (bonus)
				pipe.deal_damage(
					atk_stats, tgt_stats,
					atk_buffs, tgt_buffs,
					ds, float(hits[hi]) * 0.3, replay,
					turn_index, bonus_tags_mask, runtime,
					bonus_rk, skill_id, damage_type, element,
					true # is_bonus_damage
				)
```

> 上面示例如果你希望“bonus 必须基于最终伤害”而不是 base_damage*ratio，建议使用数据驱动 BONUS_DAMAGE（见 schema_reference recipes）。
