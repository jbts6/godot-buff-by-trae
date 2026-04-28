# OmniBuff（Godot 4.7）— "万物皆 Buff" 的回合制 Buff/Stat/DamagePipeline

> 当前仓库状态：可运行 demo + GUT 自动化测试（包含整回合脚本式集成测试 + 压力基准测试）。
> 目标：**性能硬约束**（StatCache + EventIndex + Precompiled BuffDef）+ **数据驱动**（manifest/enums/defs → validate → compile）+ **可回归**（GUT）+ **可扩展**（Mod Override）。

## 1. 安装与启用

### 1.1 安装（拷贝插件目录）

把本目录拷贝到你的项目里：

```
res://addons/omnibuff/
```

### 1.2 启用插件（推荐）

在 Godot 编辑器中：

1. `Project → Project Settings → Plugins`
2. 找到 `OmniBuff`，勾选 **Enable**

启用后会发生两件事：

- **自动添加 Autoload 单例**：`OmniBuff`
- 禁用插件会自动移除该 Autoload（保证“启用才有全局入口、禁用则无”）

> 说明：Autoload 的安装/卸载逻辑在 `res://addons/omnibuff/omnibuff.gd`（EditorPlugin）里实现。

---

## 2. 如何在代码里调用（关键：OmniBuff 命名空间式入口）

启用插件后，你可以把 `OmniBuff` 当作"命名空间入口"来用，它暴露的都是 **Script 资源（preload 的类）**：

- `OmniBuff.Replay`
- `OmniBuff.DamagePipeline`
- `OmniBuff.BuffCore`
- `OmniBuff.StatsCore`
- `OmniBuff.StatsComponent`
- `OmniBuff.TurnComponent`
- `OmniBuff.ManifestLoader`
- `OmniBuff.DatasetCompiler`
- `OmniBuff.EnumsRuntime`
- `OmniBuff.CompiledDataset`
- `OmniBuff.BattleExecutor`
- `OmniBuff.EventIndex`
- `OmniBuff.CommandContext`
- `OmniBuff.ExprContext`
- `OmniBuff.Validate`
- `OmniBuff.Migrate`
- `OmniBuff.Json`
- `OmniBuff.Csv`

入口脚本：`res://addons/omnibuff/runtime/omnibuff_singleton.gd`

---

## 2.1 Public API / Stable API（TL;DR）

- **不要依赖 `class_name` 标识符**（例如 `OmniExprContext`），业务代码里建议用 `OmniBuff.Xxx` / preload 引用脚本，避免脚本解析时机导致编译问题。
- 伤害结算如果你更在意"插件升级兼容性"，建议优先使用：`DamagePipeline.deal_damage_v1(...)`（旧签名兼容层）。新签名 `deal_damage_v2(...)` 使用 `DamageRequest` 结构体传参，支持确定性 RNG seed。
- BONUS_DAMAGE（追加伤害）需要不递归 guard：`filters.require_not_bonus_damage=true`，并建议用 tag `BONUS_DAMAGE` 识别 bonus hit（不要依赖 trace 顺序）。
- **Mod Override**：manifest 中声明 `mods[]` 可实现数据热覆盖（`last_wins_by_id` 策略），详见 §6.8。
- **Precompiled BuffDef**：运行时使用 `ds.buff_defs_compiled[bdid]` 替代 `ds.buff_defs[bdid]` 字典查找，详见 §6.7。
- **Event Trace Hook**：`BuffCore.event_trace_fn` 可挂载 HUD 事件追踪回调，详见 §6.10。

文档导航（建议按顺序阅读）：
- Tutorial（从零理解设计原理/思想/用法）：`res://addons/omnibuff/tutorial/00_index.md`
- ModiBuff Tutorial（第三方参考 + 对比）：`res://addons/omnibuff/tutorial_modibuff/00_index.md`
- 接入主线（战斗系统如何对接）：`res://addons/omnibuff/docs/integrator_guide.md`
- 数据协议速查 + 常见配方：`res://addons/omnibuff/docs/schema_reference.md`
- 设计师配方指南（18 种配方 + 排错表）：`res://addons/omnibuff/docs/designer_guide.md`
- 调试与回归（UI demo / HUD / tests）：`res://addons/omnibuff/docs/debug_and_qa.md`
- API 契约（contract）：`res://addons/omnibuff/docs/api.md`
- 变更日志：`res://addons/omnibuff/docs/changelog.md`
- 迁移指南（版本升级 breaking changes）：`res://addons/omnibuff/docs/migration_guide.md`

