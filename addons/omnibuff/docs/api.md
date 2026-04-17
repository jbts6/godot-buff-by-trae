# OmniBuff API（契约文档）

本文档描述 OmniBuff 插件在**加载期**与**运行期**的关键“契约”（contract），用于：
- 让上层战斗框架（项目代码）以最小耦合方式接入
- 让数据（manifest/enums/defs）与运行时（Stats/Buff/DamagePipeline）之间的边界清晰
- 明确 Replay/Trace 的定位：**只记录输出，不参与逻辑驱动**

> 参考实现：
> - Manifest loader：`res://addons/omnibuff/config/manifest_loader.gd`
> - Dataset compiler：`res://addons/omnibuff/config/compiler/dataset_compiler.gd`
> - Runtime enums：`res://addons/omnibuff/runtime/core/enums_runtime.gd`
> - DamagePipeline & DamageContext：`res://addons/omnibuff/runtime/core/damage_pipeline.gd`
> - BuffCore（event/action/scope/runtime meta）：`res://addons/omnibuff/runtime/core/buff_core.gd`
> - Replay：`res://addons/omnibuff/runtime/core/replay.gd`

---

## 0. Public API / Stable API（给插件使用方）

本节面向“把 OmniBuff 当插件接入到自己项目”的开发者，优先回答：
- 我应该从哪里引用类？
- 哪些 API 是稳定推荐的（升级不容易炸）？
- BONUS_DAMAGE / 不递归 guard 应该怎么配？

相关文档导航（更偏“项目内战斗开发接入”）：
- 接入主线：`res://addons/omnibuff/docs/integrator_guide.md`
- 数据协议速查 + recipes：`res://addons/omnibuff/docs/schema_reference.md`
- 调试与回归：`res://addons/omnibuff/docs/debug_and_qa.md`

### 0.1 Autoload：`OmniBuff`（命名空间入口）

启用插件后会有 Autoload：`OmniBuff`（见 `res://addons/omnibuff/runtime/omnibuff_singleton.gd`）。

它暴露的是 **Script 资源（preload 的类）**，使用方式：

```gdscript
var pipe := OmniBuff.DamagePipeline.new()
var replay := OmniBuff.Replay.new()
var buffs := OmniBuff.BuffCore.new(ds, enums_rt)
var exec := OmniBuff.BattleExecutor.new()
```

> 强烈建议：业务代码尽量通过 `OmniBuff.Xxx` / `preload("res://...")` 引用脚本，
> 不要直接依赖 `class_name` 标识符（例如 `OmniExprContext`），以避免脚本解析时机导致的编译问题。

目前对外暴露的常用入口（节选）：
- Runtime Core：`BuffCore` / `DamagePipeline` / `Replay` / `BattleExecutor` / `CommandContext` / `ExprContext`
- Runtime Components：`StatsComponent` / `TurnComponent`
- Config/Compiler：`ManifestLoader` / `DatasetCompiler` / `EnumsRuntime` / `Validate`

### 0.2 Stable API：`DamagePipeline.deal_damage_v1(...)`

`deal_damage(...)` 内部签名可能继续演进（例如新增可选参数），如果你更在意升级兼容性，推荐使用：

- `OmniDamagePipeline.deal_damage_v1(...)`（旧签名兼容层，不包含 `is_bonus_damage`）

示例（仍使用位置参数，但签名稳定）：

```gdscript
var ctx := pipe.deal_damage_v1(
	attacker_stats,
	defender_stats,
	attacker_buffs,
	defender_buffs,
	ds,
	10.0,
	replay,
	1,   # turn_index
	0,   # tags_mask
	runtime,
	0,   # roll_key
	-1,  # skill_id
	0,   # damage_type
	0    # element
)
```

### 0.3 BONUS_DAMAGE（value / ratio / expr）与“不递归”guard

BONUS_DAMAGE 是一个 **DAMAGE 事件动作**，典型触发点：
- `event_type=DAMAGE`
- `event_phase=AFTER_DEAL`

并需要配置不递归 guard（否则追加伤害会触发追加伤害）：

```jsonc
{
  "filters": { "require_not_bonus_damage": true },
  "action": { "kind": "BONUS_DAMAGE", "value": 3.0, "tags_mask_any": ["BONUS_DAMAGE"] }
}
```

三种数值来源 **互斥三选一**（validators 会校验）：

1) 固定值：
```jsonc
{ "kind": "BONUS_DAMAGE", "value": 3.0 }
```

2) 按最终伤害比例：
```jsonc
{ "kind": "BONUS_DAMAGE", "ratio": 0.5 }
```

3) 表达式：
```jsonc
{ "kind": "BONUS_DAMAGE", "expr": "final_damage*0.5" }
```

