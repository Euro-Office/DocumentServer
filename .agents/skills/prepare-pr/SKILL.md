---
name: prepare-pr
description: Prepares (never publish) the PR(s) for the current task — drafts each affected repo's PR body from plan.md with the source link and an AI-use disclosure, and shows the gh pr create command for the human to run. Prepare-only; no auditing here.
user-invokable: true
metadata:
  version: 0.1.0
---

# prepare-pr — prepare only (never submit)

> **Language rule (non-negotiable):** detect the language the human used when invoking this skill
> and use that language for ALL user-facing output. Default to **English** if unclear. Never output
> in a language that was not used in the invocation or the conversation history.

Final stage. **Prepares** the pull request(s) for the human to review and submit. It **never** opens
a PR, posts comments, or submits anything autonomously (root `AGENTS.md` §"Contribution policy").
No auditing happens here — that lives in the audit stage (`audit`).

> **Recommended execution:** normal mode. See `.agents/skills/_shared/execution-profiles.md` for
> recommended model and effort. State the profile to the human before starting; remind them to lower
> effort if they had raised it.

## Invocation

- `/prepare-pr` — prepare the PR(s) for the current task-id.

## Steps

1. **Resolve the `task-id`** and read `.ai/tasks/<task-id>/plan.md` (and `review.md` if present, only
   to reference audit status — do not re-audit).
2. **Identify affected repos** and their `feature/<task-id>` branches (or the branch names recorded in
   `tasks.md` "## Branches" if they were customized).
3. **(Optional) Propose history cleanup** to Conventional Commits: show the suggested squash/reword;
   the **human** performs it. Ensure each AI-assisted commit has an `Assisted-by: AGENT:MODEL`
   trailer. **Never** add `Signed-off-by` — only the human certifies the DCO.
4. **Draft the PR body per repo** into `.ai/tasks/<task-id>/pr-<repo>.md`:
   - Problem + approach (from `plan.md`), scoped to one concern.
   - Link to the source issue/Jira.
   - Testing done (note: the human tests on a live instance, per `CONTRIBUTING.md`).
   - An **AI-use disclosure** — provide a draft the human rewrites **in their own words**
     (PR text must be the contributor's own words; the agent must not ghostwrite it as final).
   - If the diff is large, **warn** and suggest splitting into focused PRs.
5. **Show the command** (do not run it):
   ```sh
   gh pr create --repo Euro-Office/<repo> --base main --head feature/<task-id> \
     --title "<conventional title>" --body-file .ai/tasks/<task-id>/pr-<repo>.md
   ```
   If `gh` is not set up, onboard it first (`scripts/setup-integrations.sh` / `.ps1`, or
   `.agents/skills/_shared/integrations.md`), or output the body for **manual paste** into the GitHub UI.
6. **Stop.** The human reviews, finalizes the wording, and runs the command / opens the PR.

## Guardrails

- **Prepare-only:** never run `gh pr create`, never open/comment on PRs or issues.
- **AI disclosure and PR text in the human's own words** — the skill drafts, the human owns it.
- **Never** `Signed-off-by`. Focused PRs. Verify dependencies against real registries. Comply AGPL-3.0.
- No auditing here (see `audit`).

## References

- `.agents/skills/_shared/integrations.md` (gh) · `agpl-checklist.md` · `execution-profiles.md`
- Onboarding helper (if `gh` missing): `scripts/setup-integrations.sh` · `scripts/setup-integrations.ps1`
- Root `AGENTS.md` (§Commits, §"Contribution policy"), `CONTRIBUTING.md` (§"AI-assisted contributions")
- Prev: `audit`.
