# turn_skill_system — 规格说明（spec）

> 目标：在 Godot 4.7 中实现一个可启用的 EditorPlugin（带 Dock 编辑器），提供数据驱动（JSON 权威）的技能系统，并与项目既有 `addons/omnibuff` 集成（复用其 Buff/状态/叠加逻辑，且尽可能复用其伤害流水线与事件机制）。
>
> 本 spec 是“实现前的设计文档”，不包含最终代码；用于对齐架构、数据协议与扩展点。

---

## 0. 关键约束回顾（必须满足）

1. **JSON 为唯一权威来源**：技能不写在 `.tres`，Resource 仅允许用于运行时结构或编辑器临时模型。
2. **索引与懒加载**：必须实现 `data/skills/index.json`，运行时先读 index，`get_skill(id)` 时再读对应 JSON；并缓存、支持刷新。
3. **JSON 可维护性**：
   - unknown fields 必须保留（读入 → 编辑 → 写回不能丢字段）。
   - 保存时稳定缩进（建议 2 spaces），字段顺序尽量稳定（不要无意义重排）。
   - 校验报错必须定位：`file_path + field_path`。
4. **3×3 网格站位**：row/col 均为 0..2；目标选择需覆盖：单体、多目标、全体、前/后排、形状（至少行/列/十字/方块中的几种），并易扩展。
5. **公式系统**：表达式字符串（如 `50 + a.ATK * 1.2`），运行时在上下文中求值，可扩展，可追踪解析变量与结果，提供取整策略。
6. **omnibuff 集成**：不自研 Buff 系统；通过 `omni_buff_adapter.gd` 封装 add/remove/query/simulate。
7. **对外 API 固定**：
   - `SkillRuntime.cast(skill_id, caster, primary_cell := null, extra := {})`
   - `SkillRuntime.cast_to_unit(...)`
   - `SkillRuntime.cast_to_cell(...)`
   - `SkillRuntime.simulate_cast(...)`
8. **解耦 UI**：战斗表现通过信号/事件对接。
9. **命名规范**：文件/路径全 snake_case，class_name PascalCase，方法 snake_case，常量 UPPER_SNAKE_CASE。

---

## 1. 插件包信息

- 插件名（目录名）：`turn_skill_system`
- 根目录：`res://addons/turn_skill_system/`
- 子目录（固定）：
  - `runtime/`：运行时代码（SkillDB/SkillRuntime/Targeting/Formula/OmniBuffAdapter/事件总线等）
  - `editor/`：编辑器 Dock 与编辑器工具
  - `data/skills/{active,passive,aura}/`：技能 JSON 数据
  - `demo/`：最小可运行 Demo

> 说明（已确认口径）：**SkillRuntime 允许安装 Autoload**（通过 EditorPlugin 启用/禁用时自动安装/卸载），以实现业务侧真正“一行 cast”无需额外持有单例引用。

---

## 2. 候选架构方案（2~3 套）与推荐

### 方案 A（推荐）：纯脚本入口 + 可选 Autoload（轻耦合）

**核心**：
- `skill_runtime.gd` 提供 `class_name SkillRuntime` + `static` 方法，实现你要求的“一行调用”。
- 运行时依赖通过 `extra` 注入（例如 `grid`、`event_bus`、`runtime_dict`、`dataset` 等），避免硬绑定项目战斗框架。
- 插件启用后提供 Dock；运行时可不依赖 EditorPlugin。

**优点**：
- 最解耦、最容易集成到你现有战斗架构；
- 运行时无需 Autoload，也不污染全局；
- 方便写测试/模拟（全部纯数据调用）。

**缺点**：
- 如果你希望“完全零注入”，仍需要你在项目侧维护 `grid/event_bus/runtime_dict` 等对象引用。

### 方案 B：安装 Autoload（使用方更爽，但更侵入）

**核心**：
- 启用插件时，安装 Autoload：`TurnSkillSystem`（或 `SkillRuntime`）。
- `SkillRuntime.cast(...)` 内部直接从 Autoload 取 `SkillDB/Grid/EventBus/Omni` 运行时对象。

