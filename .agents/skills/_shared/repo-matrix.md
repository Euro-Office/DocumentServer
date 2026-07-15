# Repo matrix — what lives in each repo and how it is built/verified

> **Source of truth per repo:** the `AGENTS.md` and `CLAUDE.md` **of each submodule** (read them at
> runtime; some are still under review on GitHub and may be absent today — use this matrix as a
> fallback). Build/lint/test commands → `.agents/skills/_shared/build-commands.md`.

DocumentServer is the **master meta-repo**: it aggregates every submodule via `.gitmodules`. The
skills live here to have the **full context** and to **break down which repos each task affects**.
No repo is a privileged pilot.

## Submodules (11) — all under the `Euro-Office` org

| Submodule | What lives there | Code anchors | Build target (in-container) | Lint / test |
|---|---|---|---|---|
| `core` | C++ conversion/render engine (x2t, fonts, DocxRenderer, doctrenderer, WASM) | `core/OOXML/`, `core/OdfFile/`, `core/X2tConverter/`, `core/DocxRenderer/`, `core/DesktopEditor/`, `core/Common/` | `make core` (subsets: `core/x2t`, `core/allfontsgen`, `core/wasm`, …) | C++/CMake — see `core/AGENTS.md` |
| `core-fonts` | Bundled fonts | `core-fonts/` | (via `core/allfontsgen`) | — |
| `sdkjs` | JavaScript SDK for the editors (word/cell/slide/pdf/visio) | `sdkjs/common/`, `sdkjs/word/`, `sdkjs/cell/`, `sdkjs/slide/`, `sdkjs/pdf/` | `make sdkjs` | `python tests/code-style/check.py`; QUnit in `sdkjs/tests/` |
| `sdkjs-forms` | OForm layer (fillable forms) on top of sdkjs | `sdkjs-forms/` (integrated via `configs/word.json`) | (part of `make sdkjs`) | see `sdkjs-forms/AGENTS.md` |
| `server` | Node.js backend (co-editing, storage, conversion, metrics, auth/JWT) | `server/Common/sources/` (`storage/`, `signing/`, `logger.js`…), `server/DocService/`, `server/FileConverter/` | `make server/docservice` (+ `server/converter`, `server/metrics`, `server/adminp`) | `npm run lint:check` / `format:check` / `code:check` / `"unit tests"` |
| `web-apps` | Editors UI (front-end) | `web-apps/apps/{api,common,documenteditor,spreadsheeteditor,presentationeditor,pdfeditor,visioeditor}` | `make web-apps` (first time) / `make web-apps-dev` (fast) | repo eslint/prettier; *memory-leak sweep* |
| `dictionaries` | Hunspell dictionaries (45+ locales) | `dictionaries/<locale>/` | — | strict LF + UTF-8 — see `dictionaries/AGENTS.md` |
| `document-formats` | Format definitions/resources | `document-formats/` | — | see `document-formats/AGENTS.md` |
| `document-templates` | Document templates | `document-templates/` | — | — |
| `document-server-package` | Packaging/distribution (DEB/RPM/EXE/TAR) | `document-server-package/` | — (release only) | — |
| `document-server-integration` | Integrations/examples (Nextcloud, WOPI, …) | `document-server-integration/` | — | see its `AGENTS.md` |

## Org repos that are NOT local submodules

They can be the target of a task even though they are not in `.gitmodules` (clone them separately if
needed): `DesktopEditors`, `internal`, `issue-taxi`, and others under `github.com/Euro-Office`. Treat
them the same way: read their `AGENTS.md`/`CLAUDE.md`, derive their commands, and propose them as
affected repos.

## How to determine which repos a task affects

1. Task keywords → layer:
   - UI, toolbar, panel, dialog, editor i18n → **web-apps** (`apps/<editor>/`)
   - Editor logic / JS API / collaboration → **sdkjs** (`common/`, `<editor>/`)
   - Fillable forms → **sdkjs-forms**
   - Format conversion / render / fonts / x2t → **core**
   - Co-editing, storage, server-side conversion, auth/JWT, metrics → **server** (`Common/sources/`)
   - Spellcheck / dictionaries → **dictionaries**
   - Packaging / installers → **document-server-package**
   - Integration (Nextcloud, WOPI, examples) → **document-server-integration**
2. Confirm by grepping/reading the anchors (above) before locking the list.
3. A task may touch **several** repos (e.g. a UI feature that needs an API in sdkjs). `blueprint`
   lists them all; `breakdown` proposes one `feature/<task-id>` branch per affected repo.
