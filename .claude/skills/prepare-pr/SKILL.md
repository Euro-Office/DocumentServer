---
name: prepare-pr
description: Prepares (never publish) the PR(s) for the current task — drafts each affected repo's PR body from plan.md with the source link and an AI-use disclosure, and shows the gh pr create command for the human to run. Prepare-only; no auditing here.
user-invokable: true
metadata:
  version: 0.1.0
  canonical: .agents/skills/prepare-pr/SKILL.md
---

# prepare-pr — adapter (Claude Code)

The full, canonical playbook for this skill lives at:

**`.agents/skills/prepare-pr/SKILL.md`**

Read that file now and follow it exactly — it is the single source of truth (shared with Codex and
Cursor). This stub exists only because Claude Code cannot discover skills through symlinks; do not
act from this stub alone.
