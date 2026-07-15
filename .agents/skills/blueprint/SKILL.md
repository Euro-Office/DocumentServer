---
name: blueprint
description: Fetches, investigates, and defines a Euro-Office task (GitHub issue, Jira key, or pasted description + screenshots) into a plan.md with the affected repos, an action plan, and Gherkin acceptance criteria; on first run it also onboards the gh/Jira integrations it needs. Use when starting a new task or when the request is under-specified and needs scoping before any coding.
user-invokable: true
metadata:
  version: 0.1.0
---

# blueprint — onboard (first run) + fetch + investigate + define

> **Language rule (non-negotiable):** detect the language the human used when invoking this skill
> and use that language for ALL user-facing output — questions, options, messages, and the
> `plan.md` summary. Default to **English** if the invocation language is unclear. Never output
> in a language that was not used in the invocation or the conversation history.

First stage of the Euro-Office pipeline. Turns a task reference (or a pasted description) into a
structured `plan.md`. On its **first run** on a machine it also sets up the integrations it needs
(GitHub `gh` / Jira). **Assisted mode:** it investigates and writes `plan.md`; it does **not** run
builds, commits, or PRs, and never opens issues/PRs. Interactive auth (`gh auth login`) and any
privileged install (`sudo`/`winget`) are the **human's** to run — never do them silently. When
anything is ambiguous, **ask; never assume**.

> **Recommended execution:** plan mode. See `.agents/skills/_shared/execution-profiles.md` for
> recommended model and effort. State the profile to the human and how to switch
> (`/plan` or Shift+Tab · `/model` · `/effort`) before starting.

Runs from the **DocumentServer** meta-repo, so it has whole-project context and can decide which
submodules/repos a task actually touches. No repo is privileged.

## Invocation

- `/blueprint web-apps #54`
- `/blueprint https://github.com/Euro-Office/web-apps/issues/54`
- `/blueprint EUOFFICE-5`
- `/blueprint https://<jira-instance>/browse/EUOFFICE-5`
- `/blueprint` (no ref → **interactive intake**: ask the user to paste a title + description +
  screenshots, or give an ID/URL)

## Steps

1. **Resolve the reference.** Follow `.agents/skills/_shared/task-ref-parsing.md` (detection order:
   GitHub → Jira → manual). Derive the `task-id` slug.
2. **Ensure integrations (first run), then fetch** — per `.agents/skills/_shared/integrations.md`:
   a. **Check readiness** in the tool's shell for the source you resolved: `gh auth status` (GitHub)
      or `echo "$JIRA_URL"` (Jira).
   b. **If the needed integration is missing/unauthed, offer one-time onboarding** — run the
      cross-platform helper (`bash scripts/setup-integrations.sh` on Linux/macOS/WSL/Git Bash, or
      `powershell -File scripts/setup-integrations.ps1` on Windows), or walk the human through the
      matching row of `integrations.md`. The interactive `gh auth login` and any `sudo`/`winget` are
      the **human's** to run — propose, never do them silently.
   c. **Fetch**: GitHub (primary) → `gh issue view … --json …`; Jira → REST with
      `$JIRA_URL`/`$JIRA_PERSONAL_TOKEN`.
   d. If the human declines onboarding, is offline, or the mode is manual → use the **pasted** title,
      description, and **screenshots** (read images directly). **Never invent** issue content.
3. **Interactive intake when needed.** If there is no ref, required info is missing, or a screenshot
   is unclear, **ask focused technical questions** before continuing. Do not guess intent.
4. **Investigate the codebase.** Using `.agents/skills/_shared/repo-matrix.md`, map task keywords to
   layers and confirm by reading/grepping the code anchors (`web-apps/apps/*`, `sdkjs/common/`,
   `server/Common/sources/`, `core/…`). Read the `AGENTS.md`/`CLAUDE.md` of each involved repo
   (root `AGENTS.md` always; per-repo docs when present — they may be absent today).
5. **Determine the affected repos** (may be several) and note the specific files/dirs in scope.
6. **Assess readiness.** Confirm there is: a clear action plan, defined inputs/outputs, and testable
   acceptance criteria. Fill gaps by asking, not assuming. For complex/multi-subsystem work, note in
   `plan.md` that a discussion ticket should be opened first (per `AGENTS.md` policy) — but **do not
   open it**; that is the human's action.
7. **Write** `.ai/tasks/<task-id>/plan.md` (always produced) using the template below.

## Output — `.ai/tasks/<task-id>/plan.md`

~~~markdown
# <Task title>

- **Source:** <GitHub/Jira/manual> · <link or "pasted">
- **task-id:** <task-id>
- **Status/type/labels:** <if known>

## Summary
<1–3 sentences: the problem and the intended outcome, in your own words.>

## Investigation
<What was read/grepped, key findings, root cause or the relevant mechanism. Reference files as
`repo/path/file.ext`.>

## Affected repos
| Repo | Why | Files/areas in scope |
|---|---|---|
| web-apps | … | `apps/<editor>/…` |
| sdkjs | … | `common/…` |

## Action plan
1. <high-level step> (repo)
2. …

## Inputs / Outputs
- **Inputs:** <data, config, user actions>
- **Outputs:** <observable result, files, API>

## Acceptance criteria (Gherkin)
Scenario: <name>
  Given <context>
  When <action>
  Then <expected result>

## Open questions
- <anything still ambiguous / awaiting human decision>
~~~

## Guardrails

- **Assisted mode:** investigate + write `plan.md` only. Do not build, commit, branch, or open
  anything. For integration onboarding, propose/run the helper but leave interactive auth
  (`gh auth login`) and privileged installs (`sudo`/`winget`) to the human — never enter tokens or
  secrets on their behalf, and never commit secrets.
- **Ask, don't assume** when ambiguous (including unclear screenshots).
- **Never invent** issue content; fall back to manual paste if a source is unreachable.
- **Do not duplicate** `AGENTS.md`/`CLAUDE.md` — read and link them.
- Keep `.ai/` local (it is gitignored); no secrets in `plan.md`.

## References

- `.agents/skills/_shared/task-ref-parsing.md` · `integrations.md` · `repo-matrix.md` · `execution-profiles.md`
- Onboarding helper: `scripts/setup-integrations.sh` · `scripts/setup-integrations.ps1`
- Root `AGENTS.md`, `CONTRIBUTING.md`; per-repo `AGENTS.md`/`CLAUDE.md`
- Next stage: `breakdown`.
