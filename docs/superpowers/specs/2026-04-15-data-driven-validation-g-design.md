# G（数据驱动与校验：manifest/enums/defs）设计（最小集）

## 目标（本轮最小集）

把 checklist 的 G1~G4 收尾到可打勾：

- **G1 manifest 权威**：所有数据文件仅通过 `manifest.files[]` 加载，路径解析稳定（支持 `../`）。
- **G2 enums 权威（最小集）**：保持现状“enum 数组按序映射”，但补齐**可追溯能力**与测试锁死：
  - tags.code → bitmask 映射可反解（mask → tags[]）
  - 常用 tag（如 FIRE/POISON/DOT）映射有回归测试
  - validators 增强：enum 列表值唯一/非空
- **G3 Schema 治理**：未知字段深度治理（JSONPath 定位），strict/lenient 行为可测试。
- **G4 错误定位可用**：Issue 结构稳定（file+loc+id+message），并有测试保证。

## 非目标

- 不引入“显式 enum code 映射/lockfile”（这是更大改动，留给后续增强版）
- 不改变现有数据格式（保持兼容）

---

## 现状分析（已具备的能力）

### manifest 权威
`OmniManifestLoader.load_dataset_full()` 已按 `manifest.files[]` 加载全部 json/csv，并用 `_resolve_relative(base_dir.path_join(rel))` 支持相对路径与 `../`。

### Issue 定位
`OmniValidate.Issue` 已具备：`level/file/loc/id/message`，并且 validators 里大量使用 `path=$...` 的 JSONPath。

### Schema 未知字段治理
`OmniValidate._unknown_fields()` 已对多处结构调用，但缺少“strict/lenient 行为”的专门测试锁死。

### enums/tags
tags 使用显式 `code` 并映射为 `1<<code`；但缺少：
- mask 反解能力（可追溯）
- enum 数组的“重复/空字符串”校验

---

## 设计：新增/调整点

### 1) G2：tags_mask 反解（可追溯）

在 `addons/omnibuff/runtime/core/enums_runtime.gd` 新增：

- `func tags_from_mask(mask: int) -> Array[String]`
  - 返回所有命中的 tag_id（按 code 升序稳定排序）
  - 用于调试/追帧/断言

（可选）`func describe_tags_mask(mask: int) -> String`：以 `"DOT|FIRE"` 形式输出字符串（不要求本轮实现）。

### 2) G2：validators 增强（enum 列表唯一/非空）

在 `OmniValidate._validate_enums` 中，对 required_enums 的每个 `Array`：
- 校验每个值必须是非空 String
- 校验值不得重复
- Issue.loc 使用 `path=$.enums.<name>[i]`

### 3) G3/G4：补齐专门测试

新增 3 个 GUT：
1) `test_manifest_loader_manifest_files_authority.gd`
   - 断言 rpg_tests 数据集：`sources` 的 key 集合来自 `manifest.files[].type`（剔除 manifest/enums）
   - 断言 `enums` 来自 `../base_demo/enums.json` 能加载成功（路径解析稳定）

2) `test_enums_runtime_tag_mask_roundtrip.gd`
   - `mask = tag_mask(["DOT","POISON"])`
   - `tags_from_mask(mask)` 必须包含 DOT/POISON（顺序稳定）

3) `test_validators_unknown_fields_strict_lenient.gd`
   - 基于 rpg_tests 的 sources 拷贝，在某个 buff 上注入未知字段 `unknown_x`
   - `strict=false`：应产生 WARNING（level=WARNING）且 loc=path=...
   - `strict=true`：同 issue 应升级为 ERROR（level=ERROR）
   - 同时断言 Issue 的 file/loc/message 非空（G4）

---

## 验收标准

- 新增 tests 全绿
- checklist：G1~G4 标为完成并提交

