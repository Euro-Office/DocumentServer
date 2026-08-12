## What this repo is

DocumentServer is the master orchestrator for the Euro-Office ecosystem. It manages all submodules, docker orchestration, and workspace-level build configurations.

This repo holds the workspace configuration for the submodules:
- `core`, `core-fonts`, `sdkjs`, `sdkjs-forms`, `server`, `web-apps`, `dictionaries`, `document-formats`, `document-server-integration`, `document-server-package`, `document-templates`.

Any change to the orchestration (e.g., updating a submodule commit, modifying `docker-bake.hcl`, or changing the build order) requires a full verification of the dependency chain.

## Architecture notes

### Submodule dependency chain

Changes flow in one direction — everything downstream needs rebuilding:

```
core-fonts → core/AllFontsGen → sdkjs (AllFonts.js) → web-apps → server → Docker image
```

Each submodule has its own `AGENTS.md` with repo-specific guidance.

The Nextcloud integration app lives in the **sibling repo `eurooffice-nextcloud`**, mounted read-only into the dev container.

> **Shared submodules**: `core`, `sdkjs`, `web-apps`, `core-fonts`, and `sdkjs-forms` are also submodules of the **`DesktopEditors`** product (the Windows/Mac/Linux desktop app). A change merged to any of those repos affects both DocumentServer and DesktopEditors.

## Rules

- **Never** modify submodule contents directly from here without verifying the target submodule's own `AGENTS.md`.
- **Never** introduce workspace-wide dependencies that break the "no root package.json" rule in submodules.
- **Never** commit changes to `docker-bake.hcl` without validating the build orchestration for all platforms.
- **Always** verify that `AGENTS.md` is updated if you modify workspace-level developer workflows.
- **Never** update submodule refs manually via a PR — submodule bumps are handled by an automated GitHub Action.

## Build & run a test server (Docker)

The dev environment in `develop/` runs a full document server from a prebuilt image. Individual components are rebuilt *inside* the container — never rebuild the docker image to test a change. The repo is bind-mounted at `/develop` in the container, so edits on the host are immediately visible inside.

### Start the server

```sh
cd develop
docker compose pull eo     # one-time; multi-arch (amd64/arm64)
docker compose up -d eo    # document server only; add `nextcloud` for the connector flow
```

If the pull fails (GHCR auth), build locally once: `cd build && docker buildx bake develop`.

Do not use `make`/`make local` in `develop/` — those exec into an interactive shell. Use `docker compose exec -T eo <cmd>` for everything.

Wait until ready (returns `true`):

```sh
curl -sf http://localhost:8080/healthcheck
```

### Build changes

Run targets from the in-container Makefile (mounted at `/Makefile`; default workdir is `/`). Each target builds the component from `/develop`, deploys it into the installed tree, and restarts the affected service:

```sh
docker compose exec -T eo make web-apps           # full web-apps build (installs npm deps; needed once first)
docker compose exec -T eo make web-apps-dev       # fast rebuild, skips npm install/babel/imagemin
docker compose exec -T eo make sdkjs              # closure compile + allfontsgen
docker compose exec -T eo make core               # all of core; subsets: core/x2t, core/allfontsgen, ...
docker compose exec -T eo make server/docservice  # also: server/converter, server/metrics, server/adminp
```

For changes spanning several submodules, run the targets back to back (e.g. `make sdkjs web-apps`). First run of each target installs npm deps and is slow; later runs are faster. Core builds are incremental (ninja) only for the lifetime of the container. `web-apps`/`sdkjs` targets flush the nginx cache tag automatically.

Note: builds run against the bind-mounted checkout and can modify it — the web-apps targets run `translation/merge_and_check.py`, which rewrites locale JSON files in the working tree. Don't commit those changes unless intended.

Troubleshooting: if `make` fails with `Makefile: No such file or directory`, the single-file bind mount of `develop/setup/Makefile` went stale (editing that file on the host replaces its inode). Fix with `docker compose up -d --force-recreate eo` — this also resets all in-container build/deploy state, so previously built components revert to the image's versions and need rebuilding.

### Test the change

- **Example app** (no Nextcloud needed): open `http://localhost:8080/example/` — create a document, spreadsheet, or presentation and open it in the editor. The welcome page is at `http://localhost:8080/`.
- **Service status & logs**: `docker compose exec -T eo supervisorctl status`; logs live under `/var/log/euro-office/documentserver/` (e.g. `docservice/out.log`, `converter/out.log`, `ds-example_out.log`).
- **Conversion check**: opening a `.docx`/`.xlsx` in the example app exercises FileConverter + x2t; watch `converter/out.log` for errors.
- **Nextcloud connector flow** (only when testing the integration): `docker compose up -d`, then `make refresh-urls` to wait for install and wire URLs/JWT; Nextcloud at `http://localhost:8081/` (admin/admin).

