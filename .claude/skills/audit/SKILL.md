---
name: audit
description: Audits a diff — the current task's working changes OR any open PR — into review.md with four blocks: security (/security-review + AGPL checklist + web-apps memory-leak sweep), code quality (/code-review), an emulated SonarQube-style Quality Gate (A–E, PASS/FAIL), and proposed PR comments (drafts for the human to post, never posted autonomously). Task-mode reviews are written to .ai/tasks/<task-id>/review.md; standalone PR reviews to .ai/reviews/<repo>-<n>/review.md. Use before preparing a PR, or to review any PR independently.
user-invokable: true
metadata:
  version: 0.1.0
  canonical: .agents/skills/audit/SKILL.md
---

# audit — adapter (Claude Code)

The full, canonical playbook for this skill lives at:

**`.agents/skills/audit/SKILL.md`**

Read that file now and follow it exactly — it is the single source of truth (shared with Codex and
Cursor). This stub exists only because Claude Code cannot discover skills through symlinks; do not
act from this stub alone.
