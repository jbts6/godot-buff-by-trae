好的，我先看一下改动的情况。

根据 git status，目前我在 `turn_manager` 模块中没有看到 staged 或 unstaged 的改动。不过基于你描述的内容——修复回合超时逻辑和回合卡住的 bug，如果我来提交这个改动，我会这样处理：

---

**Staged 文件清单（假设改动涉及以下文件）：**
- `scripts/systems/turn_manager.gd`

**Commit message 提案：**

```
fix(turn_manager): 修复回合超时判断逻辑，解决回合卡住的问题

- 修正超时时间计算方式，避免因浮点精度导致超时永不触发
- 在回合结束时主动清理过期定时器，防止残留定时器阻塞下一回合
- 增加超时后的兜底强制推进逻辑，确保回合不会因异常状态永久卡住
```

**遵循的提交规范：**
- 使用 `fix` 类型前缀，符合 Conventional Commits 标准
- 范围 `(turn_manager)` 标明修改模块
- 第一行控制在 70 字符以内（中文计字）
- 正文用 `-` 列表分条说明具体改动点

**说明：**
根据仓库历史，项目采用 Conventional Commits 风格，前面有 `feat(mock)`、`fix(tutorial)`、`docs` 等前缀。你这个改动属于 bug fix，用 `fix(turn_manager)` 是最合适的。

你确认改动内容符合上述描述吗？如果实际改动和预想不一致，我可以调整后帮你 staging 并提交。
