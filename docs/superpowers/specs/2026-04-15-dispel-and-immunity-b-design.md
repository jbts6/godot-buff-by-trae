# B. 驱散与免疫（可控性）设计（B1-B6）

## 目标

把 B（驱散与免疫）做成“可控 + 可回归”的一组能力。**你的标准：没有单独 test 就算未完成**，因此本轮以“补齐单测覆盖”为核心。

涵盖条目：
- **B1** 驱散按 Tag
- **B2** 驱散按来源
- **B3** 驱散按类型
- **B4** 不可驱散（undispellable）
- **B5** 驱散免疫
- **B6** 驱散会清理 DOT

---

## 现状结论（作为设计输入）

- 运行时已经有 `dispel_by_tag/source/type` 与 `target_dispel_immunity_mask`、`inst.undispellable`
- 但多数仅被“整回合脚本集成测试”间接覆盖；**缺少专门的单测**
- 数据层目前没有任何 `"dispel": {"dispellable": false}` 的样例，导致 B4 实际上没被走到

---

## 关键语义约定（本轮定死）

### 1) include_implicit 默认语义

`include_implicit=false`（默认）时：
- 不驱散 `IMPLICIT` 与 `PASSIVE`

这是为了避免把装备/套装/被动这种“系统固有能力”当成战斗驱散目标。

### 2) undispellable（不可驱散）

若 buff_def 配置：

```json
"dispel": { "dispellable": false }
```

则：
- 任意 `dispel_*` 都不得移除该实例
- `remove_*` 在 `force=true` 时仍可移除（系统清理）

### 3) 驱散免疫范围（按你确认）

`target_dispel_immunity_mask` 影响 **全部** `dispel_*`：
- `dispel_by_tag`
- `dispel_by_source`
- `dispel_by_type`

语义：
- 若本次驱散的“目标集合”与免疫有交集，则该驱散**不生效**（返回 0）

其中，“本次驱散的目标集合”定义为：
- by_tag：请求 tag 对应的 tag_mask
- by_source：使用通用 mask `"DISPEL_ALL"`（本轮最小实现：直接认为可被免疫拦截）
- by_type：同上（使用通用 mask）

> 解释：tag 驱散可以精确描述；source/type 驱散没有单一 tag 可映射，因此本轮以“免疫就拦截全部”做最小一致语义。后续可扩展更细粒度。

### 4) DOT 清理

当某 DOT buff 实例被驱散/移除时：
- 必须清理其 DotInstance（按 owner_buff_inst_id 对应关系）
- 后续 TurnStart 不再产生 DotTrace，且 HP 不再变化

---

## 测试策略（专门单测，拆分覆盖 B1-B6）

新增 4 个测试文件（都放 `addons/omnibuff/tests/rpg/`）：

1) `test_dispel_by_tag.gd`（B1 + B6 + include_implicit）
2) `test_dispel_by_source.gd`（B2）
3) `test_dispel_by_type.gd`（B3）
4) `test_undispellable_and_immunity.gd`（B4 + B5）

并在 `data/rpg_tests/buff_defs.json` 新增最小测试 buff：
- `buff_dispel_undispellable_atk_10`（EXPLICIT，dispel.dispellable=false）
- `buff_dispel_implicit_atk_10`（IMPLICIT，可用于 include_implicit 行为测试）
- `buff_dispel_passive_atk_10`（PASSIVE，可用于 include_implicit 行为测试）
- `buff_dispel_source_mark`（EXPLICIT，BY_SOURCE_INSTANCE，方便构造“同 buff_id 不同来源”实例）

---

## 验收标准

- 以上 4 个单测文件全绿
- `target_dispel_immunity_mask` 在 3 个 dispel API 上语义一致
- 数据集中存在 undispellable 配置且被测试覆盖

