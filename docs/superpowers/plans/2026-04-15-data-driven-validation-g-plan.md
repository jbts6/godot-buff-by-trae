# Data-Driven + Validation (G1~G4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 checklist 的 G1~G4 收尾到可打勾：manifest 权威加载、enums/tags 可追溯、schema 未知字段治理（strict/lenient）、Issue 定位信息稳定，并同步更新 checklist。

**Architecture:** 先新增 3 个 failing tests（manifest 权威、tags_mask roundtrip、strict/lenient unknown fields），再补最小实现（enums_runtime 增 tags_from_mask + validators 增强 enum 列表校验），最后全量测试通过后更新 checklist 勾选 G1~G4。

**Tech Stack:** Godot 4.7 + GDScript + GUT。

---

## 0) 文件清单

**运行时：**
- Modify: `godot-buff/addons/omnibuff/runtime/core/enums_runtime.gd`

**编译校验：**
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_manifest_loader_authority.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_enums_tag_mask_roundtrip.gd`
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_validators_unknown_fields_strict_lenient.gd`

**文档：**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

---

## Task 1：新增 failing test（G1：manifest 权威 + 路径解析）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_manifest_loader_authority.gd`

- [ ] **Step 1: 写测试**

```gdscript
extends GutTest

const ManifestLoader := preload("res://addons/omnibuff/config/manifest_loader.gd")

func test_manifest_loader_only_loads_files_declared_in_manifest() -> void:
	var res: ManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/rpg_tests/manifest.json", true)
	assert_true(res.issues.is_empty(), "dataset should load without issues in strict mode")

	# sources 的 key 只能来自 manifest.files[].type（不包含 manifest/enums）
	var allowed := {}
	for f in res.manifest.get("files", []):
		var t := String(f.get("type", ""))
		if t != "" and t != "manifest" and t != "enums":
			allowed[t] = true

	for k in res.sources.keys():
		assert_true(allowed.has(String(k)), "sources contains unexpected key: %s" % String(k))

	# 关键：rpg_tests 的 enums 来自 ../base_demo/enums.json，能成功加载即说明 ../ 解析稳定
	assert_true(res.enums.has("tags"))
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_manifest_loader_authority.gd
git -C godot-buff commit -m "test(g1): lock manifest.files authority"
```

---

## Task 2：新增 failing test（G2：tags_mask roundtrip）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_enums_tag_mask_roundtrip.gd`

- [ ] **Step 1: 写测试**

```gdscript
extends GutTest

const ManifestLoader := preload("res://addons/omnibuff/config/manifest_loader.gd")
const EnumsRt := preload("res://addons/omnibuff/runtime/core/enums_runtime.gd")

func test_tags_mask_roundtrip_is_traceable_and_stable() -> void:
	var res: ManifestLoader.Result = ManifestLoader.load_dataset_full("res://data/base_demo/manifest.json", true)
	assert_true(res.issues.is_empty())
	var rt: OmniEnumsRuntime = EnumsRt.from_enums_json(res.enums)

	var mask := int(rt.tag_mask(["DOT", "POISON"]))
	var tags: Array[String] = rt.tags_from_mask(mask)
	assert_true(tags.has("DOT"))
	assert_true(tags.has("POISON"))
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_enums_tag_mask_roundtrip.gd
git -C godot-buff commit -m "test(g2): add tags_mask roundtrip coverage"
```

---

## Task 3：新增 failing test（G3/G4：unknown fields strict/lenient + Issue 定位）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_validators_unknown_fields_strict_lenient.gd`

- [ ] **Step 1: 写测试**

```gdscript
extends GutTest

const ManifestLoader := preload("res://addons/omnibuff/config/manifest_loader.gd")
const Validate := preload("res://addons/omnibuff/config/compiler/validators.gd")

func _has_issue(issues: Array, level: int, contains: String) -> bool:
	for i in issues:
		if int(i.level) == level and String(i.message).find(contains) >= 0:
			return true
	return false

func test_unknown_fields_are_warning_in_lenient_and_error_in_strict() -> void:
	var manifest_path := "res://data/rpg_tests/manifest.json"
	var res: ManifestLoader.Result = ManifestLoader.load_dataset_full(manifest_path, true)

	# 注入未知字段
	var sources := res.sources.duplicate(true)
	var buff_defs: Dictionary = sources["buff_defs"]
	var buffs: Array = buff_defs.get("buffs", [])
	var b0: Dictionary = buffs[0]
	b0["unknown_x"] = 123

	# lenient：warning
	var issues_lenient := Validate.validate_all(manifest_path, res.manifest, res.enums, sources, false)
	assert_true(_has_issue(issues_lenient, OmniValidate.Level.WARNING, "unknown field"))

	# strict：error
	var issues_strict := Validate.validate_all(manifest_path, res.manifest, res.enums, sources, true)
	assert_true(_has_issue(issues_strict, OmniValidate.Level.ERROR, "unknown field"))

	# G4：Issue 定位字段必须可用
	var i0 = issues_lenient[0]
	assert_true(String(i0.file) != "")
	assert_true(String(i0.loc) != "")
	assert_true(String(i0.message) != "")
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_validators_unknown_fields_strict_lenient.gd
git -C godot-buff commit -m "test(g3/g4): add strict/lenient unknown-field coverage"
```

---

## Task 4：实现 G2（tags_from_mask）+ validators enum 列表治理

**Files:**
- Modify: `godot-buff/addons/omnibuff/runtime/core/enums_runtime.gd`
- Modify: `godot-buff/addons/omnibuff/config/compiler/validators.gd`

- [ ] **Step 1: enums_runtime.gd 新增 tags_from_mask**

```gdscript
func tags_from_mask(mask: int) -> Array[String]:
	var pairs: Array = []
	for id in tag_code_by_id.keys():
		pairs.append([int(tag_code_by_id[id]), String(id)])
	pairs.sort_custom(func(a, b): return int(a[0]) < int(b[0]))

	var out: Array[String] = []
	for p in pairs:
		var code := int(p[0])
		var id := String(p[1])
		if (mask & (1 << code)) != 0:
			out.append(id)
	return out
```

- [ ] **Step 2: validators.gd：enum 数组唯一/非空**

在 `_validate_enums` 的 required_enums 循环内，对 `enums[name]` 做：
- 值必须是非空 String
- 重复值报错

- [ ] **Step 3: 提交**

```bash
git -C godot-buff add addons/omnibuff/runtime/core/enums_runtime.gd addons/omnibuff/config/compiler/validators.gd
git -C godot-buff commit -m "feat(g2/g3): add tags_from_mask and enum list validation"
```

---

## Task 5：更新 checklist 勾选 G1~G4

**Files:**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

- [ ] **Step 1: 勾选 G1~G4 为 [x]**
- [ ] **Step 2: 提交**

```bash
git -C godot-buff add docs/superpowers/checklists/omnibuff-done-definition.md
git -C godot-buff commit -m "docs(checklist): mark G complete"
```

