# AOE 多目标多段攻击 + DOT（复杂回归用例）设计

## 目标

提供一个“复杂但可回归”的 GUT 用例，证明 OmniBuff 当前机制能支持：

- 同时攻击多个目标（AOE）
- 命中/暴击 **按目标独立计算**（每个 target 各自 roll）
- 多段 AOE：每一段对每个目标都会走一遍 `DamagePipeline.deal_damage`
- 每段都能挂 DOT（使用事件触发器 `AFTER_DEAL` + `scope=TARGET`）

> 这里的“AOE”不引入新系统；语义上等价于“同一技能在同一回合对多个目标各结算一次伤害”。  
> 这是多数回合制里最常见的实现方式，也与当前 pipeline 的单目标接口天然契合。

---

## 现状依据

`OmniDamagePipeline.deal_damage()` 的命中/暴击 roll seed 由 `(turn_index, attacker_id, defender_id, salt)` 组成：
- 同一段（turn_index 相同）下，不同 defender_id 会产生不同 roll
- 因此天然支持“按目标独立命中/暴击”

---

## 方案（推荐：只加测试 + 最小数据）

### 1) 新增一个仅用于测试的数据 buff（require_hit）

原因：现有 `buff_on_hit_apply_dot` 触发器没有 `require_hit`，会导致“未命中也挂 DOT”，不利于回归用例表达“命中驱动挂 DOT”的语义。

因此新增测试专用 buff：
- `id`: `buff_on_hit_apply_dot_require_hit`
- 触发器：`event_type=DAMAGE`, `event_phase=AFTER_DEAL`, `scope=TARGET`
- filters：`tag_mask_any=["BUFF"]`, `require_hit=true`
- action：`APPLY_BUFF buff_dot_fire_3t`

只用于 `data/rpg_tests`，不会影响 demo 数据集。

### 2) 新增复杂回归测试用例（AOE 多段 + per-target hit/crit + DOT）

新增 GUT（放在 `tests/rpg/`）：
- 构造 attacker + 两个 defender（A、B）
- 让 defenderA 必中：`EVADE=0`
- 让 defenderB 必闪避：`EVADE=1`（命中率用 `HIT_RATE - EVADE`，clamp 0..1）
- attacker 设置 `HIT_RATE=1`（使 A 命中率=1，B 命中率=0）
- attacker 设置 `CRIT_RATE=0.5`、`CRIT_DMG=1.0`，并在测试中用 pipeline 的 `_roll01` 公式计算期望 crit（验证“按目标独立 roll”）

执行 3 段 base_damage（12/14/18），每段对两个目标各调用一次 `deal_damage`。

断言：
- `replay.damage_traces.size == hits * targets`
- defenderA：每段 `ctx.hit==true`，且 `crit` 与测试计算一致
- defenderB：每段 `ctx.hit==false` 且 `ctx.final_damage==0`
- DOT 挂载：
  - defenderA 在 3 段后有 3 个 `buff_dot_fire_3t` 实例
  - defenderB 为 0（因为 require_hit=true）
- 推进到下一回合并 TurnStart tick：
  - dot_traces 新增条数应为 1（只有 defenderA 有 DOT，且按来源合并为 1 条）
  - trace 的 `source_entity_id==attacker_id` 且 `target_entity_id==defenderA_id`

---

## 验收标准

- 新增数据 + 新增测试全绿
- 不影响既有 tests（尤其 `test_multihit_each_hit_applies_dot.gd`）

