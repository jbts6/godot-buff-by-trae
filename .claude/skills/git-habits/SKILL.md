---
name: git-habits
description: |
  Manages git operation habits and workflows. Use this skill whenever the user mentions git operations, commits, branches, pull requests, or any version control tasks. Triggers on: committing, branching, merging, rebasing, pushing, PR creation, stash operations, worktree usage, or when the user asks about git-related questions. Also triggers when Claude is about to perform git operations on the user's behalf.
---

# Git Habits

Manage the user's git operations with two categories of rules:

- **Safety rules**: strictly enforced, no exceptions. Prevents destructive or risky operations.
- **Style rules**: flexible guidance. The user has final say, but defaults should follow their established conventions.

## Safety Rules (STRICT)

Never execute these without explicit user confirmation:

1. **Never force push to main/master.** If the user requests it, warn them and refuse. Only proceed if they type the exact phrase "I understand, force push to main."
2. **Never `git reset --hard`** or `git checkout -- .` or `git clean -f` without confirmation. These destroy uncommitted work.
3. **Never skip hooks** (`--no-verify`, `--no-gpg-sign`, `-c commit.gpgsign=false`) unless the user explicitly requests it. If a hook fails, investigate and fix the underlying issue instead of bypassing it.
4. **Never run `git push --force`** on shared branches without confirmation. Warn about overwriting collaborators' work.
5. **Never amend published commits** (commits already pushed to remote). Amending local-only commits is fine if the user asks.
6. **Never delete remote branches** without confirmation.

## Git Identity

The user's git identity:
- Username: `jbts6`
- Display name: `Analyzer`
- Email: `fh345392977@gmail.com`
- Do NOT modify git config unless the user explicitly asks.

## Commit Style (Flexible)

The user follows **conventional commits**. Apply these defaults, but defer to the user if they specify otherwise:

### Format
```
type(scope): description

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

### Types
- `feat` — new feature or functionality
- `fix` — bug fix
- `docs` — documentation only
- `chore` — maintenance, dependencies, build tasks
- `test` — adding or updating tests
- `refactor` — code restructuring without behavior change
- `style` — formatting, whitespace (no logic change)

### Scope
- Use the module/component name in parentheses: `feat(turn_manager):`, `docs(tutorial):`, `fix(ui):`
- Scopes are lowercase, use underscores for multi-word: `turn_manager`
- Omit scope for cross-cutting changes: `feat: add uid`

### Description
- Lowercase, imperative mood ("add X" not "added X" or "adds X")
- Keep it concise (under 72 chars for the subject line)
- No period at the end

### Body
- The user typically keeps commits simple — subject line only, no body.
- If the change is complex, a short body explaining WHY is acceptable. Avoid explaining WHAT the code does (the diff shows that).

### When to Commit
- Commit logical units of change, not arbitrary snapshots.
- A single commit should address one concern (one bug fix, one feature, one refactor).
- If you find yourself writing "and" in the commit message, split it into multiple commits.
- Commit after each completed step in a multi-step task, not at the very end.

### Co-Authored-By Trailer
- Always append `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>` to every commit Claude creates.
- This is a hard rule — never skip this trailer.

## Branch Naming (Flexible)

Pattern: `type/short-description-with-hyphens`

Examples from the user's workflow:
- `feat/demo-auto-delay`
- `feat/turn_manager`
- `feat/turn_skill_system`

Types match commit types: `feat/`, `fix/`, `docs/`, `chore/`, `test/`, `refactor/`.

Description uses lowercase with hyphens, 2-4 words max.

## PR Workflow (Flexible)

When creating a PR:

1. **Title**: Match the primary commit style — `type(scope): description`
2. **Body format**:
   ```
   ## Summary
   <1-3 bullet points of what changed>

   ## Test plan
   <checklist of things to verify>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   ```
3. **Before creating a PR**: Verify tests pass. If there are no tests for the change, mention it.
4. **PR targets main** unless the user specifies otherwise.

## Git Operations Workflow

When the user asks you to commit changes:

1. Run `git status`, `git diff`, and `git log --oneline -5` in parallel.
2. Analyze the changes and draft a commit message following the user's commit style.
3. Stage specific files (not `git add -A` or `git add .`).
4. Commit with the message including `Co-Authored-By` trailer.
5. Verify with `git status`.

When the user asks to create a PR:

1. Review all commits that will be in the PR (not just the latest).
2. Draft title and description.
3. Push and create PR with `gh pr create`.

## What NOT to Do

- Don't use `git add -A` or `git add .` — stage specific files.
- Don't amend commits unless explicitly asked.
- Don't push to remote unless asked.
- Don't create commits unless asked.
- Don't use interactive git commands (`git rebase -i`, `git add -i`).
