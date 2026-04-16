# OmniBuff Phase 0（Demo-only）Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Phase 0（Demo-only）剩余工作拆成可执行任务，确保 Debug HUD + Scenario Runner 形成稳定的调试闭环，并把 dump/文档/校验补齐，便于回顾与持续迭代。

**Architecture:** 在既有 `buff_ui_demo`（scenario runner）与 `debug_hud`（tabs）基础上做增量：dump 结构化与长度控制、HUD 自动选中体验、validators/lint 规则加强、文档化调试工作流。保持 demo-only，不引入主游戏依赖。

**Tech Stack:** Godot 4.7 + GDScript + OmniBuff runtime.

---

## 0) 文件清单（会涉及）

- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Modify: `godot-buff/addons/omnibuff/README.md`

---

## Task 1：Debug HUD dump 结构化与长度上限（p0-7）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`

- [ ] **Step 1: 抽出统一的 section 拼装**

新增 helper：
```gdscript
const DUMP_MAX_CHARS := 20000

func _join_sections(sections: Array[String]) -> String:
    var s := "\\n\\n".join(sections).strip_edges()
    if s.length() > DUMP_MAX_CHARS:
        return s.substr(0, DUMP_MAX_CHARS) + \"\\n\\n...(truncated)\"\n
    return s
```

- [ ] **Step 2: 将 _make_dump() 改为固定顺序 sections**

固定顺序：
1) `_format_stats()`
2) `_format_stat_mods()`
3) `_format_buffs()`
4) `_format_dots()`
5) `_format_listeners()`

- [ ] **Step 3: 复制按钮显示截断提示**

当发生截断，在 window title/status 中提示 “truncated”。

- [ ] **Step 4: 手工验收**

运行 `run_all` 场景后复制 dump：
- 结构顺序稳定
- 超长时能截断且提示

- [ ] **Step 5: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/debug_hud.gd
git -C godot-buff commit -m \"feat(debug): structure dump and cap length\"
```

---

## Task 2：Demo 体验：HUD 自动选中与多目标辅助（p0-8）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`
- (可选) Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`

- [ ] **Step 1: 在 runtime 注入 attacker/defender**

当前已有 `_hud_attacker_id/_hud_defender_id`，确保每个 scenario 在创建 actor 后都设置它们。
（已有大部分场景覆盖；补漏场景）

- [ ] **Step 2: AOE 场景的默认 target**

在 `_sc_aoe_multitarget_multihit` 场景里：
- 约定 `_hud_defender_id` 指向第一个 target（已做）
- 若希望更强：在 rt 注入 `rt[\"targets\"]=[idA,idB]`（可选）

- [ ] **Step 3: HUD 中提供“快速切换到 defender”按钮（可选）**

在 TopBar 新增两个按钮：
- “选 attacker”
- “选 defender”

（此步可选，若你希望纯下拉即可）

- [ ] **Step 4: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd addons/omnibuff/demo/debug_hud.tscn addons/omnibuff/demo/debug_hud.gd
git -C godot-buff commit -m \"feat(demo): improve hud auto selection\"
```

---

## Task 3：Validate/Lint Phase 0：字段要求矩阵与更可读错误（p0-9）

**Files:**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`

- [ ] **Step 1: 为 action.kind 建字段要求矩阵**

例如：
- APPLY_BUFF/CHANCE_APPLY_BUFF：必须 buff_id/apply_buff_id；add_stacks 可选（>=1）
- SET_STAT_FINAL：必须 stat；value 必须存在（或允许缺省=0）
- DOT_*：dot_buff_id 或 dot_tags_mask_any 至少一个

- [ ] **Step 2: 让错误信息带“建议”**

例如：
`missing stat for SET_STAT_FINAL (hint: {"kind":"SET_STAT_FINAL","stat":"SHIELD","value":0})`

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/config/compiler/validators.gd
git -C godot-buff commit -m \"feat(validate): action schema matrix and better hints\"
```

---

## Task 4：文档化调试工作流与 dump 规范（p0-10）

**Files:**
- Modify: `godot-buff/addons/omnibuff/README.md`

- [ ] **Step 1: 增加“调试工作流”章节**

内容包含：
1) 运行 scenario
2) 打开 HUD
3) 查看 Dots/Listeners/StatMods
4) 复制日志与 dump
5) 粘贴到 issue 的模板建议

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/README.md
git -C godot-buff commit -m \"docs: add phase0 debugging workflow\"
```

