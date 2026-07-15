# Build / lint / test commands (per repo)

> **POINTER, not duplication.** The server's start/build/verify workflow is authoritative in
> **`AGENTS.md`** (root), §"Build & run a test server (Docker)". **Always derive from there**; this
> sheet only adds what `AGENTS.md` does not cover (per-repo lint/test) and a quick target index.

## Server: start, in-container build, and verification

See `AGENTS.md` §"Build & run a test server (Docker)":
- **Start** → "Start the server" subsection (docker under `develop/`; healthcheck at `/healthcheck`).
- **Build** → "Build changes" subsection (in-container targets via `docker compose exec -T eo make <target>`).
- **Verify in a browser** → "Verify in a browser (Playwright MCP)" subsection.

`AGENTS.md` is the reference; follow whatever it says (e.g. do not use interactive `make`/`make local`
under `develop/`). This sheet **does not** contradict `AGENTS.md`.

### Quick index of in-container targets (source: `AGENTS.md` + `develop/setup/Makefile`)

| You change… | Target |
|---|---|
| web-apps (first time / deps) | `make web-apps` |
| web-apps (fast rebuild) | `make web-apps-dev` |
| sdkjs | `make sdkjs` |
| core (all) | `make core` |
| core (x2t only) | `make core/x2t` |
| server docservice | `make server/docservice` (or `server/converter`, `server/metrics`, `server/adminp`) |

⚠️ The `web-apps*` targets rewrite locale JSON (`translation/merge_and_check.py`). **Do not commit**
that churn unless intended (`audit` and `prepare-pr` watch for it).

## Lint / test per repo (what `AGENTS.md` does not cover)

**server** (in the `server/` repo, see `server/package.json`):
```sh
npm run lint:check      # eslint .
npm run format:check    # prettier . --check
npm run code:check      # both (lint + format)
npm run "unit tests"    # jest — the name has a space → it must be quoted!
```
Auto-fix: `lint:fix` / `format:fix` / `code:fix`. Integration: `"integration tests with server instance"`,
`"integration database tests"`.

**sdkjs**:
```sh
cd sdkjs && python tests/code-style/check.py    # code-style
```
QUnit: HTML tests under `sdkjs/tests/{word,cell,slide,pdf,common,oform,visio}/` (open in a browser).

**web-apps**: repo eslint/prettier; prioritize the *memory-leak sweep*
(`.agents/skills/_shared/memory-leak-checklist.md`).

**core**: C++/CMake build via `make core*` (above); see `core/AGENTS.md` for tests.

> Rule: if a repo's `AGENTS.md`/`CLAUDE.md` defines commands, **those win** over this sheet.