> BONUS_DAMAGE 的 trace 顺序可能与“base hit”不同（因为它是嵌套结算）。
> 若你需要在回放/断言里识别 bonus hit，建议用 `tags_mask` 的 `BONUS_DAMAGE` bit 来区分，而不要依赖数组顺序。

---

## 0.4 扩展能力索引（Phase 1/2）

### Stats breakdown（属性面板）

Phase 2 提供：
- `StatsComponent.get_breakdown(stat_id) -> {"base","bonus","final"}`

口径：
- `base = base_values + computed_base(derived)`
- `final = 完整 pipeline 后的最终值`
- `bonus = final - base`

建议 UI：显示 final（主值），并展示 base/bonus（折叠/tooltip）。

### LIFE events（DEATH/REVIVE）

Phase 1 增加 `event_type=LIFE`，需要上层战斗系统在死亡/复活时显式触发：
- `buffs.emit_event("LIFE","DEATH", LifeContext)`
- `buffs.emit_event("LIFE","REVIVE", LifeContext)`

详见：`integrator_guide.md` 的 LIFE 触发示例。

### stack actions（ADD_STACKS / SET_STACKS）

Phase 1 wrap-up 增加：
- `ADD_STACKS {buff_id, delta, min_stack, max_stack}`
- `SET_STACKS {buff_id, value, min_stack, max_stack}`

常见配方见：`schema_reference.md`。

### 技能系统接入建议（Skill Integration）

关于 `skill_id/damage_type/element/tags_mask/roll_key` 的推荐约定（多段/多目标/追加伤害的确定性组织方式）：
- `integrator_guide.md#9-技能系统接入建议skill_iddamage_typeelementtags_maskroll_key`

---

## 1. Dataset 加载链路（manifest → enums → sources → validate → compile）

### 1.1 入口：`OmniManifestLoader.load_dataset_full()`

加载入口（推荐使用“full”版本）：

```gdscript
var result := OmniBuff.ManifestLoader.load_dataset_full("res://data/base_demo/manifest.json", true)
```

其职责（当前实现）：
1. 读取 `manifest.json`（权威入口）
2. 在 `manifest.files[]` 中找到 `type=="enums"` 的条目并加载 `enums.json`
3. 按 `manifest.files[]` 加载其余源文件（json/csv）
4. 调用 `OmniValidate.validate_all(...)` 进行统一校验并返回 issues（strict/lenient）

返回结构：`OmniManifestLoader.Result`
- `manifest: Dictionary`：manifest 原始字典
- `enums: Dictionary`：enums.json 原始字典（用于构建 `OmniEnumsRuntime`）
- `sources: Dictionary`：源文件内容（按 `files[].type` 作为 key）
- `source_paths: Dictionary`：源文件路径（同 key，用于报错定位）
- `issues: Array[OmniValidate.Issue]`：加载/校验问题列表

> strict 语义：
> - `strict=true`：关键缺失/非法结构以 ERROR 记录（一般应阻断继续运行）
> - `strict=false`：部分问题以 WARNING 记录（允许继续，但结果不保证）

### 1.2 enums 运行时映射：`OmniEnumsRuntime.from_enums_json()`

```gdscript
var enums_rt := OmniBuff.EnumsRuntime.from_enums_json(result.enums)
```

用途：
- 将配置层的字符串枚举映射为运行时的 `int code`
- 将配置层 `tags` 映射为运行时 `bitmask`

关键 API：
- `enums_rt.enum_int(enum_name, value) -> int`
- `enums_rt.tag_mask(tags:Array) -> int`
- `enums_rt.tags_from_mask(mask:int) -> Array[String]`（用于调试/断言，稳定输出）

### 1.3 编译：`OmniDatasetCompiler.compile() -> OmniCompiledDataset`

```gdscript
var ds := OmniBuff.DatasetCompiler.compile(result.manifest, enums_rt, result.sources)
```

编译边界约束（非常重要）：
- **只有 Parser/Compiler 层允许直接读取 raw JSON/CSV 的字段名**
- **运行时核心（Stats/Buff/Damage）只允许依赖 `OmniCompiledDataset` 的编译后结构**

当前最小可用版的编译产物（仍以 `Array[Dictionary]` 暂存 defs）：
- `ds.stat_id_to_int: Dictionary`：`"HP" -> 0`（示例）
- `ds.stat_defs: Array[Dictionary]`：`index=stat_id` 的定义数组
- `ds.buff_id_to_int: Dictionary`：`"buff_dot_fire_3t" -> 12`（示例）
- `ds.buff_defs: Array[Dictionary]`：`index=buff_def_id` 的定义数组

