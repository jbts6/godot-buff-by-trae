# OmniBuff 性能预算（J）

## 规模符号
- N_entities：战斗实体数
- N_inst：单实体 buff 实例数（`BuffCore.inst_ids.size`）
- N_listeners：单实体 listeners 总数（`EventIndex` 各 key 列表长度之和）
- N_dot：单实体 DOT 实例数（`BuffCore.dots_by_target[entity].size`）

## 关键操作复杂度（上界）

### apply_buff（施加）
- ownership lookup：O(1)
- modifiers 注册/聚合：O(k_mod)
- listeners 注册：O(k_trg)
- DOT upsert（按来源合并）：O(N_dot)

### remove_by_instance（移除）
- modifiers 撤销：O(k_mod)
- listeners 注销：O(k_trg)
- 清理 DOT（`owner_buff_inst_id` 匹配过滤）：O(N_dot)
- inst_ids 重建：O(N_inst)

### emit_event（事件触发）
- 仅遍历 listeners 子集：O(N_listeners_for_key)
- action 成本：与 action 类型相关（`APPLY_BUFF`/`CHANCE`/`ADD_BASE_DAMAGE`/`DOT_*`）

### deal_damage（单次伤害）
- 固定阶段流程 + `emit_event` 的成本

### tick_dots（每回合 DOT 结算）
- 遍历目标 DOT：O(N_dot)
- 按 `tags_mask` 分组聚合：O(N_dot)

## 建议上限（保守值）
- N_entities <= 64
- N_inst <= 1000 / entity
- N_dot <= 200 / entity
- N_listeners_for_key <= 2000（超过建议收紧 filters，否则性能与可控性风险上升）

## 禁止点（J2）
- 禁止在 `deal_damage`/`emit_event`/`tick_dots` 内遍历全实体（`buff_by_entity.keys`/`stats_by_entity.keys`）
- 禁止在 `tick_dots` 内遍历所有 target（必须按当前 target）