---

## 3. 最小运行示例：加载数据集 → 上 Buff → 结算一次伤害

> 说明：本插件是“数据驱动”的：先加载 manifest/enums/defs，编译为只读 `CompiledDataset`，运行时只依赖编译产物。

```gdscript
# 假设：你已启用 OmniBuff 插件（项目中存在 /root/OmniBuff）

func run_one_hit() -> void:
	# 1) 加载并编译数据集（strict=true：校验失败直接阻断）
	var result := OmniBuff.ManifestLoader.load_dataset_full("res://data/base_demo/manifest.json", true)
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

	# 4) 施加 Buff（示例：装备 + 测试 before_deal 触发器）
	buff_attacker.apply_buff(attacker, "buff_equip_weapon_001", attacker.entity_id)
	buff_attacker.apply_buff(attacker, "buff_test_before_deal_plus5", attacker.entity_id)

	# 5) runtime：用于事件动作（APPLY_BUFF/CHANCE_APPLY_BUFF）定位目标实体
	var runtime := {
		"stats_by_entity": {101: attacker, 202: defender},
		"buff_by_entity": {101: buff_attacker, 202: buff_defender}
	}
	var tags_mask: int = int(enums_rt.tag_mask(["BUFF"]))

	# 6) 结算一次伤害
	var ctx = pipe.deal_damage_v1(attacker, defender, buff_attacker, buff_defender, ds, 20.0, replay, 1, tags_mask, runtime)
	print("final=", ctx.final_damage, " defender_hp=", defender.get_final(ds.stat_id("HP")))
```

---

## 4. DOT 语义（重要）：默认在 TURN_START 结算

本项目约定：**DOT 在“目标回合开始（TURN_START）”结算**。
也就是：你在 Turn2 给对方挂上 DOT，**要等到 Turn3 start** 才会第一次掉血。

运行时接口：
- `TurnComponent.on_turn_start(...)`：回合开始（会 tick DOT）
- `TurnComponent.on_turn_end(...)`：回合结束（默认不 tick DOT；仅用于推进回合/结构完整性）

示例（测试里常用写法）：

```gdscript
var ids := PackedInt32Array([attacker_id, defender_id])
ids.sort()

# TurnEnd：推进到下一回合（不 tick DOT）
turn.on_turn_end(ids, buff_by_entity, stats_by_entity, pipe, ds, replay)

# TurnStart：DOT 结算（tick）
turn.on_turn_start(ids, buff_by_entity, stats_by_entity, pipe, ds, replay)
```

---

## 5. Buff 驱散与免疫

运行时支持（最小实现）：
- `BuffCore.dispel_by_tag(stats, "DEBUFF", include_implicit=false)`
- `BuffCore.dispel_by_source(stats, source_entity_id, include_implicit=false)`
- `BuffCore.dispel_by_type(stats, "EXPLICIT")`
- `BuffCore.target_dispel_immunity_mask`：驱散免疫（bitmask）

注意：
- 默认 `include_implicit=false`：不会驱散 `IMPLICIT/PASSIVE`（符合装备/被动不应被常规驱散）。
- 驱散会同时清理该 BuffInst 对应的 **DOT 实例**（避免“驱散了 debuff 但 DOT 仍在跳”）。

---

## 6. 已实现能力（当前版本）

### 6.1 属性系统（StatsCore / StatCache）
- `ADD/FLAT`（平铺加成）
- `MUL/PERCENT`（百分比加成）
  公式：`final = (base + flat) * (1 + pct)`
- **整数比较优化**：`recompute()` 使用 `op_int`/`phase_int` 替代字符串比较（热路径零分配）
- **预编译派生属性**：`derived_from_int[]`/`derived_ratio[]` 替代运行时 `stat_id()` 查找

### 6.2 伤害流水线（DamagePipeline）
- 固定骨架：BUILD → BEFORE_DEAL → BEFORE_TAKE → RESOLVE → APPLY → AFTER_DEAL → AFTER_TAKE
- 公式（raw）：`raw = max(0, base_damage + ATK - DEF)`
- 命中/暴击（确定性 RNG）：仅在数据集中存在 `HIT_RATE/EVADE` 时启用
- 减伤：`DMG_REDUCE`（resolve 后、apply 前生效）
- 护盾：`SHIELD` 先吸收、剩余再扣 HP
- `deal_damage_v2(DamageRequest)`：结构体传参，支持确定性 RNG seed（xorshift32）