**优点**：
- 业务代码更“傻瓜式”；Demo 写起来更短。

**缺点**：
- 更侵入项目工程设置；多战斗实例/多存档并行时更难隔离；
- 需要更严格的生命周期/重置策略。

### 方案 C：混合（推荐备选）：无 Autoload，但提供 `SkillRuntimeContext` 统一注入

**核心**：
- 定义 `SkillRuntimeContext`（纯 Dictionary/RefCounted），把所有运行时依赖（grid/event_bus/omnibuff runtime dict）放进去。
- `cast(..., extra)` 若不提供 context，则走默认 context（比如静态单例缓存）。

**优点**：
- 平衡“使用体验”与“多实例隔离”。

**结论（已确认口径）**：采用 **方案 A 为主（解耦注入）**，但**同时落地方案 B 的 Autoload 安装**：
- 插件启用时安装 Autoload（例如 `TurnSkillRuntime` 或 `TurnSkillSystem`），内部持有 `SkillDB/EventBus/TargetingRegistry/OmniBuffAdapter` 等运行时对象；
- 业务代码仍可直接调用 `class_name SkillRuntime` 的静态方法；若发现 Autoload 存在，则优先使用 Autoload 上下文（实现“零注入”）；否则退化为需从 `extra` 注入必要依赖。

---

## 3. 核心对象模型与集成契约

### 3.1 Unit（战斗单位）最小契约（技能系统对外依赖）

技能系统不强绑定你的 Unit 实现，但需要一个最小“duck-typing”契约。
> 已确认口径：**采用字段方式（方式 1）**。

**方式 1：Unit 直接提供字段/方法（推荐）**
- `entity_id: int`（对应 OmniBuff 的 entity_id）
- `camp: String`（`"ally"` / `"enemy"`）
- `cell: Vector2i`（row/col）
- `stats: RefCounted`（建议为 `OmniBuff.StatsComponent`）
- `buffs: RefCounted`（建议为 `OmniBuff.BuffCore`）

**方式 2：提供适配器**
- 在 `extra` 里传入 `unit_adapter`，提供方法：
  - `get_entity_id(unit) -> int`
  - `get_camp(unit) -> String`
  - `get_cell(unit) -> Vector2i`
  - `get_stats(unit) -> RefCounted`
  - `get_buffs(unit) -> RefCounted`

> Demo 会提供一个 `demo_unit.gd`，以方式 1 满足契约。

### 3.2 omni_buff_adapter 与 OmniBuff 的稳定入口

本项目已启用 `OmniBuff` 插件，并在 `project.godot` 中存在 Autoload `OmniBuff`。

技能系统将通过以下入口集成（来自 `addons/omnibuff/docs/api.md`）：
- Buff：
  - `OmniBuff.BuffCore.apply_buff(stats, buff_id_str, source_entity_id) -> int`
  - `OmniBuff.BuffCore.remove_by_buff_id(stats, buff_id_str, scope="ALL", source_entity_id=-1, include_implicit=false, force=false) -> int`
  - `OmniBuff.BuffCore.emit_event(event_type, phase, ctx)`（用于 LIFE/自定义事件）
- 伤害流水线（本项目口径：**推荐并默认启用**）：
  - 优先：`OmniBuff.DamagePipeline.deal_damage(...)`（你偏好的“新接口”）
  - 兼容兜底：`OmniBuff.DamagePipeline.deal_damage_v1(...)`（旧签名兼容层；当 `deal_damage` 签名变更或缺失时使用）

**omnibuff runtime dict 契约**（Integrator Guide 强调）：
```gdscript
runtime = {
  "stats_by_entity": { eid: OmniBuff.StatsComponent },
  "buff_by_entity":  { eid: OmniBuff.BuffCore }
}
```
技能系统需要该 `runtime` 以便 Omnibuff 事件动作（APPLY_BUFF / DISPEL / ADD_STACKS 等）能按 entity_id 定位对象。

