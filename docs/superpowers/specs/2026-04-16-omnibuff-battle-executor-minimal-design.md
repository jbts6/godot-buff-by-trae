# OmniBuff：回合制 BattleExecutor（最小可用版）设计

## 背景与问题

目前我们已经有：
- `COMMAND` 事件域（CMD_BEFORE/CMD_AFTER）+ `CANCEL_COMMAND`
- `DAMAGE` 事件域 + DamagePipeline（可处理命中/暴击/护盾/减伤/DOT）
- `OmniReplay`（能记录命令/伤害/DOT 的追帧）

但还缺一个“把回合制指令真正执行起来”的桥接层：
- 根据 `OmniCommandContext.command_kind` 执行攻击/施法/用道具/防御/逃跑
- 在执行前后触发 `COMMAND` 事件（让 buff 可以加成、阻止、追加效果）
- 对攻击/技能造成的伤害调用 `DamagePipeline.deal_damage`
- 在必要时记录 replay 的命令流（最小可用，只覆盖 skill）

本设计提供一个 **Demo/Test 级别的 BattleExecutor**：重点是“串联事件域”，而不是完整游戏框架。

---

## 目标（最小可用）

实现 `OmniBattleExecutor`，支持：

1) `ATTACK` / `CAST_SKILL`
- 统一当作“技能执行”（技能数据从 `sources.skill_defs` 获取，不进 CompiledDataset，保持最小侵入）
- 单目标（targets[0]）
- 单段伤害（base_damage 来自 skill_defs.base_damage；若缺省则使用常量 10 作为 demo 默认）
- `tags_mask` 由 skill_defs.tags 转换而来（包含 BASIC_ATTACK 时用于普攻加成/触发器）
- 触发流程：
  - actor buffs：COMMAND/CMD_BEFORE（可 cancel）
  - 若未 cancel：调用 deal_damage（skill_id/damage_type/element/tags_mask）
  - actor buffs：COMMAND/CMD_AFTER

2) `USE_ITEM`
- 单目标（targets[0]，默认 SELF）
- 仅支持两种道具效果（用于验证事件链）：
  - `item_heal_small`：HEAL +30
  - `item_shield_small`：ADD_SHIELD +50
- 触发流程：
  - actor buffs：COMMAND/CMD_BEFORE（可 cancel）
  - 若未 cancel：直接修改 stats（HP/SHIELD），并允许 `COMMAND/CMD_AFTER` 触发额外效果

3) `DEFEND`
- 给自己挂一个可配置的 buff（例如 `buff_defend_1t`，由 rpg_tests/buff_defs 提供）
- 触发 COMMAND before/after；可被 cancel

4) `ESCAPE`
- 若未被 cancel：返回一个 `ExecuteResult.escaped=true`
- 若被 cancel：escaped=false

---

## 非目标

- 不做多段/多目标（后续版本做，当前保持最小可用）
- 不引入 item_defs 的完整数据集编译（先用字符串常量映射）
- 不将 skill_defs 编译进 `OmniCompiledDataset`（当前 compiler 只编译 stat/buff；本轮不扩大范围）

---

## API 设计

新增文件：`addons/omnibuff/runtime/core/battle_executor.gd`

### 类型

```gdscript
class_name OmniBattleExecutor
extends RefCounted

class ExecuteResult:
    extends RefCounted
    var canceled: bool = false
    var escaped: bool = false
    var last_damage_ctx: RefCounted = null
```

### 方法

```gdscript
func execute_command(
    turn_index: int,
    ctx: OmniCommandContext,
    runtime: Dictionary,
    ds: OmniCompiledDataset,
    enums_rt: OmniEnumsRuntime,
    pipeline: OmniDamagePipeline,
    replay: RefCounted = null
) -> ExecuteResult:
    pass
```

约定：
- `runtime` 与现有一致：`{stats_by_entity, buff_by_entity}`
- `ctx.set_meta("runtime", runtime)` 由 executor 内部负责补齐（以便 actions 能读到）
- `roll_key`：最小可用阶段固定为 0（后续多段/多目标再扩展为递增）

---

## 技能数据读取（最小侵入）

`OmniCompiledDataset` 当前不含 skill_defs。为了最小实现：
- executor 在执行时直接从 `runtime.get("sources", {})["skill_defs"]` 或从调用方传入的 `skill_sources` 读取
- 但为了不改变 runtime 结构，推荐：**在 execute_command 参数中直接传入 `skill_sources: Dictionary`**

考虑到现有测试加载路径 `OmniManifestLoader.load_dataset_full` 已能拿到 `sources`：
- tests/demo 可以把 `loaded.result.sources` 传给 executor 作为 `sources`

本轮规范：
- `sources["skill_defs"]["skills"]` 为 Array[Dictionary]
- skill 查找方式：按 `id` 字符串匹配

---

## 测试与 Demo（验收）

### 新测试：`test_battle_executor_minimal.gd`

覆盖：
1) BASIC_ATTACK 普攻加成链路：
   - 准备：攻击者挂 `buff_basic_attack_add_base_5`（DAMAGE/BEFORE_DEAL + tag BASIC_ATTACK）
   - 执行：ATTACK（skill_basic_attack_1）
   - 断言：DamageContext.base_damage 被加成（或 final_damage 增加）

2) ESCAPE 可被 CANCEL_COMMAND 取消：
   - 准备：actor 挂 `buff_cmd_cancel_escape`
   - 执行：ESCAPE
   - 断言：result.canceled==true / escaped==false

3) USE_ITEM 触发 item_id filters：
   - 准备：actor 挂 `buff_cmd_use_item_mark`（item_id=2001 → APPLY_BUFF mark）
   - 执行：USE_ITEM item_id=2001
   - 断言：mark 被挂上

### Demo 场景
在 `buff_ui_demo` 增加 2 个 scenario：
- executor_attack_basic
- executor_escape_cancel

---

## 验收标准

- [ ] 新增 executor + 测试全绿
- [ ] Demo 可复现“普攻技能 → DAMAGE 事件链”与“逃跑被取消”
- [ ] 不破坏现有 Phase 1 tests

