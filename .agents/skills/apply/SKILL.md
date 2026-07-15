---
name: apply
description: Applies the next unchecked step from the current task's tasks.md — first ensures the target repo is on the task branch (proposes/creates it interactively; you can rename it), then edits the code and shows the build/lint/test command for you to run (no build/commit auto-run), and stops. Use to implement a task one step at a time after breakdown.
user-invokable: true
metadata:
  version: 0.1.0
---

# apply — assisted implementation (one step, then stop)

> **Language rule (non-negotiable):** detect the language the human used when invoking this skill
> and use that language for ALL user-facing output. Default to **English** if unclear. Never output
> in a language that was not used in the invocation or the conversation history.

Third stage. Inherently interactive: applies exactly **one** step and stops. Before editing it makes
sure the target repo is on the **task branch** (proposing/creating it with your confirmation), then
edits code and **shows** the build/lint/test command for **you** to run. It never runs builds/tests,
never commits/pushes, and never auto-heals in a loop. The only git action it performs is
creating/switching the task branch — and only after you confirm.

> **Recommended execution:** normal mode. See `.agents/skills/_shared/execution-profiles.md` for
> recommended model and effort. State the profile to the human before starting; if they raised
> effort earlier remind them to lower it (`/effort`).

## Invocation

- `/apply` — take the **first `- [ ]`** from `.ai/tasks/<task-id>/tasks.md` for the current task-id.

## Steps

1. **Resolve the `task-id`** and read `tasks.md`. Resolve from the current branch `feature/<task-id>`,
   the most recent `tasks.md`, or ask. A **custom branch name is fine** — in that case resolve the
   task-id from `tasks.md`, not from the branch.
2. **Pick the first unchecked step** `- [ ]`. If none remain → report completion and suggest `audit`.
3. **Ensure the repo is on the task branch (interactive — propose, confirm, then create/switch):**
   a. **Intended branch** = the one recorded for this repo under `tasks.md` "## Branches", else the
      default `feature/<task-id>`.
   b. **Current branch**: `git -C <repo> rev-parse --abbrev-ref HEAD`.
   c. If it already matches (or you confirm the current branch is this task's branch) → continue.
   d. Otherwise **propose the branch**: show the default name `feature/<task-id>` and ask you to
      **accept it or type a different name** (you may not like the default). With the confirmed
      `<branch>`, and only after your OK, run **just** this:
      - new:      `git -C <repo> checkout -b <branch>`
      - existing: `git -C <repo> switch <branch>`

      If you decline, **stop** without editing. Never create/switch without confirmation; never
      commit or push.
   e. If `<branch>` differs from what `tasks.md` records, **update** the "## Branches" line for this
      repo so `audit` and `prepare-pr` use the right branch.
4. **Apply the change** in that repo, **scoped** to this step; respect the repo's `AGENTS.md`/`CLAUDE.md`;
   do not touch unrelated files.
5. **Show the verify command(s)** for that repo — do **not** run them — from
   `.agents/skills/_shared/build-commands.md` and root `AGENTS.md`. Examples:
   - `docker compose exec -T eo make web-apps-dev`
   - `npm run "unit tests"` (in `server/`)
   - `cd sdkjs && python tests/code-style/check.py`
6. **Wait for you** to run them and report the result. If it fails, help diagnose, but do not auto-run
   fixes in a loop.
7. On your confirmation, mark the step `- [x]` in `tasks.md` and **stop** (one step per run).
8. **Remind** you that the commit is yours: Conventional Commits v1.0.0 + an `Assisted-by: AGENT:MODEL`
   trailer, and **never** `Signed-off-by` (see root `AGENTS.md` §Commits).

## Guardrails

- **Assisted mode:** the only git command `apply` runs is `checkout -b` / `switch` for the task branch,
  and only after you confirm. No build/test auto-run, no auto-heal, no commit, no push.
- **One step per invocation**, then stop.
- Watch the `web-apps*` locale JSON churn — do not stage it unless intended
  (`.agents/skills/_shared/build-commands.md`).
- Do not modify submodule contents against their own `CLAUDE.md`/`AGENTS.md`.

## References

- `.agents/skills/_shared/build-commands.md` · `repo-matrix.md` · `execution-profiles.md`
- Root `AGENTS.md` (§"Build & run a test server (Docker)", §Commits), `CONTRIBUTING.md`
- Prev: `breakdown` · Next: `audit`.