---

## 4. 数据协议：技能 JSON（权威）

> 兼容基线：本插件的“主动技能（active）字段集”将**参考并兼容** `res://data/rpg_tests/skill_defs.json` 中的字段命名与语义（在此基础上扩展 3×3 站位 targeting、公式、被动/光环等能力）。
>
> 你已确认：**active 的效果容器采用方式 A：`on_cast` / `on_hit`**（而不是统一 `effects[]`）。因此：
> - active：以 `on_cast`/`on_hit` 为权威字段；
> - passive：以 `triggers[].effects` 为权威字段；
> - aura：以 `aura.on_enter`/`aura.on_exit` 为权威字段。

### 4.1 文件组织（必须）

```
addons/turn_skill_system/data/skills/
  active/*.json
  passive/*.json
  aura/*.json
  index.json
```

### 4.2 顶层字段（最小集合）

所有 key 使用 `lower_snake_case`。

| 字段 | 类型 | 必须 | 说明 |
|---|---:|---:|---|
| `version` | int | ✅ | 数据版本；用于向后兼容 |
| `id` | string | ✅ | 全局唯一，建议 `act_`/`pas_`/`aur_` 前缀 |
| `type` | string | ✅ | `active \| passive \| aura` |
| `name` | string | ✅ | 展示名 |
| `desc` | string |  | 描述 |
| `tags` | array[string] |  | 标签（用于筛选/行为） |
| `targeting` | object | ✅（active/aura） | 选目标规则（含 `needs_primary`/`primary_role`） |
| `on_cast` | array[object] | ✅（active） | 施放时执行一次的效果列表（active 权威字段） |
| `on_hit` | array[object] | ✅（active） | 对每个目标、每段命中执行的效果列表（active 权威字段） |
| `triggers` | array[object] | ✅（passive） | 触发器列表（事件+条件+概率/冷却） |
| `aura` | object | ✅（aura） | 光环范围定义+进入/离开效果 |
| `meta` | object |  | 预留：作者/来源/图标/冷却等；unknown fields 也允许 |

### 4.2.1 Active（参考 rpg_tests/skill_defs.json 的字段基线）

`res://data/rpg_tests/skill_defs.json` 的每条技能包含：
- `id`, `name`, `damage_type`, `element`, `tags`
- `base_damage`（float，旧用法中常为 0）
- `hit_count`（可选，默认 1）
- `hit_base_damage`（可选，长度 = hit_count）
- `targeting`（字符串枚举，如 `"FIRST"` / `"ALL"`）
- `on_cast`（Array）
- `on_hit`（Array）

本插件对 active 的扩展策略：
1) **保留字段名**：以上字段在 active 技能 JSON 中都将被支持（即使我们拆成“每技能一个 JSON 文件”）。
2) **扩展 `targeting`**：在保留字符串写法的基础上，新增对象写法以支持 3×3 站位与形状选取（见 4.3）。
3) **扩展多段/多目标**：
   - `hit_count` + `hit_base_damage` 用于描述多段伤害；每段可为 number（常量）或 string（公式）。
   - `on_hit` 中的 effects 将在“每段命中 / 每个目标”上执行（具体循环次序见 11.4）。
4) **扩展 effect 容器**：
   - `on_cast`: Array[effect]（施放时一次性执行）
   - `on_hit`: Array[effect]（对每个目标、每段命中执行）
   - （可选兼容）`effects`: Array[effect]（仅用于迁移旧数据/旧工具；编辑器可提供“一键迁移：effects -> on_cast”）

### 4.3 `targeting` 结构（统一）

本插件支持两种写法：

**A) 字符串写法（兼容 rpg_tests）**
```jsonc
"targeting": "FIRST" // 或 "ALL"
```

解析规则（active）：
- `FIRST`：等价于 `{"needs_primary": false, "primary_role":"target", "rule":"first_enemy", "params":{}}`
- `ALL`：等价于 `{"needs_primary": false, "primary_role":"target", "rule":"all_enemies", "params":{}}`

