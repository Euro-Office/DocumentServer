# Integrations (personal) — NEVER committed (this is OSS)

## Contents

- [Which shell actually runs the fetch?](#which-shell-actually-runs-the-fetch)
- [GitHub — `gh` CLI (primary path)](#github--gh-cli-primary-path): install · authenticate · fetch
- [Jira — direct REST (current solution)](#jira--direct-rest-current-solution): set env vars · fetch
- [Jira — MCP `mcp-atlassian` (professional upgrade, future)](#jira--mcp-mcp-atlassian-professional-upgrade-future)
- [Quick self-check](#quick-self-check)
- [Fallback](#fallback)

No credential, instance, or config containing secrets may be **committed**. Everything lives in the
**user's shell profile / OS keychain** or in **local** config (never `project` scope). If nothing is
available, fall back to **manual paste**.

These skills are used by an **international team on Linux, macOS, Windows, and WSL**. The fetch
**commands** below are identical on every platform — only the **install step** and **where you set
env vars / PATH** differ. Pick your platform from the tables.

**Fastest path (recommended):** run the onboarding helper once — `bash scripts/setup-integrations.sh`
(Linux/macOS/WSL/Git Bash) or `powershell -File scripts/setup-integrations.ps1` (Windows). `blueprint`
also offers this on its first run. It automates the install + auth + env + self-check described below.

## Which shell actually runs the fetch? (read this first)

The agent runs `gh`/`curl` in **the shell your AI tool uses**, and `gh` + env vars must be available
**there**:
- Native **Linux / macOS**: your login shell (bash/zsh).
- Native **Windows**: usually **Git Bash** (bundled with the AI tool). It inherits Windows PATH and
  Windows user env vars.
- **Windows editing a repo inside WSL** (repo under `\\wsl.localhost\...`): the tool may run **Git
  Bash on Windows** even though the code is in WSL. Then `gh` must be installed **for Windows**, not
  only in WSL. If you prefer to keep everything in WSL, install `gh` in WSL and have the agent call
  `wsl gh …` / `wsl curl …`.

**Rule of thumb:** run `gh --version` in the same shell the tool uses. If it says *command not
found*, install `gh` for **that** environment (see table). Same idea for `echo "$JIRA_URL"`.

## GitHub — `gh` CLI (primary path)

### 1) Install (pick your platform)

| Platform | Command |
|---|---|
| macOS | `brew install gh` |
| Debian / Ubuntu / **WSL** | `sudo apt install gh` (for the latest, add the official gh apt repo) |
| Fedora / RHEL | `sudo dnf install gh` |
| Arch | `sudo pacman -S github-cli` |
| **Windows** | `winget install --id GitHub.cli` (or `scoop install gh` / `choco install gh`) |

Official install matrix: <https://github.com/cli/cli#installation>. After a Windows install, **reopen**
the tool so Git Bash picks up the new PATH.

### 2) Authenticate (once, any platform)

```sh
gh auth login          # GitHub.com · HTTPS · account with access to the Euro-Office org (incl. private repos like `internal`)
gh auth status         # verify
```
Non-interactive / CI alternative: export a PAT (repo scope) as `GH_TOKEN` (or `GITHUB_TOKEN`) instead
of `gh auth login`.

### 3) Fetch (identical on every platform)

```sh
gh issue view <n> --repo <owner>/<repo> \
  --json title,body,comments,labels,state,assignees,url
```
(`<owner>` defaults to `Euro-Office`.) For PRs: `gh pr view <n> --repo … --json …`.
No `gh` / not authed / no access to a private repo → **manual paste**.

## Jira — direct REST (current solution)

**Server/Data Center** instance → **PAT + `Bearer`**, REST **v2**, description in **wiki-markup**
(not ADF). The skill reads `$JIRA_URL` → **instance-agnostic**.

### 1) Set the env vars (per platform — never in the repo)

| Shell / platform | Where | How (reopen the shell afterwards) |
|---|---|---|
| bash — Linux / **WSL** | `~/.bashrc` | `export JIRA_URL="https://<instance>"` / `export JIRA_PERSONAL_TOKEN="<PAT>"` |
| zsh — macOS (default) | `~/.zshrc` | same `export …` lines |
| **Git Bash** — Windows | `~/.bashrc` (= `%USERPROFILE%\.bashrc`) | same `export …` lines |
| Windows (system-wide) | user env vars | `setx JIRA_URL "https://<instance>"` then `setx JIRA_PERSONAL_TOKEN "<PAT>"` (Git Bash inherits them; reopen) |

Check: `echo "$JIRA_URL"` prints a value (not empty).

### 2) Fetch (identical on every platform)

```sh
curl -sf -H "Authorization: Bearer $JIRA_PERSONAL_TOKEN" \
  "$JIRA_URL/rest/api/2/issue/<KEY>?fields=summary,description,status,issuetype,comment,attachment,labels,priority"
```
Lightweight wiki-markup → markdown conversion (`h1.`→`#`, `*bold*`, `{code}`→fenced block, `#`/`*`
lists). Without the env vars → **manual paste**. (`curl` ships with macOS/Linux and Git Bash.)

## Jira — MCP `mcp-atlassian` (professional upgrade, future)

Only if you want JQL/boards. Docker + **local** registration with env pass-through (no secrets in config):
```sh
claude mcp add jira --scope local \
  -e JIRA_URL -e JIRA_PERSONAL_TOKEN \
  -- docker run -i --rm -e JIRA_URL -e JIRA_PERSONAL_TOKEN <mcp-atlassian-image>
```
(Verify the image against its real registry before using it — Euro-Office policy: nothing unverified.)
**Never** in `project` scope nor in a committed `.mcp.json` (it would expose/force config on the whole repo).

## Quick self-check (run in the tool's shell)

```sh
gh --version && gh auth status        # GitHub ready?
echo "${JIRA_URL:-<unset>}"           # Jira URL present?
```

## Fallback

Preference per source: integration available → if it fails / is absent → **manual paste** (title +
description + screenshots). **Never invent** the content of an issue.
