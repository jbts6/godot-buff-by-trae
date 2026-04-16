# OmniBuff（Godot 4.7）— “万物皆 Buff” 的回合制 Buff/Stat/DamagePipeline

> 当前仓库状态：可运行 demo + GUT 自动化测试（包含整回合脚本式集成测试）。  
> 目标：**性能硬约束**（StatCache + EventIndex）+ **数据驱动**（manifest/enums/defs → validate → compile）+ **可回归**（GUT）。

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

启用插件后，你可以把 `OmniBuff` 当作“命名空间入口”来用，它暴露的都是 **Script 资源（preload 的类）**：

- `OmniBuff.Replay`
- `OmniBuff.DamagePipeline`
- `OmniBuff.BuffCore`
- `OmniBuff.StatsComponent`
- `OmniBuff.TurnComponent`
- `OmniBuff.ManifestLoader`
- `OmniBuff.DatasetCompiler`
- `OmniBuff.EnumsRuntime`

入口脚本：`res://addons/omnibuff/runtime/omnibuff_singleton.gd`

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
	var ctx = pipe.deal_damage(attacker, defender, buff_attacker, buff_defender, ds, 20.0, replay, 1, tags_mask, runtime)
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

### 6.2 伤害流水线（DamagePipeline）
- 固定骨架：BUILD → BEFORE_DEAL → BEFORE_TAKE → RESOLVE → APPLY → AFTER_DEAL → AFTER_TAKE
- 公式（raw）：`raw = max(0, base_damage + ATK - DEF)`
- 命中/暴击（确定性 RNG）：仅在数据集中存在 `HIT_RATE/EVADE` 时启用
- 减伤：`DMG_REDUCE`（resolve 后、apply 前生效）
- 护盾：`SHIELD` 先吸收、剩余再扣 HP

### 6.3 事件系统（EventIndex）
- `ADD_BASE_DAMAGE`
- `APPLY_BUFF`
- `CHANCE_APPLY_BUFF`
- filters：`tag_mask_any`（最小实现）

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
      stats_core.gd              # StatCache/Dirty + modifiers 聚合
      buff_core.gd               # Buff 实例、事件索引、DOT、驱散
      damage_pipeline.gd         # 固定阶段伤害骨架（护盾/减伤/命中/暴击）
      replay.gd                  # DamageTrace/DotTrace
    components/
      stats_component.gd
      turn_component.gd
  demo/
    demo_scene.tscn
    demo_runner.gd
    buff_ui_demo.tscn
    buff_ui_demo.gd
  tests/
    base/
    helpers/
    rpg/
      test_*.gd

data/
  base_demo/                     # demo 数据集
  rpg_tests/                     # 更复杂测试数据集（不污染 demo）
```

---

## 9. 常见问题（FAQ）

### Q1：为什么推荐用 `OmniBuff.Xxx`，而不是直接 `class_name Xxx`？
因为 Godot 的全局类表/缓存有时会出现“解析期不可见”的问题（尤其是切分支/CI/headless/编辑器缓存不刷新）。  
`OmniBuff` 入口通过 `preload("res://...")` 暴露 Script 资源，引用更稳定。

### Q2：为什么有些地方不建议用 `:=`？
当变量类型是 `RefCounted` 或动态对象时，Godot 4 的静态分析可能无法推断 `:=` 的结果类型，导致解析期报错。  
建议显式标注类型或直接用 `var x = ...`（不做推断约束）。

---

## Compatibility / Versioning

- Godot：以 **4.7** 为基线（headless/CI 应使用相同 major/minor）
- GUT：仓库内 vendor 到 `res://addons/gut/`（以仓库版本为准）
- Dataset `schema_version`：当前为 `1`
  - 升级策略：通过 `OmniMigrate.migrate(schema_from, schema_to, obj)` 在线迁移（不写回源文件）
- Tag codes：`tags.code` 是兼容契约（只增不复用 / 不复用旧码语义）