### Running instances (`eo.sh`)

`develop/eo.sh` runs one or more test servers as self-contained containers from the same image — current tree mounted at `/develop`, auto-assigned port. Starts detached (agent-friendly, unlike `make local`):

```sh
cd develop
./eo.sh up <name>                  # start; waits for /healthcheck; prints URL + per-type editor URLs
./eo.sh build <name> web-apps-dev  # in-container make targets (sdkjs, core/x2t, server/docservice, …)
./eo.sh exec <name> <cmd…>         # run inside (TTY-aware)
./eo.sh ls | logs <name> | down <name>|--all   # manage; `up --force` to recreate
```

Run a building instance from its own git worktree so builds don't share `node_modules`; a fresh worktree needs `git submodule update --init --recursive` first. JWT (secret `euro-office-dev-jwt-secret-key-2026`), `EXAMPLE_ENABLED` and `WOPI_ENABLED` are on, so the example app works out of the box.

### Verify in a browser (Playwright MCP)

Don't trust HTTP 200 — the editor shell can load while the document download fails. `browser_navigate` to a create-new URL (`…/example/editor?fileExt=docx|xlsx|pptx|pdf`; `?fileName=` expects an existing file and fails), `browser_wait_for` a few seconds, then `browser_snapshot`/`browser_take_screenshot` to confirm the toolbar and page render with no error dialog, plus `browser_console_messages` at level `error`. If it won't open, check `ds-example_out.log` (JWT) and `converter/out.log` (download 403) — usually a JWT secret mismatch.

## Commits

- Commit messages must follow the Conventional Commits v1.0.0 specification — e.g. feat(chat): add voice message playback, fix(call): handle MCU disconnect gracefully.
- Every commit containing AI-assisted content must include an `Assisted-by:` trailer identifying the coding agent and the model(s) used:
    Pattern: Assisted-by: AGENT_NAME:MODEL_VERSION (e.g. Assisted-by: ClaudeCode:claude-opus-4-8)
    Add one `Assisted-by:` line per agent/model if more than one was used.

## Contribution policy

All contributions generated or assisted by this agent must fully comply with:

- **[AI Contribution Policy](https://github.com/Euro-Office/.github/blob/main/AI_POLICY.md)** — the primary reference for AI-specific rules, covering disclosure, author accountability, communication, security, licensing, code quality, and autonomous agent behavior.
- **[Contribution Guidelines](CONTRIBUTING.md)** — covering testing requirements, sign-off, license headers, and the review process. These apply in full to all contributions regardless of how they were produced.

### What this agent must always do

- Add an `Assisted-by: AGENT_NAME:MODEL_VERSION` git trailer to every commit containing AI-assisted content.
- Ensure every pull request includes a disclosure of AI tool use in the PR description.
- Produce focused, scoped pull requests that address exactly one concern. Do not touch unrelated files or introduce incidental refactors.
- Verify all dependencies against actual package registries before suggesting them. Do not use hallucinated or unverified package names.
- Explicitly inform the contributor when any action they are about to take, or have taken, would violate the AI Contribution Policy or the Contribution Guidelines. Do not silently proceed. State which rule is at risk and what the contributor should do instead.
- Warn the contributor if a pull request is growing too large. A PR approaching several thousand lines of changed code is a signal that it should be split into smaller, focused PRs. Suggest a logical split before the PR is opened, not after.
- Recommend opening a ticket for discussion before starting implementation whenever a feature or change is sufficiently complex — for example when it touches multiple subsystems, requires architectural decisions, or the right approach is not yet clear.

### What this agent must never do

- Open issues, submit pull requests, post review comments, or send security reports autonomously. Every contribution must be reviewed and submitted by a human.
- Add `Signed-off-by` tags to commits. Only the human contributor can certify the Developer Certificate of Origin.
- Generate or submit security reports without independent human verification. Report verified vulnerabilities privately by email to the maintainers (`euro-office-team` on the `proton.me` mail server), not as GitHub issues.
- Write PR descriptions, review comments, or issue reports on behalf of the contributor. These must be in the contributor's own words.
- Fully automate the resolution of issues labeled [`good first issue`](https://github.com/search?q=org%3AEuro-Office+label%3A%22good+first+issue%22&type=issues) or similar beginner-friendly labels.
- Submit code that has not been reviewed and cleaned up by the contributor. Dead code, redundant logic, excessive comments, and unrelated changes must be removed before submission.
