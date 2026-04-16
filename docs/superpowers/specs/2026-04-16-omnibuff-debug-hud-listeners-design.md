# OmniBuff Debug HUD：Listeners 面板设计（Phase 0 / Demo-only）

## 背景

当前 Debug HUD 已有 Stats/Buffs/Dots，并统一了 DOT 生命周期口径（DotInstance 权威）。Phase 0 的下一个高价值能力是：在 HUD 中直接看到 **“有哪些事件监听者（listeners）会在什么条件下触发、做什么动作”**，以及最近一次事件触发命中了哪些 buff inst。

目标是把“为什么触发/为什么没触发”从读代码变成看 HUD。

---

## 目标

在 `debug_hud.tscn/.gd` 中新增 **Listeners** 面板：

1) 顶部显示 `last_triggered_inst_ids`（来自 `BuffCore.get_triggered_inst_ids_last_emit()`）
2) 下面按 **event_type / event_phase** 分组列出 listener 列表（仅显示当前选中 entity 的 BuffCore listeners）
3) 每个 listener 行展示：
   - `inst_id`（所属 buff 实例）
   - `buff_id`（反查 ds.buff_defs）
   - `scope`
   - `filters` 摘要（tag_mask_any / require_hit / stat_threshold）
   - `action` 摘要（ADD_BASE_DAMAGE / APPLY_BUFF(+add_stacks) / CHANCE_APPLY_BUFF / SET_STAT_FINAL / DOT_*）

---

## 非目标（Phase 0）

- 不做交互式筛选器（搜索/折叠/高亮命中）——只读展示即可
- 不做跨实体聚合（不显示“全场 listeners”），只看当前选中实体
- 不把每个 listener 的命中原因/失败原因做逐项评估（后续 Phase 1 可做）

---

## 数据来源与可行性评估

现状：
- `OmniBuffCore.event_index` 存在（类型：`OmniEventIndex`）
- `OmniEventIndex.listener_data` 存所有 Listener
- `OmniEventIndex.listeners[key]` 存 listener_id 列表（按 event_type/phase 编码后的 key）
- `OmniEventIndex.Listener` 已包含：
  - key、inst_id、active、filter_tag_mask、filter_require_hit、filter_stat_*、action_*、scope
- `OmniBuffCore.get_triggered_inst_ids_last_emit()` 可拿最近触发 inst_id 列表

因此无需改运行时结构，只需要 HUD 读取并格式化展示即可。

---

## UI 结构

在 `debug_hud.tscn` 的 `TabContainer` 中新增一个 Tab：

- `Listeners`（ScrollContainer）
  - `ListenersBox`（RichTextLabel，selection_enabled=true）

输出为纯文本分组（方便复制/截图），格式示例：

```
[LastTriggered] inst_ids=[12, 15]

[Listeners] entity_id=9001
== DAMAGE / AFTER_DEAL ==
- inst=12 buff=buff_on_hit_apply_dot scope=TARGET filters=tag_any=[BUFF],require_hit=true action=APPLY_BUFF(buff_dot_fire_3t, add_stacks=2)
- inst=13 buff=buff_test_before_deal_plus5 scope=SELF filters=tag_any=[BUFF] action=ADD_BASE_DAMAGE(+5)

== DAMAGE / BEFORE_TAKE ==
- inst=21 buff=buff_shield_50 scope=SELF filters=... action=SET_STAT_FINAL(SHIELD=0)
```

---

## 字段格式化规则（重点：可读）

### 1) event_type / phase
- 从 enums_rt 做 int->string 的反查（若没有反查接口，则至少打印 key 和 phase int）
- Phase 0 若缺反查：可以打印 `key=<et*PHASE_COUNT+ph>`，并在注释说明

### 2) filter_tag_mask
- 若 ds/enums_rt 可用：把 mask 转回 tags 数组（若无接口则打印十六进制 mask）

### 3) inst_id -> buff_id
- 用 `buffs.instances_by_id[inst_id].buff_def_id` 反查 `ds.buff_defs[*].id`

### 4) action 摘要
- APPLY_BUFF/CHANCE_APPLY_BUFF：`buff_id` + `add_stacks`
- SET_STAT_FINAL：`stat` + `value`
- DOT_*：`dot_buff_id` / `dot_tag_mask_any` / `value`

---

## 验收标准

- [ ] HUD 新增 Listeners Tab，切换 entity 会更新内容
- [ ] 能看到 last_triggered_inst_ids（即使为空也显示）
- [ ] 至少能列出 DAMAGE 相关 listeners，并包含 inst_id/buff_id/scope/action 摘要
- [ ] 文本可选中复制（用于 issue）

