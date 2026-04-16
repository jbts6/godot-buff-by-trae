# OmniBuff Phase 1 Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 扩展 `triggers[].filters` 的表达能力（crit/skill_id/damage_type/element/shield_absorb/damage_threshold），并在 EventIndex 子集遍历框架内高效执行，配套 validators + tests + demo scenarios。

**Architecture:** 在 `OmniEventIndex.Listener` 增加紧凑字段；在 `BuffCore._register_triggers_for_instance()` 解析 filters；在 `BuffCore.emit_event()` 做快速过滤；在 `DamagePipeline.deal_damage()` 写入 skill/type/element 与 absorbed_shield meta；新增 rpg tests 与 demo scenario 验证。

**Tech Stack:** Godot 4.7 + GDScript + OmniEventIndex + OmniBuffCore + OmniDamagePipeline + GUT。

---

## 0) 文件清单

- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`
- Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`（filters 摘要输出增强）
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`（新增场景）
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_filters_extended.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_filters_extended.gd.uid`

---

## Task 1：写 failing tests（RED）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_filters_extended.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_event_filters_extended.gd.uid`

- [ ] **Step 1: 新增测试骨架**

```gdscript
extends GutTest

const ReplayScript = preload(\"res://addons/omnibuff/runtime/core/replay.gd\")
const TestDataset = preload(\"res://addons/omnibuff/tests/helpers/test_dataset.gd\")
const TestBattle = preload(\"res://addons/omnibuff/tests/helpers/test_battle.gd\")

func test_require_crit_filter() -> void:
    # 先写期望：require_crit=true 时仅 crit 命中触发
    pass
```

- [ ] **Step 2: 具体用例（至少 4 个）**

1) `require_crit`
2) `require_shield_absorbed`
3) `min_final_damage`
4) `damage_type_any` + `element_any`

> 这些测试初始应失败（因为 runtime 还不支持新 filter 字段）。

- [ ] **Step 3: 手工运行验证 RED**

运行（你的本地 Godot 环境）：
```bash
GODOT_BIN=\"/path/to/godot\" ./run_gut_tests.sh addons/omnibuff/tests/rpg/test_event_filters_extended.gd
```
Expected：FAIL（缺少 filters 行为）。

- [ ] **Step 4: Commit**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_event_filters_extended.gd addons/omnibuff/tests/rpg/test_event_filters_extended.gd.uid
git -C godot-buff commit -m \"test(filters): add failing coverage for phase1 filters\"
```

---

## Task 2：扩展 Listener 字段（GREEN-1）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/event_index.gd`

- [ ] **Step 1: Listener 增加字段（带默认值）**

```gdscript
var filter_require_crit: bool = false
var filter_skill_id: int = -1
var filter_damage_type_mask_any: int = 0
var filter_element_mask_any: int = 0
var filter_require_shield_absorbed: bool = false
var filter_min_absorbed_shield: float = 0.0
var filter_min_final_damage: float = 0.0
```

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/event_index.gd
git -C godot-buff commit -m \"feat(filters): extend listener filter fields\"
```

---

## Task 3：解析 filters（GREEN-2）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 在 _register_triggers_for_instance() 解析新字段**

读取：
- `require_crit` -> `l.filter_require_crit`
- `skill_id` -> `l.filter_skill_id`
- `min_final_damage` / `min_absorbed_shield`
- `require_shield_absorbed`

并对 `damage_type_any/element_any` 做枚举映射，构建 bitmask：
```gdscript
var mask := 0
for s in arr:
    var code := enums_rt.enum_int(\"damage_type\", String(s))
    if code >= 0:
        mask |= (1 << code)
l.filter_damage_type_mask_any = mask
```

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff commit -m \"feat(filters): parse trigger filters into listener\"
```

---

## Task 4：emit_event 执行过滤（GREEN-3）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/buff_core.gd`

- [ ] **Step 1: 在 emit_event 循环中增加 cheap checks**

顺序建议：
1) tag_mask
2) require_hit / require_crit
3) skill_id
4) damage_type/element mask
5) absorbed_shield（meta）与阈值
6) min_final_damage（ctx.final_damage）
7) stat_threshold（已有，放最后）

absorbed_shield 读取：
```gdscript
var absorbed := 0.0
if ctx.has_meta(\"absorbed_shield\"):
    absorbed = float(ctx.get_meta(\"absorbed_shield\"))
```

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/buff_core.gd
git -C godot-buff commit -m \"feat(filters): apply filters in emit_event\"
```

---

## Task 5：DamagePipeline 写入 skill/type/element（GREEN-4）

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/damage_pipeline.gd`

- [ ] **Step 1: 扩展 deal_damage() 参数（保持默认兼容）**

新增可选参数：
```gdscript
func deal_damage(..., skill_id: int = -1, damage_type: int = 0, element: int = 0) -> DamageContext:
    ctx.skill_id = skill_id
    ctx.damage_type = damage_type
    ctx.element = element
```

并在现有调用点（tests/demo）按需传参；不传则保持默认。

- [ ] **Step 2: 同步 deal_damage_with_tags()（可选）**

若要在 DOT tick 中也支持 element/type，可在 `deal_damage_with_tags` 增加同样参数。

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/damage_pipeline.gd
git -C godot-buff commit -m \"feat(filters): pass skill/type/element via damage context\"
```

---

## Task 6：validators 更新（schema 治理）

**Files:**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`

- [ ] **Step 1: allowed_filters 放行新字段**
增加：
- require_crit（bool）
- skill_id（int）
- damage_type_any（Array[String]）
- element_any（Array[String]）
- require_shield_absorbed（bool）
- min_absorbed_shield（float >=0）
- min_final_damage（float >=0）

- [ ] **Step 2: 校验逻辑**
- damage_type_any / element_any：枚举存在性校验（unknown -> error）
- min_*：>=0

- [ ] **Step 3: Commit**

```bash
git -C godot-buff add addons/omnibuff/config/compiler/validators.gd
git -C godot-buff commit -m \"feat(validate): support phase1 trigger filters\"
```

---

## Task 7：Debug HUD Listeners 输出增强（可选但推荐）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/debug_hud.gd`

- [ ] **Step 1: 在 listeners 行输出新 filters 摘要**
例如：
- require_crit
- skill_id
- damage_type_any / element_any（用 enums_rt 反查）
- require_shield_absorbed / min_absorbed_shield / min_final_damage

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/debug_hud.gd
git -C godot-buff commit -m \"feat(debug): display phase1 filters in listeners tab\"
```

---

## Task 8：Demo 场景（可选）

**Files:**
- Modify: `godot-buff/addons/omnibuff/demo/buff_ui_demo.gd`
- Modify (data): `godot-buff/data/rpg_tests/buff_defs.json`

- [ ] **Step 1: 新增 1~2 个 scenario**
- 暴击才触发（require_crit）
- 护盾吸收才触发（require_shield_absorbed）

- [ ] **Step 2: Commit**

```bash
git -C godot-buff add addons/omnibuff/demo/buff_ui_demo.gd data/rpg_tests/buff_defs.json
git -C godot-buff commit -m \"feat(demo): add phase1 filter scenarios\"
```

---

## 最终验证（GREEN）

- [ ] 运行新增测试文件：全部 PASS
- [ ] 随机抽 2 个旧 rpg tests：仍 PASS（不受默认字段影响）
- [ ] Demo 场景可在 HUD 的 Listeners 中直观看到 filters，并能解释触发/未触发