### 6.3 事件系统（EventIndex）
- `ADD_BASE_DAMAGE`
- `APPLY_BUFF`
- `CHANCE_APPLY_BUFF`
- filters（已实现）：
  - `tag_mask_any`（tags any-of）
  - `require_hit` / `require_crit`（命中/暴击门控；全阶段可用）
  - `skill_id`（全阶段可用；ctx.skill_id 默认 -1 表示未知）
  - `damage_type_any` / `element_any`（全阶段可用）
  - `require_shield_absorbed`（建议 AFTER_TAKE；依赖 ctx.meta.absorbed_shield）
  - `min_absorbed_shield`（建议 AFTER_TAKE；absorbed_shield>=阈值）
  - `min_final_damage`（建议 APPLY/AFTER_*；final_damage>=阈值）
  - `stat_threshold`（STAT 门控；依赖 runtime）

### 6.4 DOT
- DOT 运行时由 **DotInstance** 管理（独立于 BuffInst）
  - `DotInstance.remaining_turns` 才是 DOT 的权威回合数（到期递减发生在 DOT tick 中）
  - `BuffInst.remaining_turns` 仅对 **非 DOT 的 TURNS buff** 生效（DOT buff 实例本身不会按此递减）
- 按来源独立实例（每个来源最多一个 DotInstance；重复施加会叠层/刷新，取决于 stack/refresh_policy）
- 默认 TURN_START 结算
- 每跳读取来源 StatCache（证明没遍历来源 buff）
- Replay 记录 DotTrace

### 6.5 Demo（场景）

- 控制台 demo：`res://addons/omnibuff/demo/demo_scene.tscn`（输出到 Godot 的 Output）
- UI demo（推荐）：`res://addons/omnibuff/demo/buff_ui_demo.tscn`
  - 支持切换数据集：`base_demo` / `rpg_tests`
  - 以 Scenario 形式覆盖 `tests/rpg` 的主要能力点
- ScenarioRunner：`res://addons/omnibuff/demo/scenario_runner.gd`
  - 从 JSON 文件或内联 Dictionary 加载场景脚本
  - 自动执行 setup → steps → verify 流程
  - 支持 `assert_stat`、`apply_buff`、`deal_damage`、`turn_start`、`turn_end` 等步骤类型

### 6.6 调试工作流（Debug HUD — 交互增强版）

推荐工作流（适合提 issue / 远程协作定位）：

1) 打开 `buff_ui_demo.tscn`，选择 dataset（通常 `rpg_tests`），运行能复现问题的 scenario
2) 打开 **Debug HUD**（三标签页）：
   - **Stats 标签**：
     - `StatsEditArea`：SpinBox 直接编辑 stat base 值（实时生效）
     - `StatsScroll`：只读 stat 最终值展示
   - **Buffs 标签**：
     - `BuffsToolbar`：输入 buff_id 施加 / 输入 inst_id 移除
     - `BuffsScroll`：当前 buff 实例列表
   - **Timeline 标签**：
     - 事件时间线（最多 500 条），记录 entity_id、event_type、phase、hit_inst_ids
     - `BtnClearTimeline` 清空时间线
3) 点击 "复制日志" 和 "复制 dump"，将两段文本粘贴到 issue

dump 建议格式（节选，真实内容会更长）：
```
[OmniBuffDebugHUD]
[Stats] ...

[StatMods] ...

[Buffs] ...

[Dots] ...

[Listeners] ...
```

### 6.7 BuffDef 预编译（Precompiled BuffDef）

编译阶段将 `buff_defs[]`（Dictionary）转换为 `buff_defs_compiled[]`（强类型 RefCounted），运行时零字典查找：

- `BuffDefCompiled`：包含 `buff_type_int`、`tag_mask`、`duration_turns`、`undispellable` 等预计算字段
- `EffectCompiled`：包含 `op_str`/`phase_str`（缓存字符串）+ `op_int`/`phase_int`（整数比较）
- `TriggerCompiled`/`FilterCompiled`/`ActionCompiled`/`ConditionCompiled`/`DotCompiled`：同上策略

源码：`res://addons/omnibuff/runtime/core/compiled_buff_def.gd`

### 6.8 Mod Override 系统

manifest.json 中声明 `mods[]` 可实现数据热覆盖（无需修改基础数据集）：

```json
{
  "files": [...],
  "mods": [
    { "dir": "../mods/my_mod" }
  ]
}
```

