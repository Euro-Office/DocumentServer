# Task reference resolution (3 modes)

`blueprint [<ref>]` accepts the task in three ways. Detect the mode **in this order** and, if
anything is ambiguous or missing, **ask** (do not assume). GitHub is the primary path.

## Detection order

1. **GitHub** (primary path)
   - URL: `https://github.com/<owner>/<repo>/issues/<n>` (or `/pull/<n>`)
   - Short ref: `<owner>/<repo>#<n>`, or `<repo> #<n>` / `<repo>#<n>` (owner defaults to `Euro-Office`)
   - Examples: `web-apps #54`, `Euro-Office/web-apps#54`, `DocumentServer #38`
2. **Jira** — if GitHub does not match, look for a key with regex `\b[A-Z][A-Z0-9]+-\d+\b`
   - Key: `EUOFFICE-5`
   - URL: `…/browse/EUOFFICE-5`, or `…?selectedIssue=EUOFFICE-5`
3. **Manual** — if no ref is detectable: interactive intake (title + description + screenshots).

## task-id (slug)

| Mode | Example ref | `task-id` |
|---|---|---|
| GitHub | `web-apps #54` | `web-apps-54` |
| GitHub | `DocumentServer #38` | `documentserver-38` |
| Jira | `EUOFFICE-5` | `euoffice-5` |
| Manual | title "Fix crash on paste" | `fix-crash-on-paste` |

Slug rules: lowercase; spaces/`#`/`/`/`_` → `-`; strip accents and symbols; collapse repeated `-`;
trim to ~50 chars. The GitHub pattern is `<repo>-<n>`; Jira is `<key lowercased>`.

## Fetching the content

Depending on the mode, use `.agents/skills/_shared/integrations.md`:
- GitHub → `gh` CLI (or manual paste if there is no `gh`/auth).
- Jira → REST with `$JIRA_URL`/`$JIRA_PERSONAL_TOKEN` (or the future MCP; or manual paste).
- Manual → the user pastes text + screenshots (images read directly).

If the integration is unavailable → **fall back to manual paste** (never invent the content of an issue).

## Inferring the task-id from context (when no `<ref>` is passed)

1. Current branch `feature/<task-id>` → use that `task-id`.
2. Most recently modified `.ai/tasks/<task-id>/plan.md` → propose that one.
3. If still ambiguous → **ask** which one.
