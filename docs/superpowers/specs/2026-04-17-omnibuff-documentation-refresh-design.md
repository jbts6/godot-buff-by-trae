# OmniBuff 文档完善（面向战斗系统接入）设计

## 背景

当前 OmniBuff 已覆盖 Phase 0~2 的关键能力（Stats/Buff/DamagePipeline/Event/DOT/Debug），你接下来会继续开发技能与战斗系统。为了让插件“可复用、可维护、可移交”，需要把**接入契约**与**常见配方/坑位**写成文档，避免未来只能靠读代码或问人。

现状：
- `addons/omnibuff/README.md` 已包含 Quickstart + 部分能力列表
- `addons/omnibuff/docs/api.md` 已覆盖 Dataset 链路、runtime dict、scope 等“契约型内容”
- 但仍缺：
  - Stats 面板展示口径（base/bonus/final、derived/curve）
  - Phase 1 wrap-up（LIFE/DEATH/REVIVE + ADD_STACKS/SET_STACKS）与最佳实践
  - 数据协议速查（enums/stat_defs/buff_defs）与常见配方
  - 调试与回归：buff_ui_demo / Debug HUD / ErrorList / 如何新增 scenario 对齐 tests

---

## 目标

面向“项目内战斗开发者”（你后续写技能/战斗系统）提供一套清晰的文档结构：

1) **接入主线清晰**：如何在战斗系统中接入 OmniBuff（数据集、runtime、scope、事件、DOT、回合推进）
2) **Stats 面板口径明确**：
   - 能解释并示例使用 `StatsComponent.get_breakdown(stat_id)`（base/bonus/final）
   - 解释 derived/curve 对 UI 展示的影响与推荐展示方式
3) **事件/动作可查**：
   - 覆盖 Phase 1：LIFE（DEATH/REVIVE）与 stack actions（ADD_STACKS/SET_STACKS）
   - 强调“不递归 guard”（BONUS_DAMAGE 等）
4) **数据协议速查**：提供“字段速查 + 常见配方”，让策划/程序能快速写出可用配置
5) **调试与回归流程可复制**：
   - buff_ui_demo 作为 scenario runner 的使用方式
   - Debug HUD 各面板解释
   - ErrorList 快速定位错误的工作流
   - 如何新增一个 scenario 并与 tests/rpg 对齐

---

## 非目标

- 不写成“百科全书式”的完整 API reference（后续可迭代）
- 不引入额外文档生成工具链（保持 Markdown 即可）
- 不在本轮强制补齐 Phase 3（网络/回滚等）

---

## 文档结构（最终产物）

在 `addons/omnibuff/docs/` 下新增 3 份文档，并在 `README.md`/`api.md` 中补充链接：

1) **Integrator Guide（主线）**
   - `addons/omnibuff/docs/integrator_guide.md`
   - 内容：接入最小闭环、runtime dict、scope、事件/动作、Stats 面板口径、LIFE/Stacks 的接入与触发方式

2) **Schema Reference（速查）**
   - `addons/omnibuff/docs/schema_reference.md`
   - 内容：enums/stat_defs/buff_defs 关键字段速查、常见配方（吸血/反伤/复活清 debuff/叠层控制等）

3) **Debug & QA（调试回归）**
   - `addons/omnibuff/docs/debug_and_qa.md`
   - 内容：buff_ui_demo、Debug HUD、ErrorList、日志复制、如何新增 scenario、如何跑 GUT

README 负责“入口 + 指路”，api.md 保持“契约/contract”，并在合适位置指向新文档。

---

## 关键口径（写入文档的准确定义）

### 1) Stats breakdown

`StatsComponent.get_breakdown(stat_id)` 返回：
- `base = base_values + computed_base(derived)`
- `final = 完整 pipeline（flat/pct/override/final_add/curve/clamp）后的值`
- `bonus = final - base`

建议 UI：
- 主显示 final（大字）
- 折叠/tooltip 展示 base 与 bonus
- 若曲线/DR 影响较大，bonus 会包含曲线导致的差值：这是期望行为（让“最终比基础多/少了多少”更直观）

### 2) LIFE 与 stacks actions

需要说明：
- LIFE 事件由上层战斗系统在“单位死亡/复活”时显式触发 `buffs.emit_event("LIFE","DEATH/REVIVE", life_ctx)`
- `LifeContext` 关键字段：`actor_id`（死亡/复活者）、`source_id`（击杀者/来源，可无）
- stacks actions 通过 trigger.action：
  - `ADD_STACKS {buff_id, delta, min_stack, max_stack}`
  - `SET_STACKS {buff_id, value}`

---

## 验收标准

- [ ] README 能作为“入口文档”，明确指向 3 份新文档与 api.md
- [ ] Integrator Guide 能让读者在不读源码的情况下完成接入（至少能跑通一次伤害 + 事件动作）
- [ ] Schema Reference 覆盖核心字段与常见配方；能用作写配置的速查表
- [ ] Debug & QA 能指导复现问题、定位问题、补充 scenario 与回归测试
- [ ] 文档内容覆盖本仓库已经实现的 Phase1/Phase2 新增能力（LIFE/Stacks、derived/curve、breakdown）

