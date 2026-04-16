# OmniBuff Demo Debug HUD 设计（Demo-only Phase 0）

## 目标

为 `buff_ui_demo` 提供一个 **Demo 专用**的调试 HUD（不接入主游戏），用于快速定位：

- 某个实体当前有哪些 Buff / DOT（来源、层数、剩余回合、active）
- Buff 注入了哪些 modifiers（影响哪些 stat）
- 该实体注册了哪些事件监听（listeners），最近一次 emit_event 命中了哪些 inst
- 能一键复制可读 dump（用于贴到 issue / IM）

**硬约束：**
1) **Demo-only**：HUD 不建立全局 entity registry；只接受 demo 传入的 `runtime`（Dictionary）
2) 不破坏现有 `OmniBuff` 运行时结构；HUD 只读 `StatsComponent`/`BuffCore` 的公开字段/调试方法
3) 低侵入：在 `buff_ui_demo` 中“可选开启”，不影响正常运行

---

## 用户体验（使用流程）

1. 打开 `res://addons/omnibuff/demo/buff_ui_demo.tscn`
2. 选择 dataset（base_demo/rpg_tests），运行任意 scenario
3. 点击“Debug HUD”按钮（或快捷键）弹出 HUD
4. 在 HUD 顶部下拉选择 entity_id（默认选 attacker/defender 或最小 id）
5. 查看 Stats/Buffs/DOT/Listeners/Replay 概要
6. 点击“复制当前实体 dump”复制到剪贴板

---

## HUD 与 Demo 的接口（Demo-only 合同）

HUD 脚本提供：

```gdscript
func set_runtime(runtime: Dictionary) -> void
func set_selected_entity(entity_id: int) -> void
func set_preferred_entities(attacker_id: int, defender_id: int) -> void # 可选：用于默认选中
func clear() -> void
```

`runtime` 约定（沿用现有 pipeline/event runtime）：

```gdscript
{
  "stats_by_entity": { int: OmniStatsComponent, ... },
  "buff_by_entity":  { int: OmniBuffCore, ... }
  # 可选：attacker_id/defender_id（方便默认选中）
}
```

> HUD 不依赖场景树中的 Node（不找 /root），只使用这个 runtime。

---

## UI 结构（Scene 组件）

文件：
- `res://addons/omnibuff/demo/debug_hud.tscn`
- `res://addons/omnibuff/demo/debug_hud.gd`

建议布局：

- 顶部 Bar：
  - OptionButton：EntitySelect（entity_id 列表）
  - Button：Copy Dump（复制 dump）
  - Button：Close（关闭）
- TabContainer（4~5 个 Tab）：
  1) **Stats**：显示常用 stat（ATK/DEF/HP/SHIELD/HIT_RATE/CRIT_RATE/EVADE…，只显示 ds 存在的）
  2) **Buffs**：实例列表（buff_id、type、tags、source_entity_id、stacks、remaining_turns、active）
  3) **DOT**：dot 实例列表（dot_buff_id、source、stacks、remaining_turns、tick_phase、tags）
  4) **Listeners**：按 event_type/phase 分组列出（scope + filters 摘要 + action 摘要）
  5) **Replay（可选）**：展示最近 N 条 damage/dot trace 的摘要（先做可选）

> MVP 可以先做 Stats + Buffs + DOT + Copy；Listeners/Replay 第二周补齐。

---

## 数据来源（如何从现有对象提取）

### Stats
- 通过 ds.stat_id("ATK") 获取 id，调用 `stats.get_final(stat_id)`。
- 对于“是否存在该 stat”，用 `ds.stat_id(name) >= 0` 判断。

### Buffs（实例）
从 `buffs.inst_ids` 遍历 `buffs.instances_by_id`，并从 `ds.buff_defs[inst.buff_def_id]` 反查 `id/tags/buff_type`。

显示字段（最低集）：
- buff_id（字符串）
- buff_type
- source_entity_id
- stacks
- remaining_turns
- active（bool）

### DOT
从 `buffs.dots_by_target[entity_id]` 读取 dot 实例数组（若存在）。
显示字段：
- dot_buff_id（反查 ds）
- source_entity_id
- stacks
- remaining_turns
- tick_phase
- tags（如果 dot 带 tags_mask_any，显示 tags）

### Listeners（Week 3）
从 `buffs.event_index` 与其内部 listeners（需要看 EventIndex 暴露接口，若无则先用 `buffs.debug_dump_*` 代替）。
最低交付：展示 `buffs.get_triggered_inst_ids_last_emit()` 的结果即可（“最近命中哪些 inst”）。

---

## 输出（Copy Dump 格式）

复制内容为纯文本（易贴到 issue）：

```
[OmniBuffDebugHUD]
entity_id=9002
stats: ATK=..., DEF=..., HP=..., SHIELD=...

buffs:
- buff_dot_fire_3t type=EXPLICIT src=9001 stacks=1 turns=2 active=true tags=[DEBUFF,DOT,FIRE]
...

dots:
- dot=buff_dot_fire_3t src=9001 stacks=2 turns=1 tick=TURN_START
...
listeners:
- DAMAGE/AFTER_DEAL scope=TARGET filters=... action=APPLY_BUFF(buff_dot_fire_3t)
...
```

并执行：
`DisplayServer.clipboard_set(dump_text)`

---

## 默认选中策略（你已认可）

entity 列表来源：`runtime.stats_by_entity.keys()`（int 升序）

默认选中：
1) 若 runtime 中存在 `attacker_id/defender_id`（或调用 `set_preferred_entities`），优先选 attacker
2) 否则选最小 entity_id

---

## 验收标准

MVP（Week1）：
- [ ] HUD 可打开/关闭
- [ ] 能从 runtime 列出 entity_id，并切换实体查看 Stats/Buffs
- [ ] “复制 dump”可复制非空文本

增强（Week2-4）：
- [ ] DOT 面板可用
- [ ] Listeners/最近触发可见
- [ ] Demo 场景一键启用 HUD（不会影响 scenario runner）