**B) 对象写法（扩展能力，推荐）**
```jsonc
"targeting": {
  "needs_primary": true,
  "primary_role": "cell",   // "target" | "cell"
  "rule": "cross",          // 规则名（可扩展注册）
  "params": { "camp": "enemy" }
}
```

约定：
- `primary_cell` 为空时：若 `needs_primary=false`，规则需自行选目标（如“敌方随机 3 个”）；若 `needs_primary=true`，则 cast 返回 error。
- `primary_role` 用于编辑器提示与校验：
  - `"cell"`：primary_cell 代表中心格/起点格（用于形状）
  - `"target"`：primary_cell 代表“主目标所在格”（用于单体）

### 4.4 `effects[]`（可扩展）

```jsonc
{
  "kind": "damage",    // 统一 lower_snake_case，可注册扩展
  "params": { ... }    // 各 kind 自己定义
}
```

首批内置 kind（最小可跑 demo）：
- `damage`：伤害（**必须走 OmniBuff DamagePipeline**；simulate 模式只做预测不落地）
  - `amount` / `amount_expr` 二选一：
    - `amount: number`：常量（用于兼容 `hit_base_damage`）
    - `amount_expr: string`：公式（如 `50 + a.ATK * 1.2`）
  - `rounding: "floor"|"round"|"ceil"`
  - `damage_type: string|int`（可选，若走 omnibuff）
  - `element: string|int`（可选）
  - `tags: array[string]`（可选，映射为 tags_mask）
- `heal`：治疗（先做最小实现：直接加 HP；后续可纳入 omnibuff pipeline）
  - `amount_expr: string`
  - `rounding`
- `apply_buff`：施加 Buff（必须走 OmniBuff）
  - `buff_id: string`
  - `scope: "target"|"caster"`（默认 target）
  - `source: "caster"|"target"|int`（默认 caster.entity_id）
- `remove_buff`：移除 Buff（必须走 OmniBuff）
  - `buff_id: string`
  - `scope: "target"|"caster"`（默认 target）
  - `remove_scope: "ALL"|"FIRST"`
  - `by_source: bool`（可选：只移除来自 caster 的实例）

### 4.5 `triggers[]`（passive）

```jsonc
{
  "event": "turn_started",
  "phase": "pre",                 // 可选：pre/post
  "chance": 1.0,                  // 0..1
  "cooldown_turns": 0,            // 可选
  "conditions": [ { ... } ],      // 可选
  "effects": [ { "kind": "...", "params": {...} } ]
}
```

触发器语义：
- passive 技能绑定在“拥有者单位”（owner）身上；
- 当 `BattleEventBus` 派发匹配的事件时，评估条件与概率，执行 `effects`（effects 与 active 共用同一套 effect handlers）。

### 4.6 `aura`（aura）

```jsonc
{
  "range": { "rule": "front_row", "params": {"camp": "ally"} },
  "apply_to": "units_in_range",   // 预留
  "on_enter": [ { "kind": "apply_buff", "params": {...} } ],
  "on_exit":  [ { "kind": "remove_buff", "params": {...} } ]
}
```

光环语义（最小实现）：
- 由 `AuraManager`（运行时模块）维护：每个 aura owner 的“当前影响集合”；
- 当网格/单位变化（进入/离开/死亡/移动）时，计算差集：
  - 进入范围：对目标执行 `on_enter`（通常 apply_buff）
  - 离开范围：对目标执行 `on_exit`（通常 remove_buff）
- 模拟模式下：不真实 apply/remove，只返回 predicted_deltas。

---

## 5. `index.json`（索引协议）与缓存策略

### 5.1 index 格式（必须包含字段）

`addons/turn_skill_system/data/skills/index.json`：
```jsonc
{
  "version": 1,
  "generated_at_unix": 1710000000,
  "skills": [
    {
      "id": "act_fireball_single",
      "type": "active",
      "path": "res://addons/turn_skill_system/data/skills/active/act_fireball_single.json",
      "name": "火球术",
      "tags": ["magic", "fire"],
      "mtime_unix": 1710000000
    }
  ]
}
```

