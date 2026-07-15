---
name: apply
description: Applies the next unchecked step from the current task's tasks.md — first ensures the target repo is on the task branch (proposes/creates it interactively; you can rename it), then edits the code and shows the build/lint/test command for you to run (no build/commit auto-run), and stops. Use to implement a task one step at a time after breakdown.
user-invokable: true
metadata:
  version: 0.1.0
  canonical: .agents/skills/apply/SKILL.md
---

# apply — adapter (Claude Code)

The full, canonical playbook for this skill lives at:

**`.agents/skills/apply/SKILL.md`**

Read that file now and follow it exactly — it is the single source of truth (shared with Codex and
Cursor). This stub exists only because Claude Code cannot discover skills through symlinks; do not
act from this stub alone.
