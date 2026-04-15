# J（性能预算与工程化）设计（最小收尾）

## 目标

把 checklist 的 J1~J3 收尾到可打勾：

- **J1 性能预算文档**：列出关键操作复杂度（施加/移除/单次伤害/每回合 tick），给出建议上限与“危险操作”列表。
- **J2 无全量遍历**：明确哪些地方禁止出现“全实体/全 buff”遍历，并用最小回归测试/断言避免引入明显回归。
- **J3 内存与对象生命周期**：DotInstance/BuffInst 的创建与清理无泄漏，至少通过“回合推进 + 驱散”测试覆盖（已有集成测试 + 本轮补一个更偏生命周期的单测）。

本轮采用你选的 **“最小收尾(推荐)”**：以文档 + 轻量回归测试/断言为主，不做严格性能 benchmark。

---

## 范围与约束

- 不引入 profiler/基准框架（后续可选）
- 不改变战斗语义
- 测试只做“数量级与不泄漏”守门，不做耗时阈值（避免不同机器波动）

---

## J1：性能预算文档（建议结构）

新增文档：`docs/superpowers/perf/omnibuff-performance-budget.md`

包含：
1) **关键数据结构规模定义**
   - `N_inst`：某实体 buff 实例数量（`BuffCore.inst_ids.size()`）
   - `N_listeners`：某实体 listeners 总数（EventIndex 的各 key 的数组长度之和）
   - `N_dot`：某实体 DOT 实例数量（`BuffCore.dots_by_target[entity].size()`）
   - `N_entities`：战斗实体数

2) **关键操作复杂度（上界）**
   - `apply_buff`：O(1) 取 ownership + O(k_mod) 注册 modifiers + O(k_trg) 注册 listeners + O(N_dot_target)（若需要合并/复用 dot）
   - `remove_by_instance`：O(k_mod + k_trg + N_dot_target + N_inst)`（目前 inst_ids rebuild 是线性）
   - `emit_event`：O(N_listeners_for_key + Σ action cost)（D1 保证不扫全 buff）
   - `deal_damage`：固定阶段流程 + 事件触发 cost（同上）
   - `tick_dots`：O(N_dot_target) + 分组聚合（按 tags_mask）

3) **建议上限（保守值）**
   - 单实体 `N_inst <= 1000`
   - 单实体 `N_dot <= 200`
   - 单 key listeners <= 2000（超过提示配置可能过宽）
   - `N_entities <= 64`（测试规模假设）

4) **禁止点清单（J2）**
   - 禁止在 `emit_event` / `deal_damage` 内遍历全实体 `buff_by_entity.keys()` 或全 buff 实例
   - 禁止在 `tick_dots` 内遍历所有 target（必须按当前 target）

---

## J2：无全量遍历（最小守门）

策略（轻量，不侵入）：
- 在关键函数顶部加注释，明确禁止点与预期复杂度（可被 code review 快速发现）
- 新增 1 个 GUT 测试作为“生命周期回归”守门：在一次回合推进 + 驱散循环后，`inst_ids` 与 `dots_by_target` 不应单调增长。

（更强的“静态扫描/断言”后续可做，但本轮不引入）

---

## J3：生命周期不泄漏（最小守门）

新增单测思路：
- 在 `rpg_tests` 数据集下：
  - 构造 attacker/defender
  - attacker 挂 `buff_on_hit_apply_dot`，对 defender 连续触发多次（产生多个 buff 实例 + dot）
  - 多次循环：`TurnEnd` -> `TurnStart` -> `dispel_by_tag(DEBUFF)`（或 remove_by_tag）
- 断言循环结束后：
  - defender `inst_ids.size()` 不随循环累计增长（应回到 0 或稳定区间）
  - defender `dots_by_target[defender].size()` 不随循环累计增长（应回到 0 或稳定区间）

---

## 验收标准

- 新增 J1 文档完成并提交
- 新增 J3 生命周期回归测试通过并提交
- checklist：J1~J3 标为完成并提交