并提供便捷查询：
- `ds.stat_id("HP") -> int`（不存在返回 -1）
- `ds.buff_id("buff_xxx") -> int`（不存在返回 -1）

> 约定：未知 `stat_id/buff_id` 在加载期应由校验器阻断或至少报警；运行时一般将其视为 no-op（返回 -1）。

---

## 2. runtime dict 契约（`stats_by_entity` / `buff_by_entity`）

### 2.1 runtime 的用途与存放位置

**runtime 是一个最小战斗运行时环境字典**，用于事件动作（Action）跨实体定位目标对象，避免模块间强耦合。

runtime **通过 `DamageContext.meta["runtime"]` 传入**：
- `OmniDamagePipeline.deal_damage(..., runtime)`
- `OmniTurnComponent.on_turn_start/on_turn_end(..., stats_by_entity, buff_by_entity, ..., replay)`

在 `OmniBuffCore` 内部，事件动作通过如下方式取回：
- `ctx.get_meta("runtime")`（要求是 Dictionary）

### 2.2 字典结构（最小契约）

```gdscript
runtime = {
  "stats_by_entity": { eid: OmniStatsComponent },
  "buff_by_entity":  { eid: OmniBuffCore }
}
```

约束：
- key 必须为 **int entity_id**
- `stats_by_entity[eid]` 必须为该实体的 `OmniStatsComponent` 引用
- `buff_by_entity[eid]` 必须为该实体的 `OmniBuffCore` 引用

推荐惯例：
- `runtime` 中应包含战斗内所有“可能被 scope 命中”的实体（见下文 scope 语义）
- `entity_id` 统一由上层战斗系统分配，并保证全局唯一（至少在同一场战斗内唯一）

性能/正确性注意事项：
- 插件内部明确约束：**禁止遍历全实体**（例如 `runtime.stats_by_entity.keys()`），事件只遍历监听子集（EventIndex）。
- 因此，上层不要期望插件会“扫描 runtime 里的所有实体”来做任何事；runtime 的唯一目的是“按 id 精确取对象”。

---

## 3. event scope 语义（`scope` / `filters.stat_threshold.scope`）

scope 的存在目的：
- 让数据配置的 trigger/action 在运行期能把“作用目标”从字符串映射为具体实体 ID

### 3.1 scope 值集合（最小约定）

在 `buff_def.triggers[].scope`、`filters.stat_threshold.scope` 中使用，均通过同一个解析规则：

| scope（忽略大小写） | 解析结果 | 说明 |
|---|---:|---|
| `""` / `SELF` | `owner_entity_id` | 当前 BuffCore 的归属实体（事件接收者） |
| `SOURCE` / `ATTACKER` | `ctx.attacker_id` | 伤害/技能来源方（约定为 attacker） |
| `TARGET` / `DEFENDER` | `ctx.defender_id` | 伤害/技能目标方（约定为 defender） |

解析实现见：`OmniBuffCore._resolve_scope_entity_id(scope, ctx)`

### 3.2 “SELF”到底是谁：事件接收者的含义

同一份 `DamageContext` 会在不同阶段分别发送给不同的 BuffCore：
- `BEFORE_DEAL/AFTER_DEAL/BUILD` 等阶段通常由攻击方 `buff_attacker.emit_event(...)` 接收
- `BEFORE_TAKE/AFTER_TAKE` 等阶段通常由防守方 `buff_defender.emit_event(...)` 接收

因此：
- 当 `buff_attacker.emit_event(...)` 时，`SELF == attacker`
- 当 `buff_defender.emit_event(...)` 时，`SELF == defender`

这也是 scope 存在的核心价值：同一个 action 可以在不同接收者语境下稳定定义“施法者/目标/自己”。

### 3.3 scope 在哪些地方会被用到

当前运行时会在以下能力上读取 scope：

1) `action.APPLY_BUFF` / `action.CHANCE_APPLY_BUFF`  
根据 scope 解析出 `target_eid`，再从 runtime 中取：
- `stats_by_entity[target_eid]`
- `buff_by_entity[target_eid]`  
随后调用 `target_buff.apply_buff(target_stats, buff_id, source_eid)`。

> 当前最小约定：事件施加的来源实体 `source_eid = ctx.attacker_id`（更贴近“施法者/攻击者”）。

2) `action.SET_STAT_FINAL`  
根据 scope 定位目标实体的 StatsComponent，并通过“调整 base 值”把最终值设到期望值。

3) `action.DOT_*`（`DOT_MUL_STACKS/DOT_ADD_STACKS/DOT_SET_STACKS/DOT_CLEAR`）  
根据 scope 定位“DOT 承载者实体”（也就是其 BuffCore.owner），并对其 DOT 池做过滤与 stacks 操作。

