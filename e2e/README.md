# Euro-Office E2E tests

Browser-level end-to-end tests for Euro-Office DocumentServer, built on [Playwright Test](https://playwright.dev/docs/intro). They exercise the example app and the Document, Spreadsheet and Presentation editors against a running server.

## Contents

- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Running the tests](#running-the-tests)
- [Code quality](#code-quality)

## Repository layout

```
e2e/
├── frontend/
│   ├── playwright.config.ts   Playwright configuration (single `chromium` project)
│   ├── constants.ts           Host port, container name, default base URL
│   ├── global-setup.ts        Starts the Docker container, waits for readiness
│   ├── global-teardown.ts     Removes the container
│   └── tests/                 *.spec.ts files and shared helpers.ts
├── eslint.config.mjs          ESLint rules (typescript-eslint + Playwright plugin)
├── .prettierrc.json           Prettier rules
├── .editorconfig              Indentation and line endings
└── .gitignore                 Also read by Prettier, which ignores the generated folders
```

## Prerequisites

| Requirement | Version / note                                              |
| ----------- | ----------------------------------------------------------- |
| Node.js     | `^20.19`, `^22.13` or `>=24`                                |
| npm         | Bundled with Node.js                                        |
| Docker      | Required unless `E2E_BASE_URL` points to an existing server |

## Installation

All commands are run from the `e2e/` directory.

```sh
npm ci                          # install exact versions from package-lock.json
npx playwright install chromium # download the browser binary
```

Use `npm install` instead of `npm ci` only when you intend to change dependencies.

## Running the tests

```sh
npm test                 # all tests, headless
npm run test:headed      # all tests, visible browser
```

Run a subset by passing Playwright CLI arguments after `--`:

```sh
npm test -- tests/document-editing.spec.ts   # a single spec file
npm test -- -g "<test title>"                # tests matching a title
npm test -- --debug                          # Playwright Inspector, step through
npm test -- --ui                             # interactive UI mode
npm test -- --retries=0 --workers=1          # override config for a local run
```

### Against an existing server

Set `E2E_BASE_URL` to skip Docker entirely, for example against the dev server started from `develop/` (see the root [`AGENTS.md`](../AGENTS.md)). The server needs `EXAMPLE_ENABLED=true`, as the tests drive `/example/`.

```sh
E2E_BASE_URL=http://localhost:8080 npm test                     # bash / Git Bash
```

```powershell
$env:E2E_BASE_URL = 'http://localhost:8080'; npm test           # PowerShell
```

### Against a specific image

```sh
E2E_IMAGE=ghcr.io/euro-office/documentserver:dev E2E_HOST_PORT=9000 npm test
```

## Code quality

Formatting is enforced by Prettier, linting by ESLint and types by `tsc`. Run the checks before every commit:

```sh
npm run check    # report only; modifies nothing
npm run fix      # format, lint with auto-fix, type-check
```

The rules live in [`eslint.config.mjs`](eslint.config.mjs), [`.prettierrc.json`](.prettierrc.json) and [`.editorconfig`](.editorconfig). `tsc` cannot auto-fix, so type errors always need a manual fix.
