# Euro-Office task pipeline — skills

Assisted, portable AI-agent skills covering the full lifecycle of a task —
**fetch/define → plan → implement → audit → prepare a PR** — for the Euro-Office DocumentServer
meta-repo. The skills **propose and show** commands; a **human** runs builds, commits, and PRs. They
work across **Claude Code, Codex, and Cursor**.

The canonical source lives here in `.agents/skills/`. The skills **do not duplicate** the
environment docs (`AGENTS.md`, `CONTRIBUTING.md`, per-repo `AGENTS.md`/`CLAUDE.md`) — they **link**
them.

## The skills

| Skill | Invoke | What it does | Output |
|---|---|---|---|
| `blueprint` | `/blueprint [<ref>]` | Onboard `gh`/Jira (first run) + fetch + investigate + define a task (GitHub / Jira / manual) | `.ai/tasks/<task-id>/plan.md` |
| `breakdown` | `/breakdown [<task-id>]` | plan.md → atomic ~5-min steps; propose a branch per affected repo | `.ai/tasks/<task-id>/tasks.md` |
| `apply` | `/apply` | Ensure the task branch (interactive — propose/create, you can rename it), apply the next step, show the build/test command; stop | (branch + code edit + `- [x]`) |
| `audit` | `/audit` · `/audit <owner>/<repo>#<n>` · `/audit <PR-URL>` | Security + code review + emulated quality gate + proposed PR comments — task diff **or** any open PR | task: `.ai/tasks/<task-id>/review.md` · PR: `.ai/reviews/<repo>-<n>/review.md` |
| `prepare-pr` | `/prepare-pr` | Prepare (never publish) the PR(s): body + `gh pr create` | `.ai/tasks/<task-id>/pr-<repo>.md` |

Artifacts are gitignored and cross-tool, split by concept:
- **Task workspace** — `.ai/tasks/<task-id>/` holds everything for a task you drive (`plan.md`,
  `tasks.md`, `review.md`, `pr-<repo>.md`), co-located so each stage feeds the next. `<task-id>` is a
  slug of the ref (`web-apps #54` → `web-apps-54`, `EUOFFICE-5` → `euoffice-5`, manual → slug of the
  title); skills infer it from the current branch `feature/<task-id>`, or ask.
- **Standalone PR reviews** — `.ai/reviews/<repo>-<n>/` holds `audit`'s output when reviewing an open
  PR. A PR review is **not** a task, so it never lives under `.ai/tasks/`.

## The flow

```
/blueprint <ref>   ->  plan.md     (onboards gh/Jira on first run; else manual paste)
   |
/breakdown         ->  tasks.md    (+ propose feature/<task-id> branches)
   |
/apply   (repeat)  ->  ensure branch (interactive) + one step; you run build/test; you commit
   |
/audit             ->  review.md   (security / code / quality gate)
   |
/prepare-pr        ->  PR body + `gh pr create` for you to run
```

Assisted mode throughout: the agent never runs builds/commits/PRs and never opens issues/PRs — it
proposes and you execute (the one exception: `apply` may create/switch the task branch after you
confirm). Contribution policy lives in `AGENTS.md` (§Commits, §Contribution policy) and
`CONTRIBUTING.md` (§AI-assisted contributions): Conventional Commits + `Assisted-by: AGENT:MODEL`,
**never** `Signed-off-by` (human DCO), AI-use disclosure in the PR, focused PRs, AGPL-3.0.

## Smart execution (mode / model / effort)

When a skill starts it **announces a recommended execution profile** — plan mode for planning stages,
a suggested model, and a suggested reasoning effort — plus how to switch (`/plan` or Shift+Tab ·
`/model` · `/effort`). You apply it: skills **recommend and remind, they don't enforce** (SKILL.md
frontmatter can't set model/effort/mode, and these are Claude-Code-specific). Skills also remind you
to **lower effort** if you'd raised it. Full table + how-to: `_shared/execution-profiles.md`.

## Onboarding (once per person)

The first `/blueprint` run offers to set up the integrations it needs. You can also run the helper
directly at any time:
- Linux / macOS / WSL / Git Bash: `bash scripts/setup-integrations.sh`
- Windows PowerShell: `powershell -File scripts/setup-integrations.ps1`

It detects your OS, installs `gh`, runs the interactive `gh auth login`, helps set the Jira env vars,
and self-checks. Everything is **per-person** and **never committed** (OSS). The only unavoidable
manual step is the interactive `gh auth login`. Without any of this, the skills still work via
**manual paste**. Per-platform matrix: `_shared/integrations.md`.

## Portability — how each tool discovers the skills

| Tool | Mechanism |
|---|---|
| **Codex / generic** | reads `.agents/skills/<name>/SKILL.md` directly (canonical) |
| **Claude Code** | `.claude/skills/<name>/SKILL.md` — a **real thin adapter** that points here |
| **Cursor** | `.cursor/rules/<name>.mdc` — a thin rule that points here |

> Why real adapters for Claude Code, not a symlink? Claude Code on Windows over `\\wsl.localhost`
> cannot follow WSL symlinks, and skill discovery does not resolve symlinks anyway (regression
> anthropics/claude-code #38051). So each `.claude/skills/<name>/SKILL.md` is a real file that
> redirects to the canonical playbook — a single source of truth is preserved.

## `_shared/` references (read, don't duplicate)

- `repo-matrix.md` — what lives in each submodule/repo + code anchors + build/lint per repo
- `task-ref-parsing.md` — GitHub / Jira / manual detection + task-id slug rules
- `integrations.md` — `gh` + Jira setup, cross-platform (Linux/macOS/Windows/WSL)
- `build-commands.md` — pointer to `AGENTS.md` + per-repo lint/test
- `sonar-quality-gate.md` — emulated quality-gate rubric (A–E, PASS/FAIL)
- `agpl-checklist.md` — AGPL-3.0 checks
- `memory-leak-checklist.md` — web-apps memory-leak sweep
- `execution-profiles.md` — recommended mode / model / effort per skill

Onboarding helper scripts live in `scripts/setup-integrations.{sh,ps1}`.

## Maintenance — editing or adding a skill

- **Edit** a skill's behavior: change only `.agents/skills/<name>/SKILL.md` (canonical). The Claude
  Code adapter and Cursor rule redirect here, so behavior updates with no re-sync. (If you change the
  `description`, also update it in the adapter/rule, since that one line is duplicated there.)
- **Add** a skill: create `.agents/skills/<name>/SKILL.md`, plus a real adapter at
  `.claude/skills/<name>/SKILL.md` (frontmatter + pointer) and a Cursor rule at
  `.cursor/rules/<name>.mdc`.
- **Frontmatter**: `name`, `description` (trigger-oriented), `user-invokable` (spelled with a **k**),
  and `metadata` (e.g. `version`). There is no top-level `version` key, and no `model`/`effort`/
  `permission-mode` key (those are recommendations in the body — see `_shared/execution-profiles.md`).
- Skills load at session start; a **new** Claude Code session is needed to pick up new/renamed skills.
  Use `/skills` to list discovered skills and `/doctor` to validate config.
