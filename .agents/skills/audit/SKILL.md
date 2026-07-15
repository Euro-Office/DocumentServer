---
name: audit
description: Audits a diff — the current task's working changes OR any open PR — into review.md with four blocks: security (/security-review + AGPL checklist + web-apps memory-leak sweep), code quality (/code-review), an emulated SonarQube-style Quality Gate (A–E, PASS/FAIL), and proposed PR comments (drafts for the human to post, never posted autonomously). Task-mode reviews are written to .ai/tasks/<task-id>/review.md; standalone PR reviews to .ai/reviews/<repo>-<n>/review.md. Use before preparing a PR, or to review any PR independently.
user-invokable: true
metadata:
  version: 0.1.0
---

# audit — security + code + emulated quality gate

> **Language rule (non-negotiable):** detect the language the human used when invoking this skill
> and use that language for ALL user-facing output. Default to **English** if unclear. Never output
> in a language that was not used in the invocation or the conversation history.

Independent stage. Audits a diff and writes `review.md` with four blocks — (a) security, (b) code,
(c) an emulated Quality Gate, and (d) proposed PR comments. It **reuses the built-in
`/security-review` and `/code-review`** skills and adds Euro-Office-specific layers. The Quality Gate
is **informational — it does not block**.

Two modes:

| Mode | When to use | Output |
|---|---|---|
| **Task mode** (default) | Reviewing your own in-progress changes before a PR | `.ai/tasks/<task-id>/review.md` |
| **PR mode** | Reviewing any open PR (your own or a teammate's) | `.ai/reviews/<repo>-<n>/review.md` |

> **Where the review is written — task vs PR are different concepts.** A task-mode review is one
> artifact of the task workspace, so it lives with the task's other files under `.ai/tasks/<task-id>/`.
> A PR review is **not** a task — it gets its own top-level namespace `.ai/reviews/` so it never
> mixes into `.ai/tasks/`.

> Named `audit` (not `code-review`) so it can invoke the built-in `/code-review` without shadowing
> or recursing into itself.

> **Recommended execution:** normal mode. See `.agents/skills/_shared/execution-profiles.md` for
> recommended model and effort (bump to max if security-critical). State the profile to the human
> before starting.

## Invocation

```
/audit                              # task mode: diff for the current task-id (working tree vs main)
/audit <owner>/<repo>#<n>           # PR mode: review an open PR by ref
/audit <GitHub-PR-URL>              # PR mode: review an open PR by URL
```

If no argument is given and no task-id can be inferred from the current branch, ask the human
which mode to use.

## Steps

### Step 1 — Resolve the target diff

**Task mode** (no argument):
- Infer `task-id` from the current branch (`feature/<task-id>`) or ask.
- Diff = uncommitted changes + commits on `feature/<task-id>` vs `main`.
- Output file: `.ai/tasks/<task-id>/review.md`.

**PR mode** (argument provided):
- Parse the ref: `<owner>/<repo>#<n>` or extract from a GitHub PR URL
  (pattern: `github.com/<owner>/<repo>/pull/<n>`).
- Fetch the diff:
  ```sh
  gh pr diff <n> --repo <owner>/<repo>
  ```
  No `gh` / not authenticated / no access → ask the human to paste the diff manually.
- Output file: `.ai/reviews/<repo>-<n>/review.md` (owner defaults to `Euro-Office`; keep the owner in
  the folder only if it is not `Euro-Office`, e.g. `.ai/reviews/<owner>-<repo>-<n>/review.md`).
  Paste-back if `.ai/` is not writable. **Never** write a PR review under `.ai/tasks/`.
- Note the PR title, branch, and target branch for context.

### Step 2 — Block (a) Security

- Invoke the built-in **`/security-review`** on the diff.
- Run the **AGPL-3.0 checklist** (`.agents/skills/_shared/agpl-checklist.md`).
- Run the **memory-leak sweep** on `web-apps` changes
  (`.agents/skills/_shared/memory-leak-checklist.md`).
- Note **parity with CodeQL** (which runs in CI).
- Reminder: verified security issues are reported **privately by email** to the maintainers,
  **never** as GitHub issues and **never** autonomously (root `AGENTS.md`).

### Step 3 — Block (b) Code (correctness + quality)

- Invoke the built-in **`/code-review`**, respecting the repo's eslint/prettier config.

### Step 4 — Block (c) Quality Gate (emulated)

- Apply `.agents/skills/_shared/sonar-quality-gate.md`: classify findings, assign
  Reliability/Security/Maintainability ratings **A–E**, compute **PASS/FAIL** + score.

### Step 5 — Block (d) Proposed PR comments

Turn the confirmed findings into concrete, copy-pasteable review comments the **human** can post on
the PR. This block is always produced (most useful in PR mode).

- One entry per comment, anchored to a location: `<repo> <path>:<line>` + a short, actionable
  suggestion written in the reviewer's voice (a phrasing the human can paste as-is).
- Only include findings worth a comment — do not restate every Quality-Gate line.
- These are **drafts for the human to post** — the skill never posts them itself (see Guardrails).
- **Language rule applies:** write the comments (and every heading) in the human's language;
  default to English if unclear.

### Step 6 — Write output

Write the review file (path from Step 1).

## Output template

~~~markdown
# Review — <task-id | PR owner/repo#n>

Scope: <repos + branches / diff summary>
Mode: task | PR (<PR title if PR mode>)

## a) Security
- /security-review: <key findings or "none">
- AGPL-3.0 checklist: <pass / issues>
- Memory-leak sweep (web-apps): <findings or "n/a">
- CodeQL parity: <notes>
> Security reports go privately by email to the maintainers — never as issues, never autonomous.

## b) Code (correctness + quality)
- /code-review: <findings, respecting repo eslint/prettier>

## c) Quality Gate (emulated) — PASS | FAIL
Reliability: A   Security: A   Maintainability: B
Bugs: 0 · Vulnerabilities: 0 · Hotspots: 1 (review) · Code Smells: 4 · Duplications: 1.2% · Coverage(new): n/a
CodeQL parity: no known findings | [list]
Top items: 1) …  2) …

## d) Proposed PR comments
> Drafts for the human to post — the skill never comments on GitHub itself.
> Written in the human's language (default English).
- `<repo> <path>:<line>` — <suggested comment, in the reviewer's voice>
- `<repo> <path>:<line>` — <suggested comment>
~~~

## Guardrails

- **Audit only** — produce `review.md`; do not fix, commit, or publish.
- The Quality Gate is **non-blocking** (a snapshot for the human).
- **Never** post review comments on GitHub autonomously; share findings with the human only.
- **Never** file security reports autonomously; flag AGPL doubts rather than silencing them.
- Assisted mode: findings are for the human to act on.

## References

- `.agents/skills/_shared/agpl-checklist.md` · `memory-leak-checklist.md` · `sonar-quality-gate.md` · `execution-profiles.md`
- Built-in skills: `/security-review`, `/code-review`
- Root `AGENTS.md` (§"Contribution policy"), `CONTRIBUTING.md`, `SECURITY.md`
- Prev: `apply` · Next: `prepare-pr` (or standalone for PR reviews).
