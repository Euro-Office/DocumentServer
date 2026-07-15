---
name: breakdown
description: Turns a task's plan.md into tasks.md — atomic ~5-minute steps grouped by repo — and proposes (assisted) a feature/<task-id> branch per affected repo. Use after blueprint, when you have a plan and need an executable roadmap plus branches.
user-invokable: true
metadata:
  version: 0.1.0
---

# breakdown — roadmap + branches

> **Language rule (non-negotiable):** detect the language the human used when invoking this skill
> and use that language for ALL user-facing output. Default to **English** if unclear. Never output
> in a language that was not used in the invocation or the conversation history.

Second stage. Reads `plan.md` and produces `tasks.md`: a checklist of **atomic steps** (~5 minutes
each; the count flexes to the real size of the task), grouped by affected repo. It **proposes** the
branch command per repo but **does not run it** — the human confirms and executes.

> **Recommended execution:** plan mode. See `.agents/skills/_shared/execution-profiles.md` for
> recommended model and effort. State the profile to the human and how to switch
> (`/plan` or Shift+Tab · `/model` · `/effort`) before starting.

## Invocation

- `/breakdown` — infer the `task-id` from the current branch `feature/<task-id>`, else from the
  most recent `plan.md`. If ambiguous, **ask** which one.
- `/breakdown euoffice-5` — explicit task-id.

## Steps

1. **Resolve the `task-id`** (see `.agents/skills/_shared/task-ref-parsing.md` → "Inferring the
   task-id"). Ask if ambiguous.
2. **Read** `.ai/tasks/<task-id>/plan.md`. If missing, tell the user to run `blueprint` first.
3. **Decompose** the action plan into atomic steps: each ~5 minutes, independently verifiable,
   ordered by dependency, grouped by repo. Split anything larger; the number of steps is flexible.
4. **Propose branches (assisted).** For each affected repo, show — do not run:
   `git -C <repo> checkout -b feature/<task-id>`. Use descriptive branch names per `CONTRIBUTING.md`.
   The human confirms/executes.
5. **Write** `.ai/tasks/<task-id>/tasks.md` (template below), one `- [ ]` per atomic step, with the
   files touched and a verify hint (from `.agents/skills/_shared/build-commands.md`).

## Output — `.ai/tasks/<task-id>/tasks.md`

~~~markdown
# Tasks — <task-id>

Plan: `.ai/tasks/<task-id>/plan.md`

## Branches (assisted — run these yourself)
- web-apps: `git -C web-apps checkout -b feature/<task-id>`
- sdkjs:    `git -C sdkjs checkout -b feature/<task-id>`

## Steps
### web-apps
- [ ] <atomic step> — files: `apps/<editor>/…` — verify: `docker compose exec -T eo make web-apps-dev`
- [ ] <atomic step> — files: … — verify: …

### sdkjs
- [ ] <atomic step> — files: `common/…` — verify: `docker compose exec -T eo make sdkjs`
~~~

## Guardrails

- **Assisted mode:** propose the branch command; never run git, build, or commit.
- Keep steps **atomic and ordered**; one concern per step.
- Do not modify submodule contents here (that is `apply`); respect each repo's `CLAUDE.md`.

## References

- `.agents/skills/_shared/task-ref-parsing.md` · `build-commands.md` · `repo-matrix.md` · `execution-profiles.md`
- Root `AGENTS.md`, `CONTRIBUTING.md`
- Prev: `blueprint` · Next: `apply`.
