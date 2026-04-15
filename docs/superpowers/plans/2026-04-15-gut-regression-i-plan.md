# GUT Regression (I1~I4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收尾 I（测试与回归）：补 I3 数据集隔离回归测试、修复 I4 headless 脚本、并同步更新 checklist 使 I1~I4 可打勾。

**Architecture:** 先新增 failing tests（I3），再修复 `run_gut_tests.sh`（I4），再补 README（可选），最后更新 checklist 勾选 I1~I4。

**Tech Stack:** Godot 4.7 + GDScript + GUT + Bash。

---

## 0) 文件清单

**测试：**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dataset_isolation_manifests.gd`

**脚本：**
- Modify: `godot-buff/run_gut_tests.sh`

**文档（可选）：**
- Modify: `godot-buff/addons/omnibuff/README.md`

**checklist：**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

---

## Task 1：新增 I3 测试（manifest 引用边界）

**Files:**
- Create: `godot-buff/addons/omnibuff/tests/rpg/test_dataset_isolation_manifests.gd`

- [ ] **Step 1: 写 failing test**

```gdscript
extends GutTest

const OmniJson = preload("res://addons/omnibuff/config/io/json.gd")

func _is_allowed_rpg_tests_path(p: String) -> bool:
	# 允许：rpg_tests 目录内相对路径；以及共享 enums（../base_demo/enums.json）
	if p.begins_with("rpg_tests/"):
		return true
	if p == "../base_demo/enums.json":
		return true
	if p.begins_with("../base_demo/") and p != "../base_demo/enums.json":
		return false
	return false

func test_rpg_tests_manifest_only_refs_rpg_tests_files_and_shared_enums() -> void:
	var m: Dictionary = OmniJson.load_dict("res://data/rpg_tests/manifest.json")
	assert_true(m.has("files"))
	for f in m.get("files", []):
		var rel: String = String(f.get("path", ""))
		assert_true(_is_allowed_rpg_tests_path(rel), "unexpected rpg_tests manifest path: %s" % rel)

func test_base_demo_manifest_does_not_ref_rpg_tests() -> void:
	var m: Dictionary = OmniJson.load_dict("res://data/base_demo/manifest.json")
	assert_true(m.has("files"))
	for f in m.get("files", []):
		var rel: String = String(f.get("path", ""))
		assert_true(rel.find("rpg_tests") < 0, "base_demo manifest should not reference rpg_tests: %s" % rel)
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/tests/rpg/test_dataset_isolation_manifests.gd
git -C godot-buff commit -m "test(i3): lock dataset isolation via manifests"
```

---

## Task 2：修复 I4 headless 脚本（GODOT_BIN 全覆盖）

**Files:**
- Modify: `godot-buff/run_gut_tests.sh`

- [ ] **Step 1: 修复脚本第二次调用**

把：
```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://addons/omnibuff/tests -gexit
```

改为：
```bash
"${GODOT_BIN}" --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://addons/omnibuff/tests -gexit
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add run_gut_tests.sh
git -C godot-buff commit -m "fix(i4): use GODOT_BIN for gut cmdln run"
```

---

## Task 3（可选）：README 补充 CI 跑法

**Files:**
- Modify: `godot-buff/addons/omnibuff/README.md`

- [ ] **Step 1: 增加一段说明**

示例：
```md
## Run tests (headless)

GODOT_BIN="/path/to/Godot" ./run_gut_tests.sh

- Exit code 0: all tests passed
- Exit code != 0: failed (CI should fail the job)
```

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add addons/omnibuff/README.md
git -C godot-buff commit -m "docs(i4): document headless gut command"
```

---

## Task 4：更新 checklist 勾选 I1~I4

**Files:**
- Modify: `godot-buff/docs/superpowers/checklists/omnibuff-done-definition.md`

- [ ] **Step 1: 勾选**
把 I1~I4 全部标为 `[x]`。

- [ ] **Step 2: 提交**

```bash
git -C godot-buff add docs/superpowers/checklists/omnibuff-done-definition.md
git -C godot-buff commit -m "docs(checklist): mark I complete"
```

