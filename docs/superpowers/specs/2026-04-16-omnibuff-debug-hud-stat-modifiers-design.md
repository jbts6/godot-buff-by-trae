# OmniBuff Debug HUD：Stat Modifiers 面板设计（Phase 0 / Demo-only）

## 背景与目标

Debug HUD 现已支持 Stats/Buffs/Dots/Listeners。Phase 0 的下一个高价值能力是：直接解释“某个 stat 的最终值为什么是这个数”，也就是把 `StatsCore.modifiers_by_stat[stat_id]` 里的贡献项做成可读的调试输出。

本功能以 **按 Stat 分组** 为主（你已确认），帮助排查：
- 哪些 buff/inst 在影响某个 stat
- modifier 的 op/phase/layer/priority/value 是否符合预期
- override 的裁决是否正确（priority/source_inst_id）

---

## 目标（交付内容）

在 `addons/omnibuff/demo/debug_hud.*` 增加 **StatMods** Tab：

1) 对当前选中 entity 的常用 stat（ATK/DEF/HP/SHIELD/HIT_RATE/EVADE/CRIT_RATE/CRIT_DMG/DMG_REDUCE…）逐个输出：
   - 最终值 `final`
   - base 值（若可读）
   - dirty 标记（若可读）
   - 贡献项列表（来自 `stats.core.modifiers_by_stat[stat_id]`）
2) 每个贡献项展示：
   - op / phase / value
   - layer（percent layers）
   - priority（OVERRIDE 相关）
   - source_inst_id
   - buff_id（通过 source_inst_id -> BuffCore.instances_by_id -> ds.buff_defs 反查）
3) 输出可选中复制（RichTextLabel），并纳入 Copy dump 的 `stat_mods:` 分区

---

## 非目标（Phase 0）

- 不在 HUD 中实时“重算并分解出各阶段合成后的中间值”（只展示输入项与最终值）
- 不做“按 Buff 分组”的第二视图（后续可加）
- 不做排序/筛选 UI（文本输出即可）

---

## 数据来源与依赖

已存在对象/字段：
- `OmniStatsComponent.core` -> `OmniStatsCore`
- `OmniStatsCore.modifiers_by_stat[stat_id]`：Array，元素为 `OmniModifierRef`（在 `BuffCore` 中构建）
  - 字段：`op/phase/value/layer/priority/source_inst_id`
- `OmniStatsCore.base_values / final_values / dirty`（可读）
- `OmniBuffCore.instances_by_id[inst_id]` -> `buff_def_id`
- `OmniCompiledDataset.buff_defs[buff_def_id].id`

因此 HUD 不需要引入新的运行时接口；只需要把 `runtime` 中已注入的 `ds/enums_rt` 与当前 entity 的 `stats/buffs` 连接起来。

---

## 输出格式（示例）

```
[StatMods] entity_id=9002

== ATK (id=0) ==
base=10 final=34 dirty=0
- ADD/FLAT  +10  layer=0 pri=100 inst=12 buff=buff_weapon_atk_flat_10
- MUL/PERCENT +0.10 layer=1 pri=0 inst=18 buff=buff_trinket_atk_pct_10
- OVERRIDE/FINAL 0.00 pri=900 inst=20 buff=buff_c_override_hit_0_p900

== HP (id=1) ==
...
```

排序规则建议：
- 贡献项按 `(phase, op, layer, priority, source_inst_id)` 做稳定排序
- 或者直接按 `source_inst_id` 升序（更贴近“谁注入的”）

Phase 0 推荐：**按 source_inst_id 升序**（简单且稳定）。

---

## 验收标准

- [ ] HUD 新增 StatMods Tab，并在切换 entity 时更新
- [ ] 至少能正确列出一个 stat 的 modifiers 列表（含 buff_id 反查）
- [ ] 对 DOT buff 的 modifiers（通常无）不会导致崩溃
- [ ] Copy dump 包含 `stat_mods:` 分区