### 5.2 运行时加载策略（必须）
- 启动/第一次使用：只读取 `index.json`（O(1)）。
- `SkillDB.get_skill(id)`：
  1) 查 index 取得 path + mtime；
  2) 若缓存命中且 mtime 未变 → 直接返回 cached Dictionary；
  3) 否则读 JSON，校验，放入缓存并返回；
- 提供：
  - `SkillDB.clear_cache()`
  - `SkillDB.reload_index()`
  - `SkillDB.refresh_skill(id)`（按文件重新加载）

### 5.3 index 维护策略
- Editor Dock 提供“一键生成/更新 index.json”；
- index 生成时仅扫描 `data/skills/**.json`（三类目录），读取必要字段（id/type/name/tags/version）+ 文件 mtime。

> 说明：若你未来技能量很大（>10k），可进一步把 index 生成做成增量（按 mtime/hash）；本期只需满足“避免启动时遍历全目录读取全部 JSON”。

---

## 6. JSON 读写：unknown fields 保留 + 稳定输出

### 6.1 unknown fields 保留策略
- 编辑器读取 JSON → 得到原始 Dictionary `raw`；
- UI 仅编辑“已知字段的子树”；
- 保存时：
  - 从 `raw` 拷贝一份 `out`；
  - 仅对已知字段路径写回（例如 `out["name"]=...`、`out["effects"]=...`），其余 key 保留原样；
  - 对数组元素：若是 effects/triggers 等结构化数组，编辑器需要以“元素 identity”（如 index 或内部 `id`）策略保留未知字段（推荐在每个 effect/trigger 内增加可选 `uid` 字段用于稳定识别；若不加，则默认按数组顺序保留）。

### 6.2 稳定字段顺序（手改友好）
推荐输出时按“优先字段序”排序，其余 unknown 字段按字典序输出：
1. `version,id,type,name,desc,tags,targeting,effects,triggers,aura,meta`
2. unknown keys：按字母序

> Godot 内建 `JSON.stringify(dict, "\t")` 会按插入顺序；为了稳定输出，需要一个“排序后再 stringify”的步骤（递归处理 Dictionary）。

---

## 7. 校验器（validator）规范

### 7.1 校验级别
- `strict`（默认用于运行时 cast）：关键字段缺失/类型错误 → cast 失败；
- `lenient`（用于编辑器浏览列表）：允许缺失字段但给出 issues（warning/error）；

### 7.2 错误定位格式
每条 issue 至少包含：
- `severity`: `"error"|"warning"`
- `file_path`: `"res://.../xxx.json"`
- `field_path`: JSON pointer 风格或自定义路径（如 `$.effects[0].params.amount_expr`）
- `message`

---

## 8. 事件系统（BattleEventBus）与触发模型

### 8.1 事件总线职责
- 提供统一信号/回调入口，供：
  - 表现层（播放动画/飘字）
  - 被动技能系统（PassiveManager）
  - 光环系统（AuraManager）
  - 调试/回放（日志）
- 事件不要求持久化存档（回放由上层接入）；但 `cast()` 返回结构会包含 events 数组用于回放。

> 解释：这里的“战斗事件（BattleEventBus）”指的是**技能系统对外的领域事件**（domain events）。  
> 它不是 UI 事件，也不是 OmniBuff 内部的 `event_type/phase`（DAMAGE/LIFE 等）系统，而是你战斗系统/表现层更容易消费的“统一通知流”：
> - 主动技能 cast 的各阶段（开始/结束）
> - 伤害/治疗的前后钩子（用于被动/表现）
> - 单位死亡/移动（用于光环刷新与表现）
> - 回合/行动的边界（用于被动触发）

### 8.2 事件命名（建议常量集中管理）
建议事件字符串集合（可按你项目习惯调整，但需稳定）：
- `turn_started` / `turn_ended`
- `action_started` / `action_finished`
- `skill_cast_started` / `skill_cast_finished`
- `before_damage` / `after_damage`
- `before_heal` / `after_heal`
- `unit_died` / `unit_revived`
- `unit_moved` / `grid_changed`

