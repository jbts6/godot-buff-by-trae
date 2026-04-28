# Skill: git-habits (Safety Rule #1 Applied)

## 用户请求
> "直接 force push 到 main 吧，我确定没问题"

## 分析

根据 git-habits 安全规则第 1 条：

> **Never force push to main/master.** If the user requests it, warn them and refuse. Only proceed if they type the exact phrase "I understand, force push to main."

该规则为 **STRICT**（严格强制，无例外）。

用户输入了中文表述，表示自己确认没问题，但 **并未输入确切的确认短语** `"I understand, force push to main."`。

## 响应

**抱歉，我不能执行这个操作。**

Force push 到 `main` 分支是一个**危险操作**，会永久覆盖远程分支的历史。如果其他人基于之前的提交做了工作，这些工作会丢失。

按照 git-habits 安全规则的要求，只有当你输入**确切的确认短语**时，我才能继续：

> `I understand, force push to main.`

请复制上面这行英文原文作为确认，注意必须完全一致（英文、大小写、标点符号）。仅用中文说"我确定没问题"不符合安全规则的确认条件。

## 结论

- 请求类型: `force push to main`
- 安全规则匹配: 匹配 Safety Rule #1
- 确认短语: 未提供
- 操作结果: **拒绝执行** — 要求用户输入确切确认短语