- 策略：`last_wins_by_id`（同 id 的定义，后加载的覆盖先加载的）
- 冲突记录：`Result.mod_conflicts[]` 记录所有被覆盖的 id
- 支持类型：buff_defs、stat_defs、skill_defs、equipment_defs、set_bonus_defs

### 6.9 EnumsRuntime 反向查找

`EnumsRuntime.reverse_name(enum_name, int_code)` 可将运行时整数编码还原为配置层字符串：

```gdscript
var op_name: String = enums_rt.reverse_name("op_type", modifier.op_int)
```

### 6.10 Event Trace Hook

`BuffCore.event_trace_fn: Callable` 可挂载 HUD 事件追踪回调：

```gdscript
buffs.event_trace_fn = _on_event_trace.bind(entity_id)

func _on_event_trace(entity_id: int, event_type: int, phase: int, hit_inst_ids: PackedInt32Array) -> void:
    _event_traces.append({"eid": entity_id, "et": event_type, "phase": phase, "hits": hit_inst_ids})
```

- 默认为空 Callable（无开销）
- Debug HUD 使用此钩子实现 Timeline 标签页

### 6.11 性能优化摘要

| 优化项 | 方法 | 效果 |
|--------|------|------|
| StatsCore recompute | `op_int`/`phase_int` 整数比较替代字符串比较 | 热路径零分配 |
| 派生属性计算 | `derived_from_int[]`/`derived_ratio[]` 预编译数组 | 消除运行时 `stat_id()` 查找 |
| BuffDef 查找 | `buff_defs_compiled[]` 强类型替代 `buff_defs[]` Dictionary | 零字典查找 |
| ModifierRef | `op_int`/`phase_int` 缓存 | 避免热路径 `reverse_name()` |
| Dataset 指纹 | SHA-256 fingerprint 缓存失效 | 避免重复编译 |

---

## 7. 自动化测试（GUT）

### 7.1 启用 GUT

本仓库已 vendor GUT 到：
```
res://addons/gut/
```

在编辑器中启用：
`Project → Project Settings → Plugins → GUT`

### 7.2 测试目录

在 GUT 面板的 Test Directories 里添加：
```
res://addons/omnibuff/tests/base
res://addons/omnibuff/tests/rpg
```

关键用例（示例）：
- `tests/base/test_multihit_attack.gd`（基础多段）
- `tests/base/test_def_buff_reduces_damage.gd`（DEF 防守 buff）
- `tests/base/test_dot_multi_source_trace.gd`（DOT 多来源）
- `tests/rpg/*`（更复杂 RPG 机制 + 整回合脚本式集成测试）

### 7.3 Run tests (headless)

在包含 `project.godot` 的目录（即仓库根目录 `godot-buff/`）执行：

```bash
GODOT_BIN="/path/to/godot" ./run_gut_tests.sh
```

说明：
- 脚本会显式指定两次 `-gdir` 来覆盖：
  - `res://addons/omnibuff/tests/base`（基础用例）
  - `res://addons/omnibuff/tests/rpg`（rpg 大量用例）
- GUT 默认只扫描 `-gdir` 指定目录本身，不递归子目录；为避免把 `helpers/` 下的脚本当成测试扫描导致 warning，我们**不**开启 `-ginclude_subdirs`。

退出码语义（用于 CI）：
- `0`：测试全部通过（fail count = 0）
- `1`：存在失败用例或 GUT 内部错误（fail count > 0 / 运行前置检查失败等）

---

## 8. 目录结构速览

