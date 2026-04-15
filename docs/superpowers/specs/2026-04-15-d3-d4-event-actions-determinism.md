# D3/D4 收尾设计：补齐 action 测试 + 概率可复盘测试

## 目标

把 checklist 中 D3/D4 收尾到可打勾（满足“必须有测试覆盖”的门槛）：

- **D3 action 完整**：`ADD_BASE_DAMAGE / APPLY_BUFF / CHANCE_APPLY_BUFF` 三者都有专门用例覆盖  
- **D4 概率可复盘**：事件概率（CHANCE_APPLY_BUFF）与命中/暴击概率（DamagePipeline）都能在“同输入同输出”下稳定复盘

## 约束

- 不改变现有运行时语义（目前实现已确定性），只补齐 fixtures + tests
- 测试使用 `data/rpg_tests` 数据集，不污染 base_demo

## 设计要点

### 1) ADD_BASE_DAMAGE 测试

新增一个 trigger buff fixture（挂在 attacker 身上，DAMAGE/BEFORE_DEAL）：
- `action.kind = ADD_BASE_DAMAGE`
- `action.value = +5`

测试断言：
- 在固定 ATK/DEF=0 且 base_damage=10 的情况下，最终 `ctx.base_damage==15` 且 `ctx.final_damage==15`

### 2) CHANCE_APPLY_BUFF + 可复盘

新增一个 chance 触发 buff fixture（挂在 attacker 身上，DAMAGE/AFTER_DEAL）：
- `action.kind = CHANCE_APPLY_BUFF`
- `chance = 0.5`（非 0/1，确保走随机路径）
- `buff_id = buff_dot_fire_3t`（验证是否施加成功即可）

测试断言：
- “同输入同输出”：同 turn_index + 同 attacker_id/defender_id + 同 inst_id → 结果一致
- 用 `_event_seed + _roll01` 在测试内计算 expected（roll < chance）来锁死行为

### 3) 命中/暴击可复盘

在 rpg_tests 下写用例：
- 设置 `HIT_RATE/EVADE/CRIT_RATE/CRIT_DMG` 为非 0/1 值
- 同 turn_index 连续调用两次 `deal_damage`，断言 `ctx.hit/ctx.crit/ctx.final_damage` 完全一致

## 验收标准

- 新增 2~3 个 GUT 用例全绿
- 更新 checklist：D3 三个子项均勾上后，D3 可标记完成；D4 可标记完成