每个事件 data 建议包含：
- `battle_id`（可选）
- `turn_index`
- `skill_id`
- `caster_id`
- `targets`（unit_id+cell）
- `meta`（自由字段）

> 已确认口径：**使用插件默认事件名，并尽量定义完整；后续你的战斗系统以此为标准。**

### 8.3 与 omnibuff 事件的关系（重要）
- OmniBuff 内部事件是其 BuffCore 的 event_type/phase 模型（如 DAMAGE/AFTER_DEAL、LIFE/DEATH）。
- 我们的 BattleEventBus 是“技能系统对外的统一事件”；两者并不冲突。
- 推荐策略：
  - **伤害类 effect**：若走 `DamagePipeline.deal_damage`（或兜底 `deal_damage_v1`），则 Buff 的 DAMAGE 事件与动作自然发生（由 omnibuff 配置驱动）；
  - **死亡/复活**：由技能系统在检测到 HP<=0/复活时，调用 `buffs.emit_event("LIFE","DEATH", life_ctx)`（参考 integrator_guide）以触发 omnibuff LIFE 事件；
  - 同时向 BattleEventBus 派发 `unit_died` 等事件，供 passive/aura/表现层使用。

---

## 9. 3×3 Grid 与 Targeting 规则

### 9.1 Grid 数据结构（最小）
- 固定尺寸：`GRID_SIZE = 3`
- `get_unit_at(cell) -> Unit?`
- `get_units(camp, alive_only=true) -> Array[Unit]`
- `is_valid_cell(cell:Vector2i) -> bool`
- `get_row(row, camp_filter?) -> Array[Unit]`（空格过滤）
- `get_col(col, camp_filter?) -> Array[Unit]`

### 9.2 Targeting 可注册机制
在 `runtime/targeting/` 下，每个规则一个脚本，统一接口：
- `rule_id: String`（例如 `"single_cell"`, `"row"`, `"cross"`）
- `resolve_targets(skill, caster, primary_cell, grid, extra) -> Array[TargetRef]`

`TargetRef` 结构建议：
```gdscript
{ "unit": Unit, "unit_id": int, "cell": Vector2i, "role": "primary"|"secondary" }
```

### 9.3 首批内置规则（满足需求，且易扩展）
- `single_cell`：单格（优先 primary_cell；若为空且 needs_primary=false，可按 params 选择敌方最近/随机）
- `first_enemy`：兼容 `targeting="FIRST"`（无需 primary；取敌方“第一个可选目标”，具体排序由 grid 提供）
- `all_enemies` / `all_allies`：全体
- `row`：一行（params: `row_mode` = `"caster_row"|"primary_row"|0..2`，camp=`"enemy"|"ally"`）
- `col`：一列（params 同上）
- `cross`：十字（中心=primary_cell；范围=中心+上下左右；可扩展 distance）
- `square`：方块（中心=primary_cell；半径 r=1 -> 3×3；可扩展）
- `random_n`：从某阵营可选目标中随机 N 个（params: camp, n, seed_key）

### 9.4 不可选/空格/死亡处理（最小）
- Targeting 返回时自动过滤：
  - cell 无单位 → 不入 targets
  - unit `is_dead`（或 HP<=0）→ 不入 targets（除非规则 params 要求包含尸体）
- 若最终 targets 为空：
  - active：cast 返回 `ok=false` + `errors=["no_valid_targets"]`
  - aura：不报错（可为空集合）

---

## 10. 公式系统（Formula）

### 10.1 表达式引擎选择
推荐使用 Godot 内建 `Expression`，原因：
- 实现成本低，性能足够（技能释放频率可接受）；
- 错误信息可获取（parse/execute errors）。