```
addons/omnibuff/
  plugin.cfg
  omnibuff.gd                    # EditorPlugin：启用/禁用时安装/卸载 Autoload OmniBuff
  runtime/
	omnibuff_singleton.gd        # Autoload 单例：OmniBuff（命名空间入口）
	core/
	  stats_core.gd              # StatCache/Dirty + modifiers 聚合（整数比较优化）
	  buff_core.gd               # Buff 实例、事件索引、DOT、驱散、event_trace_fn
	  damage_pipeline.gd         # 固定阶段伤害骨架（护盾/减伤/命中/暴击/v2 RNG）
	  replay.gd                  # DamageTrace/DotTrace
	  compiled_data.gd           # CompiledDataset（含 buff_defs_compiled/derived_from_int/derived_ratio）
	  compiled_buff_def.gd       # BuffDefCompiled/EffectCompiled/TriggerCompiled 等预编译类型
	  enums_runtime.gd           # 枚举映射 + reverse_name() 反向查找
	  battle_executor.gd         # BattleExecutor（从 ds 读取 skill 数据）
	  event_index.gd             # 事件索引
	  expr_context.gd            # 表达式求值上下文
	  command_context.gd         # 命令上下文
	  life_context.gd            # 生命周期上下文
	components/
	  stats_component.gd
	  turn_component.gd
  config/
	manifest_loader.gd           # Manifest 加载 + Mod Override（last_wins_by_id）
	parsers/
	  csv_reader.gd              # RFC 4180 CSV 解析器
	  json_reader.gd             # JSON 加载工具
	compiler/
	  dataset_compiler.gd        # 数据集编译（含 BuffDef 预编译 + 派生属性预编译）
	  validators.gd              # 数据校验（condition_type 等扩展验证）
	  migrate.gd                 # Schema 迁移
  demo/
	demo_scene.tscn
	demo_runner.gd
	buff_ui_demo.tscn
	buff_ui_demo.gd
	debug_hud.tscn               # Debug HUD（Stats/Buffs/Timeline 三标签页）
	debug_hud.gd                 # 交互式 HUD（stat 编辑/buff 施加移除/事件追踪）
	scenario_runner.gd           # Scenario 脚本执行器
  tests/
	base/
	  helpers/
	rpg/
	  test_*.gd                  # 含 test_compiled_buff_def/test_mod_override/test_stress_benchmark 等
  docs/
	integrator_guide.md
	schema_reference.md
	debug_and_qa.md
	api.md
	designer_guide.md            # 设计师配方指南（18 种配方 + 排错表）
	changelog.md                 # 变更日志
	migration_guide.md           # 迁移指南
  schemas/
	*.schema.json                # 7 个 JSON Schema（manifest/enums/buff_defs/stat_defs/skill_defs/set_bonus/damage_pipeline）

data/
  base_demo/                     # demo 数据集
  rpg_tests/                     # 更复杂测试数据集（不污染 demo）
	mods/                        # Mod Override 测试数据
	  test_mod/
	scenarios/                   # Scenario JSON 测试脚本
```

---

## 9. 常见问题（FAQ）

### Q1：为什么推荐用 `OmniBuff.Xxx`，而不是直接 `class_name Xxx`？
因为 Godot 的全局类表/缓存有时会出现"解析期不可见"的问题（尤其是切分支/CI/headless/编辑器缓存不刷新）。
`OmniBuff` 入口通过 `preload("res://...")` 暴露 Script 资源，引用更稳定。

### Q2：为什么有些地方不建议用 `:=`？
当变量类型是 `RefCounted` 或动态对象时，Godot 4 的静态分析可能无法推断 `:=` 的结果类型，导致解析期报错。
建议显式标注类型或直接用 `var x = ...`（不做推断约束）。

### Q3：如何使用 Mod Override 覆盖已有数据？
在 manifest.json 中添加 `"mods": [{"dir": "../mods/your_mod"}]`，mod 目录下的 JSON 文件会按 `last_wins_by_id` 策略合并到基础数据集。冲突记录在 `Result.mod_conflicts[]`。

### Q4：`buff_defs_compiled` 和 `buff_defs` 有什么区别？
`buff_defs[]` 是原始 Dictionary 数组（配置层格式），`buff_defs_compiled[]` 是编译阶段生成的强类型 RefCounted 数组（运行时优化格式）。推荐运行时使用 `buff_defs_compiled` 以获得更好的性能。

### Q5：如何追踪 Buff 事件？
设置 `BuffCore.event_trace_fn` 回调即可。HUD 的 Timeline 标签页就是通过此钩子实现的。回调签名：`(event_type: int, phase: int, hit_inst_ids: PackedInt32Array)`。

### Q6：`deal_damage_v1` 和 `deal_damage_v2` 有什么区别？
`v1` 是旧签名兼容层（位置参数），`v2` 使用 `DamageRequest` 结构体传参，支持确定性 RNG seed。新代码建议使用 `v2`。

---

## Compatibility / Versioning

- Godot：以 **4.7** 为基线（headless/CI 应使用相同 major/minor）
- GUT：仓库内 vendor 到 `res://addons/gut/`（以仓库版本为准）
- Dataset `schema_version`：当前为 `1`
  - 升级策略：通过 `OmniMigrate.migrate(schema_from, schema_to, obj)` 在线迁移（不写回源文件）
- Tag codes：`tags.code` 是兼容契约（只增不复用 / 不复用旧码语义）
