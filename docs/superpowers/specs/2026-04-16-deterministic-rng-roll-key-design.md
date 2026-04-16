# Deterministic RNG Roll Key（命中/暴击可回放最小增强）设计

## 背景与问题

当前命中/暴击 roll 使用确定性算法（xorshift32），seed 由：
`(turn_index, attacker_id, defender_id, salt)` 组成。

这保证了“同输入 ⇒ 同输出”，但在真实战斗里仍有两个痛点：

1) **多段/追击/反击**：如果同一回合内对同一目标多次调用 `deal_damage` 且 `turn_index` 不变，则每次 roll 都相同，导致概率行为失真（要么全暴击/全不暴击）。
2) **回放强一致**：回放必须完全复现“战斗当时的调用顺序/参数”，否则 seed 会变，出现“战斗暴击、回放没暴击”的风险（尤其在 AOE、多段、动态目标列表下）。

## 目标

以最小改动增强可回放性与概率真实性：

- 每一次“伤害结算单元”（每段、每目标、每次额外触发）都有唯一 RNG key
- 回放时可稳定复现 hit/crit，不受目标顺序/多段结构变化影响
- Trace 能解释“当时用的 key 是多少”（调试友好）

## 方案概要（最小改动）

引入 `roll_key`（或 `attack_seq`）：

1) `DamagePipeline.deal_damage` 新增参数 `roll_key:int=0`
2) seed 由 `(turn_index, roll_key, attacker_id, defender_id, salt)` 组成
3) `DamageContext.meta` 写入 `roll_key`
4) `Replay.DamageTrace` 增加 `roll_key` 字段并写入（可选但推荐）

> 兼容性：`roll_key` 默认 0，不影响现有调用；但新业务（AOE/多段）应显式传入 roll_key。

## roll_key 生成建议（业务层）

roll_key 必须在一次战斗内对每次“伤害结算单元”唯一，建议用以下组合：

- `cast_seq`：技能释放序号（每次出手 +1）
- `strike_index`：第几段（0..N-1）
- `target_index`：第几个目标（建议按 entity_id 升序后的索引）

组合方式示例：
`roll_key = (cast_seq << 16) | (strike_index << 8) | target_index`

## 验收与回归

新增 GUT 用例锁死：

- 同一回合对同一目标连续 3 段（turn_index 相同）：
  - 若 roll_key 不同，则 crit 结果可不同（不再“全同”）
  - 且 Replay 记录的 `roll_key` 与 ctx.meta 一致

不要求做性能基准；仅确保确定性与兼容性。

