# Euro-Office E2E tests

Browser-level end-to-end tests for Euro-Office DocumentServer, built on [Playwright Test](https://playwright.dev/docs/intro). They exercise the example app and the Document, Spreadsheet, Presentation and PDF form editors (plus a mobile smoke test) against a running server.

## Contents

- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Running the tests](#running-the-tests)
- [Test tags](#test-tags)
- [Code quality](#code-quality)

## Repository layout

```
e2e/
├── frontend/
│   ├── playwright.config.ts   Playwright configuration (single `chromium` project, 4 workers)
│   ├── constants.ts           Host port, container name, default base URL
│   ├── global-setup.ts        Starts the Docker container, waits for readiness
│   ├── global-teardown.ts     Saves the server logs, then removes the container
│   ├── timeouts.ts            The editor wait timeouts and the per-test timeout derived from them
│   ├── fixtures/              fixture.docx/.xlsx/.pptx/.pdf, and make-fixtures.py which writes them
│   └── tests/
│       ├── document/          create-, save-, edit-, open-, delete-document, document-editing
│       ├── spreadsheet/       create-, save-, edit-, open-, delete-spreadsheet, spreadsheet-formula
│       ├── presentation/      create-, save-, edit-, open-, delete-presentation, presentation-slides
│       ├── pdf-form/          create-, save-, edit-, delete-pdf-form, open-pdf
│       ├── mobile/            mobile-editor
│       ├── example-page.spec.ts
│       ├── final-save.spec.ts            Final save with several editors closed together, an early reopen and two tabs
│       ├── stored-file-delete.suite.ts   The deletion scenario the four delete-* specs share
│       ├── open-stored-fixture.suite.ts  The scenario the four open-* specs share
│       └── helpers.ts         Shared editor, stored-file, fixture-upload and content-reading
│                              helpers used by every spec
├── eslint.config.mjs          ESLint rules (typescript-eslint + Playwright plugin)
├── .prettierrc.json           Prettier rules
├── .editorconfig              Indentation and line endings
└── .gitignore                 Also read by Prettier, which ignores the generated folders
```

The `create-*` and `save-*` specs cover the create-new route (`?fileExt=`); the
`edit-*`, `open-*` and `delete-*` specs cover a file that is already on the
server (`?fileName=`), reached by clicking it in "Your documents".

### Fixtures

The `open-*` specs upload a file from `frontend/fixtures/` and check the editor
shows exactly what is in it. Each fixture is the smallest valid file of its
type holding one known string. `make-fixtures.py` writes them from raw XML, and
the PDF from raw PDF syntax, rather than saving them out of an editor, so a
fault in our own writer cannot bake itself into the oracle. The strings live in
`FIXTURE_TEXT` in both that script and `tests/helpers.ts`; change one, change
the other, then rebuild:

```sh
python3 -I frontend/fixtures/make-fixtures.py
```

`uploadFixtureFile` checks each fixture holds its `FIXTURE_TEXT` string before
uploading it, so drifted strings or a fixture left unrebuilt fail as that,
rather than as an editor content mismatch. The OOXML packages are stored
uncompressed and the PDF content stream is left uncompressed, to keep that
check a plain byte search; they are a few KB either way.

The file store is server-side and shared by every spec (it is keyed by client
IP) while spec files run in parallel workers, so a spec may only assert on rows
it created itself, never on the list as a whole. The create-new route hands out
the lowest free name, so a name freed by a delete can be handed straight to
another worker: the delete specs therefore upload under a generated unique name
(`uniqueFileName`), and cleanup waits for a file to stop changing before
removing it. Each spec deletes what it created in `afterAll`, which matters
when running against a long-lived server via `E2E_BASE_URL`.

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
npm test -- tests/pdf-form                   # all specs in one folder
npm test -- tests/document/document-editing.spec.ts   # a single spec file
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

### Server logs

When the tests start the container themselves, teardown copies its logs into `e2e/server-logs/` before removing it: `container.log` (`docker logs`) plus the contents of `/var/log/euro-office/documentserver` (docservice, converter, nginx, example app). When a test times out waiting for an editor, these show whether the server was slow (conversions queued) or broken (errors). The folder is cleared at the start of each save, so it only holds the last run, and it is gitignored.

In CI it is uploaded as its own artifact, `server-logs-<sha>`, next to `playwright-report-<sha>`. Nothing is saved when you run against your own server with `E2E_BASE_URL`, because the tests do not own that container.

## Test tags

Every test carries tags, so a subset can be selected with `--grep` instead of by file path. Tags are set with Playwright's `tag` option, usually on the `test.describe` (its tests inherit them):

```ts
test.describe('Document - create new document', { tag: ['@document', '@smoke', '@regression'] }, () => {
```

| Tag                                                  | Meaning                                                      |
| ---------------------------------------------------- | ------------------------------------------------------------ |
| `@document`, `@spreadsheet`, `@presentation`, `@pdf` | Area: the editor the test exercises. Exactly one per test.   |
| `@mobile`                                            | Extra tag on the mobile-editor tests, next to their area tag |
| `@smoke`                                             | The fast sanity set, see below                               |
| `@regression`                                        | The full suite, see below                                    |
| `@ignore`                                            | Temporarily excluded from every run, see below               |

### Rules

- Every test has exactly one area tag and `@regression`. Tests that also qualify for the smoke set add `@smoke`.
- Tag every new test when you write it. Keep to the area names above: do not introduce a second spelling such as `@sheet` or `@pdf-form`.

**`@smoke`** is a fast check that the basics work on a new build or image, run before the full suite.

- Qualifies: a test that opens an editor and confirms it loads, or covers the one core action of an area, such as create-new.
- Keep it small: at most one or two smoke tests per area. A smoke test must be quick and stable, with no known flakiness and no long multi-step flow.
- Run it on every build, image or deploy.

**`@regression`** is the full suite, which checks that existing behaviour has not broken. It includes every test, smoke tests too. Run it before a release, after larger changes, and in CI.

**`@ignore`** marks a test that is temporarily excluded from every run, local and CI, for example because it is flaky or obsolete and waiting for a fix or removal.

- Add it next to the test's other tags, which stay in place so the test is easy to restore, and put a comment above it with the reason and a Jira key, for example `// flaky on slow CI, see EUOFFICE-xxx`.
- It is a temporary state: fix the test or delete it.
- `playwright.config.ts` skips these tests by default (`grepInvert`). Set `E2E_INCLUDE_IGNORED=1` to run them, for example to check whether a flaky test is fixed.

### Selecting tests by tag

A combined pattern is matched against the tags in the order they are written on the test, which is area first, then `@smoke`, then `@regression`.

```sh
npm test -- --grep @smoke                  # quick sanity check
npm test -- --grep "@document.*@smoke"     # smoke tests for one area (area tag first)
npm test -- --grep @spreadsheet            # one area
npm test -- --grep-invert @mobile          # everything except the mobile tests
npm test -- --list --grep @smoke           # list what would run, without running it
```

```sh
E2E_INCLUDE_IGNORED=1 npm test -- --grep @ignore   # run only the ignored tests
```

## Code quality

Formatting is enforced by Prettier, linting by ESLint and types by `tsc`. Run the checks before every commit:

```sh
npm run check    # report only; modifies nothing
npm run fix      # format, lint with auto-fix, type-check
```

The rules live in [`eslint.config.mjs`](eslint.config.mjs), [`.prettierrc.json`](.prettierrc.json) and [`.editorconfig`](.editorconfig). `tsc` cannot auto-fix, so type errors always need a manual fix.