4) `filters.stat_threshold`  
根据 `filters.stat_threshold.scope` 定位要读取的实体 StatsComponent，并比较其 `stat` 与阈值。

---

## 4. DamageContext 关键字段（逻辑输入/输出 + meta 扩展）

`DamageContext` 定义于：`res://addons/omnibuff/runtime/core/damage_pipeline.gd`

### 4.1 直接字段（强约定）

| 字段 | 类型 | 语义 |
|---|---|---|
| `attacker_id` | `int` | 攻击者实体 ID |
| `defender_id` | `int` | 防守者实体 ID |
| `tags_mask` | `int` | 事件 tag bitmask（供 filters.tag_mask_any） |
| `hit` | `bool` | 是否命中 |
| `crit` | `bool` | 是否暴击 |
| `base_damage` | `float` | 基础伤害（会被事件在早期阶段修改） |
| `final_damage` | `float` | 最终伤害（resolve/apply 后得到） |

保留字段（当前 demo 未用，先占位）：
- `skill_id: int`
- `damage_type: int`
- `element: int`

### 4.2 meta（弱耦合扩展点）

为了避免 `DamageContext` 强耦合过多字段，运行时通过 meta 传递“可选信息”：
- `ctx.set_meta("turn_index", turn_index)`：用于确定性随机 / 追帧
- `ctx.set_meta("runtime", runtime_dict)`：用于事件动作跨实体定位
- `ctx.set_meta("roll_key", roll_key)`：用于命中/暴击等概率事件的**确定性回放**（多段/多目标/追加触发时必须唯一）

以及在流程中可能额外写入：
- `ctx.meta["dmg_reduce_ratio"]`：若启用 `DMG_REDUCE`，记录本次减伤比例
- `ctx.meta["absorbed_shield"]`：若启用 `SHIELD`，记录本次被护盾吸收的数值

### 4.3 tags_mask 写入时机

`tags_mask` 必须在事件触发前写入（否则 filters 无法命中）。当前主流程保证了：

```gdscript
ctx.tags_mask = tags_mask
buff_attacker.emit_event(..., "BUILD", ctx)
```

上层在调用 `deal_damage()` 时，应把 tags_mask 当作“输入参数”而不是在回调中临时修改。

---

## 5. Replay / Trace：输出（output-only）定位

`OmniReplay` 定义于：`res://addons/omnibuff/runtime/core/replay.gd`

### 5.1 设计定位（强约束）

Replay 的目标是“记录与导出”，**不参与逻辑驱动**：
- `DamagePipeline/BuffCore/TurnComponent` 的逻辑在没有 replay 的情况下也必须完整、确定性、可运行
- replay 仅用于：调试、断言、回归测试、一致性校验（例如同版本同输入是否得到相同输出）

实现上也体现为：
- 调用端以可选参数传入 `replay: RefCounted = null`
- 内部会用 `replay.has_method("trace_damage")` / `trace_dot_tick` 进行鸭子类型检查
- 即便没有 replay，逻辑也不应改变

### 5.2 Trace 数据结构（输出）

1) `damage_traces: Array[OmniReplay.DamageTrace]`  
由 `OmniDamagePipeline.deal_damage()` 在一次伤害结束后写入：
- `turn, attacker_id, defender_id`
- `roll_key`：本次结算的 RNG key（用于解释/验证 hit/crit 的确定性回放）
- `hit, crit`
- `base_damage, final_damage`
- `tags_mask`
- `triggered_inst_ids: PackedInt32Array`：本次伤害各阶段命中的 buff inst_id（按发生顺序拼接）
- `stage_triggers: Dictionary`：按阶段分组的命中列表（如 `"BUILD" -> [inst_id...]`）

2) `dot_traces: Array[OmniReplay.DotTrace]`  
由 `OmniBuffCore` 的 DOT tick 在结算时写入：
- `turn`
- `dot_inst_id`
- `owner_buff_inst_id`（DOT 归属的 buff 实例，用于追溯来源）
- `source_entity_id / target_entity_id`
- `read_source_stat / source_stat_value`（证明 DOT 读取走 StatCache）
- `base_ratio / base_damage / final_damage`
- `tags_mask`

### 5.3 调试导出（输出）

Replay 提供便捷 debug 文本输出（不影响逻辑）：
- `debug_dump_last_damage()`
- `debug_dump_damage_range(from_index)`
- `debug_dump_last_dot()`
- `debug_dump_dot_range(from_index)`

> 这些输出是“观测值”，任何战斗逻辑不应依赖其内容（否则将破坏可复盘/可替换性）。