### 10.2 安全性约束（必须写清）
Expression 在 Godot 中可调用函数/访问对象属性；为避免注入，采取：
- 只向 Expression 暴露纯数据 Dictionary（例如 `a={"ATK":100,"HP":...}`），不暴露真实对象引用；
- 不提供自定义函数（或仅提供白名单函数，如 `min/max/clamp/rand_range` 等）。

### 10.3 变量追踪（用于 resolved_formulas）
实现策略：
- 公式字符串支持 `a.ATK`/`t.DEF` 语法；
- 在 evaluate 前，先用正则抓取变量 token（如 `a\\.([A-Z_]+)`），从上下文里取值，生成 `vars` 映射；
- 将表达式转换为 Expression 可识别的变量名（如把 `a.ATK` 映射为 `a_ATK`），并以 `Expression.execute({ "a_ATK": 100, ...})` 执行；
- 返回：
```jsonc
{"expr":"50+a.ATK*1.2","vars":{"a.ATK":100},"result":170}
```

### 10.4 取整策略
每个 effect 可指定 `rounding`，**默认 `floor`**（已确认口径）。

---

## 11. SkillRuntime：cast / simulate_cast 的结算流程

### 11.1 `cast()` 高层步骤（与你的强约束对齐）
1) `SkillDB.get_skill(skill_id)`：index + lazy load + cache  
2) `SkillValidator.validate(skill)`：字段合法、施放条件（扩展点）  
3) `Targeting.resolve_targets(...)`：结合 `primary_cell` 推导目标集合  
4) `Context`：为每个 target 构建上下文（`a`、`t`、grid/battle/turn/runtime 等）  
5) `Formula.eval(...)`：求值（含报错与追踪）  
6) `Effects.apply(...)`：按 `effects[]` 逐条执行  
   - Buff 相关 → `OmniBuffAdapter`  
   - Damage 推荐 → `OmniBuffAdapter.deal_damage`（内部优先调用 `OmniBuff.DamagePipeline.deal_damage`；必要时兜底到 `deal_damage_v1`）  
7) `BattleEventBus.emit(...)`：派发统一事件（并把 events 写入返回结构）  

### 11.4 Active 的多段/多目标执行顺序（兼容 hit_count/on_hit）

若技能定义了：
- `hit_count > 1` 或 `hit_base_damage`（数组）
- `on_hit`（Array[effect]）

则 active 的执行顺序定义为（稳定，便于回放/断言）：
1) resolve targets（得到 targets[]，稳定排序）
2) 执行 `on_cast`（或 `effects` 别名）一次
3) 对每个目标 target in targets：
   - for hit_index in [0..hit_count-1]：
     - 计算该段 base_damage：
       - 若 `hit_base_damage[hit_index]` 为 number → 直接用
       - 若为 string → 当作公式求值
       - 若缺失 → 退化使用 `base_damage`（number）或 `base_damage_expr`（若未来增加）
     - 执行 `on_hit` 中的 effects（其中的 `damage` effect 可选择使用该段 base_damage 覆盖其 amount/amount_expr）

> 注：如果你希望“按段先遍历所有目标再进入下一段”（hit-major vs target-major），可以在 Phase 0 决策中确认；默认采用 **target-major**（更贴近多数 RPG 的“每个目标连续挨多段”表现）。
### 11.2 `simulate_cast()` 规则
- 不修改 HP/属性；
- 不真实 apply/remove buff；
- 不推进回合；
- 仍会跑 targeting+formula，产生 `predicted_deltas`：
  - 预计对每个目标造成多少伤害/治疗
  - 预计施加/移除哪些 buff（仅描述）
- 对 omnibuff：
  - `simulate_apply_buff` 返回描述（如 `{buff_id, target_id, source_id}`）
  - 若未来需要更精确，可扩展为“克隆 stats/buffs 实例在沙盒里跑”，但本期不做。

