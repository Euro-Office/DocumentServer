# Euro-Office E2E tests

Browser-level end-to-end tests for Euro-Office DocumentServer, built on [Playwright Test](https://playwright.dev/docs/intro). They exercise the example app and the Document, Spreadsheet and Presentation editors against a running server.

## Contents

- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Running the tests](#running-the-tests)
- [Configuration](#configuration)
- [How the test server is managed](#how-the-test-server-is-managed)
- [Test suites](#test-suites)
- [Reports and debugging](#reports-and-debugging)
- [Code quality](#code-quality)
- [Editor setup](#editor-setup)

## Repository layout

```
e2e/
├── frontend/
│   ├── playwright.config.ts   Playwright configuration (single `chromium` project)
│   ├── constants.ts           Host port, container name, default base URL
│   ├── global-setup.ts        Starts the Docker container, waits for readiness
│   ├── global-teardown.ts     Removes the container
│   └── tests/                 *.spec.ts files and shared helpers.ts
├── make.sh                    Format / lint / type-check / test wrapper
├── eslint.config.mjs          ESLint rules (typescript-eslint + Playwright plugin)
├── .prettierrc.json           Prettier rules
└── .editorconfig              Indentation and line endings
```

## Prerequisites

| Requirement | Version / note                                              |
| ----------- | ----------------------------------------------------------- |
| Node.js     | `^20.19`, `^22.13` or `>=24`                                |
| npm         | Bundled with Node.js                                        |
| Docker      | Required unless `E2E_BASE_URL` points to an existing server |
| Bash        | Only for `make.sh` (Git Bash on Windows)                    |

## Installation

All commands are run from the `e2e/` directory.

```sh
cd e2e
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
npm test -- tests/document-editing.spec.ts        # a single spec file
npm test -- --debug                               # Playwright Inspector, step through
npm test -- --ui                                  # interactive UI mode
npm test -- --retries=0 --workers=1               # override config for a local run
```

### Against an existing server

Set `E2E_BASE_URL` to skip Docker entirely, for example against the dev server started from `develop/` (see the root [`AGENTS.md`](../AGENTS.md)):

```sh
# bash / Git Bash
E2E_BASE_URL=http://localhost:8080 npm test
```

```powershell
# PowerShell
$env:E2E_BASE_URL = 'http://localhost:8080'; npm test
```

The target server needs `EXAMPLE_ENABLED=true`, as the tests drive `/example/`.

### Against a specific image

```sh
# bash / Git Bash
E2E_IMAGE=ghcr.io/euro-office/documentserver:dev E2E_HOST_PORT=9000 npm test

or

E2E_IMAGE=ghcr.io/euro-office/documentserver:latest npm test
```

```powershell
# PowerShell
$env:E2E_IMAGE = 'ghcr.io/euro-office/documentserver:dev'; $env:E2E_HOST_PORT = '9000'; npm test

or

$env:E2E_IMAGE = 'ghcr.io/euro-office/documentserver:latest'; $env:E2E_HOST_PORT = '8988'; npm test

```

## Configuration

All settings are environment variables; none are required.

| Variable             | Default                             | Description                                                 |
| -------------------- | ----------------------------------- | ----------------------------------------------------------- |
| `E2E_BASE_URL`       | `http://localhost:<E2E_HOST_PORT>`  | Test an existing server. When set, no container is started. |
| `E2E_IMAGE`          | `euro-office/documentserver:latest` | Image used for the managed container.                       |
| `E2E_HOST_PORT`      | `8988`                              | Host port mapped to container port 80.                      |
| `E2E_CONTAINER_NAME` | `euro-office-e2e`                   | Name of the managed container.                              |

Change `E2E_HOST_PORT` and `E2E_CONTAINER_NAME` together to run several suites in parallel on one host.

Test runner defaults (`frontend/playwright.config.ts`): test timeout 60 s, `expect` timeout 15 s, serial execution (`fullyParallel: false`), one retry, traces and video retained on first retry, screenshots on failure.

## How the test server is managed

Unless `E2E_BASE_URL` is set, `global-setup.ts`:

1. Removes any stale container named `E2E_CONTAINER_NAME` (`docker rm -f`).
2. Starts `E2E_IMAGE` detached with `-p <E2E_HOST_PORT>:80 -e EXAMPLE_ENABLED=true`.
3. Polls `GET /healthcheck` until it returns `true` (docservice ready).
4. Polls `GET /example/` until it returns 2xx (the example app is a separate supervised process and can lag behind the healthcheck).

Both polls time out after 5 minutes. `global-teardown.ts` removes the container once the run ends; containers it did not start are never touched.

To inspect a managed container while a run is in progress:

```sh
docker ps --filter name=euro-office-e2e
docker logs euro-office-e2e
docker exec euro-office-e2e supervisorctl status
```

If a run is killed before teardown, remove the leftover container manually:

```sh
docker rm -f euro-office-e2e
```

## Reports and debugging

| Output                     | Location                 | Open with                               |
| -------------------------- | ------------------------ | --------------------------------------- |
| HTML report                | `e2e/playwright-report/` | `npx playwright show-report`            |
| Traces, screenshots, video | `e2e/test-results/`      | `npx playwright show-trace <trace.zip>` |

Typical triage when a test fails:

1. Open the HTML report and inspect the trace (recorded on first retry).
2. Check server-side logs in the container: `docker logs euro-office-e2e`, or inside it under `/var/log/euro-office/documentserver/` (`docservice/out.log`, `converter/out.log`, `ds-example_out.log`).
3. Reproduce interactively with `npm test -- --debug -g "<test title>"`.

A passing HTTP 200 does not prove the editor opened. The editor shell can load while the document download fails, typically from a JWT secret mismatch (check `ds-example_out.log` and `converter/out.log`).

## Code quality

Formatting is enforced by [Prettier](https://prettier.io/), linting by [ESLint](https://eslint.org/), and types by `tsc`. Run the helper before every commit:

```sh
./make.sh          # same as `fix`
./make.sh fix      # format, lint with auto-fix, type-check
./make.sh check    # report only; modifies nothing (use in CI)
./make.sh test     # run the Playwright tests
```

On Windows use Git Bash, or `bash make.sh`.

### What `make.sh` runs

| npm command            | What it does                       | `./make.sh` (fix) | `./make.sh check` | `./make.sh test` |
| ---------------------- | ---------------------------------- | :---------------: | :---------------: | :--------------: |
| `npm run format`       | Prettier rewrites files            |         1         |         –         |        –         |
| `npm run format:check` | Prettier reports unformatted files |         –         |         1         |        –         |
| `npm run lint:fix`     | ESLint reports and fixes problems  |         2         |         –         |        –         |
| `npm run lint`         | ESLint reports problems            |         –         |         2         |        –         |
| `npx tsc --noEmit`     | Type-check only                    |         3         |         3         |        –         |
| `npm test`             | Playwright tests                   |         –         |         –         |        1         |

The numbers are the order in which each mode runs the commands. A dash means that mode doesn't run it. Only `fix` modifies files.

Behaviour of the script:

- Runs from `e2e/` regardless of your current directory.
- Runs `npm install` first if `node_modules/` is missing.
- Stops at the first failing step and exits non-zero.
- Any other argument prints a usage message and exits 1.
- `tsc` cannot auto-fix, so type errors always need a manual fix.

### Underlying npm scripts

| Script                 | Runs                       | What it does                             |
| ---------------------- | -------------------------- | ---------------------------------------- |
| `npm run format`       | `prettier --write .`       | Rewrites files to the project style      |
| `npm run format:check` | `prettier --check .`       | Lists files that are not formatted       |
| `npm run lint`         | `eslint .`                 | Reports code problems                    |
| `npm run lint:fix`     | `eslint . --fix`           | Reports problems and fixes the safe ones |
| `npx tsc --noEmit`     | TypeScript compiler        | Type-checks only; writes no files        |
| `npm test`             | `playwright test`          | Runs the tests headless                  |
| `npm run test:headed`  | `playwright test --headed` | Runs the tests with a visible browser    |

## Editor setup

Open the `e2e/` folder itself (File → Open Folder) so VS Code loads `e2e/.vscode/` and recommends:

- Prettier (`esbenp.prettier-vscode`)
- ESLint (`dbaeumer.vscode-eslint`)
- EditorConfig (`editorconfig.editorconfig`)
- Playwright Test (`ms-playwright.playwright`)

Workspace settings format and fix on save with the same rules as `make.sh`.