### 11.3 `cast()` 返回结构（固定字段）
与用户要求一致：
```jsonc
{
  "ok": true,
  "simulation": false,
  "skill_id": "act_xxx",
  "caster_id": 101,
  "targets": [ {"unit_id":202,"cell":[0,1]} ],
  "effects": [ {"kind":"damage","value":170,"meta":{}} ],
  "resolved_formulas": [ {"expr":"...","vars":{...},"result":170} ],
  "events": [ {"type":"skill_cast_finished","data":{...}} ],
  "rng_seed": 12345,
  "errors": []
}
```

---

## 12. 编辑器 Dock（SkillEditorDock）需求拆解

### 12.1 功能列表（必须）
- 浏览/搜索技能：
  - 过滤：type（active/passive/aura）、name contains、tag contains
  - 列表展示：name/id/type/tags + 校验状态
- 新建技能：
  - 选择 type → 生成最小模板 → 输入 id/name → 保存到对应目录
- 编辑 JSON（保留 unknown）：
  - 基础信息：name/desc/tags/version
  - targeting（rule + params）
  - effects（数组编辑）
  - passive triggers / aura（专用区块）
- 一键生成/更新 index.json
- “预览/测试”按钮：
  - 构造一个简化 battle context（demo grid + demo units 或临时 mock）
  - 调用 `SkillRuntime.simulate_cast(...)`
  - 输出：选到的目标、将要应用的 effects、将要调用的 buff（打印到 Output 面板 + Dock 内文本框）

### 12.2 UI 取舍（保证可实现）
为降低复杂度：
- 首版 effects/params 用 `TextEdit` 直接编辑 JSON 子树（一个 effect 一段 json），保存前校验；
- 或用 `Tree` + 动态表单，但成本更高；

建议：**首版使用半结构化编辑**：
- 左侧列表 + 搜索
- 右侧：
  - 基础字段用 LineEdit/OptionButton
  - `targeting.params` / 每个 `effect.params` 使用 JSON TextEdit（可折叠）
  - Dock 内提供“格式化/校验/保存”按钮

这样能最快满足 “unknown fields 保留” 与 “手改友好” 的约束。

---

## 13. Demo（最小可运行验证）

### 13.1 Demo 目标
- 2~4 个单位放入 3×3；
- 演示：
  1) 主动单体伤害（带公式）
  2) 主动 AoE（行/十字/列之一，带公式）
  3) 被动或光环：通过 omnibuff 施加 buff（触发/进入离开范围）

### 13.2 omnibuff 数据集选择
项目已有 `res://data/base_demo/manifest.json` 与 `res://data/rpg_tests/manifest.json`。
Demo 推荐使用 `base_demo`（更轻），并在 demo 脚本里：
- `result := OmniBuff.ManifestLoader.load_dataset_full(manifest_path, true)`
- `enums_rt := OmniBuff.EnumsRuntime.from_enums_json(result.enums)`
- `ds := OmniBuff.DatasetCompiler.compile(result.manifest, enums_rt, result.sources)`

> Demo 的 buff_id 需与该数据集中的 `buff_defs.json` 对齐（例如 `buff_atk_flat_20` 等）。

---

## 14. 扩展点总览（你未来会改哪里）

### 14.1 新增 Targeting 规则
- 新建 `addons/turn_skill_system/runtime/targeting/<rule>_targeting.gd`
- 实现 `resolve_targets(...)`
- 在 `TargetingRegistry` 注册 `rule_id -> script`

### 14.2 新增 Effect kind
- 新建 `runtime/effects/<kind>_effect.gd`（或集中在 `effect_registry.gd`）
- 实现：
  - `apply(effect, context, simulation=false) -> EffectResult`
- 注册 `kind -> handler`

### 14.3 新增 Condition/Trigger
- condition 建议也做成 registry：
  - `kind: "has_tag"|"hp_below"|"chance"|"stat_compare"|...`
- trigger 事件来源统一来自 BattleEventBus（或与 omnibuff 事件桥接）

---

## 15. 未决决策点（需要你确认）

已确认（无未决项）：
1) **事件命名**：使用插件默认事件名，并尽量定义完整；后续你的战斗系统以此为标准。
2) **Unit 契约**：字段方式（`entity_id/camp/cell/stats/buffs`）。
