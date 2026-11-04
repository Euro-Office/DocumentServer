<!--
SPDX-FileCopyrightText: 2026 Euro-Office contributors
SPDX-License-Identifier: AGPL-3.0-only
-->

# Open-performance harness

Measures how long a spreadsheet takes to open in the Document Server, and checks that a change
keeps every cell's formula and value. Use it for before/after comparisons of changes to the open
path in x2t (core), sdkjs and the server.

| File               | What it does                                                                                                                                                    |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `gen-workbooks.ts` | Writes synthetic workbooks with the patterns that make a first open slow.                                                                                       |
| `open.ts`          | Opens workbooks in the example editor: cold open (conversion included) and warm opens (cache hit). `--phases` times sdkjs phases, `--verify` hashes every cell. |
| `x2tbench.py`      | Converts xlsx to Editor.bin with x2t, inside a Document Server container or with a local build: wall time, CPU time, peak RSS, Editor.bin size and SHA-256.     |
| `ab.ts`            | Runs variants of any of these interleaved, prints medians per variant, and checks that the result hashes agree.                                                 |

`gen-workbooks.ts`, `open.ts` and `x2tbench.py` print one JSON object per line on stdout and
progress on stderr. `ab.ts` prints a report; `--out` also writes the JSON lines to a file.

## Requirements

- Node.js 22.18 or later. The `.ts` files run directly (Node strips the types). Install the
  dependencies once in `e2e/`: `npm ci` and `npx playwright install chromium`.
- A Document Server with the example app, for example a throwaway container:

  ```sh
  docker run -d --name perf-ds -p 127.0.0.1:8090:80 -e EXAMPLE_ENABLED=true \
      ghcr.io/euro-office/documentserver:<tag>
  ```

  Wait until `http://localhost:8090/healthcheck` returns `true` and `/example/` loads. Keep the
  default JWT settings: the example app and the server then share the secret. Every run uploads
  the files again, so the example storage grows: use a container you can throw away.

- Python 3.9 or later and Docker for `x2tbench.py --container`.

## Quick start

From `e2e/`:

```sh
WB=$(mktemp -d)
node perf/gen-workbooks.ts "$WB"
node perf/open.ts --url http://localhost:8090 --verify "$WB"/perf-*.xlsx
python3 perf/x2tbench.py --container perf-ds --gzip "$WB"/perf-*.xlsx
```

`open.ts` also reads `DS_URL`, `VERIFY=1`, `PATCH_SDK=<file>` and `PATCH_SDK_MIN=<file>` from
the environment.

## Workbooks

`gen-workbooks.ts <outdir> [--scale N] [--only NAME,...] [--mutate]` writes `perf-<name>.xlsx`.
The content is deterministic: the same options give the same sheet XML (see `content_sha256` in
its output). `--scale` multiplies the row counts.

| Name              | Pattern                                                                                                                                                              | Exercises                                                                                                | Size at scale 1                   |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `formula-runs`    | Long same-column runs of identical (R1C1) formulas, each written in full without shared formulas, as Google Sheets exports them; one `__xludf.DUMMYFUNCTION` column  | Editor.bin size, open-time formula parsing and `compareFormula`                                          | 150k formulas, 12 MB sheet XML    |
| `large-sheetdata` | Two large value sheets (numbers, dates, shared and inline strings with entities and non-ASCII text, booleans, errors, styled empty cells) behind a tiny active sheet | The x2t sheetData parser, per-sheet conversion, reading sheets the user does not see first               | 1.3 M cells, 45 MB sheet XML      |
| `array-blank`     | An array formula (`UNIQUE` over a whole column) whose cached result has a blank member, and VLOOKUPs that depend on it                                               | A blank array member that triggers a recalculation at open                                               | 40k dependent formulas            |
| `area-listeners`  | Many distinct area references on one sheet over volatile `INDIRECT` cells                                                                                            | The circular-reference check, which looks up area listeners for every formula cell in a referenced range | 3,000 area listeners on one sheet |

`--mutate` changes one input cell per workbook (the cached results that depend on it change with
it) and writes `perf-<name>-mutated.xlsx`. Use it to check that `--verify` notices a change.

## Correctness check (`--verify`)

After the open, `open.ts --verify` hashes every non-empty cell in the editor: row, column, formula
text and value. Per sheet it reports `hash` (formula and value) and `valueHash` (value, and whether
the cell has a formula, but not the formula text). Per-cell hashes are summed, so the result does
not depend on the order in which sdkjs stores cells. `verify.workbook` combines the sheet hashes,
`verify.workbookValues` the value hashes.

- Two opens of the same build give the same hashes; a change to one cell changes the hash of its
  sheet.
- A change that only respells formulas (for example, x2t writing shared formulas, which sdkjs shows
  in canonical spelling) changes `hash` but not `valueHash`. Compare such arms with
  `ab.ts --compare values`.
- Functions that return something new on every open (`RAND`, `NOW`, `TODAY` across midnight) change
  the hash. The generated workbooks do not use them.
- `--dump DIR` also writes every sheet's cells as TSV, sorted by row and column, to diff two opens.

## A/B comparisons

Absolute times on a shared or busy machine vary by 3× or more between runs. Only compare variants
measured in the same session on the same machine, interleaved. `ab.ts` does that: it runs each
variant ("arm") once per round, alternates the order every round, and prints the median of every
metric per arm with the ratio to the first arm. Each JSON line also records the load average.

```sh
# sdkjs: the server's bundle against a locally built cell/sdk-all.js. Both arms load the
# bundle with --sdk, so it reaches the page the same way and only its code differs.
curl -fsSo main-sdk-all.js http://localhost:8090/sdkjs/cell/sdk-all.js
node perf/ab.ts --reps 3 \
  --arm "main=node perf/open.ts --url http://localhost:8090 --verify --sdk main-sdk-all.js perf-area-listeners.xlsx" \
  --arm "branch=node perf/open.ts --url http://localhost:8090 --verify --sdk sdk-all.js perf-area-listeners.xlsx"

# Two server images, one container each
node perf/ab.ts --arm "old=node perf/open.ts --url http://localhost:8090 --verify f.xlsx" \
                --arm "new=node perf/open.ts --url http://localhost:8091 --verify f.xlsx"

# x2t: two builds; Editor.bin must stay byte-identical
node perf/ab.ts --arm "old=python3 perf/x2tbench.py --x2t old/x2t f.xlsx" \
                --arm "new=python3 perf/x2tbench.py --x2t new/x2t f.xlsx"
```

Line k of every arm is compared with line k of the others, so give every arm the same inputs in
the same order (or matching variants of them). The exit status is 1 if a run failed or printed
no result lines, the runs printed different numbers of lines, or a hash differs. The report lists
the sheets that differ. Each round's progress line shows the arm's
total time next to the measured time; a large gap means time was lost outside the measurement
(upload, browser start), and `open.ts`'s timestamped stderr shows where.

Notes:

- `--phases` wraps sdkjs functions. Call counts are exact; times include the wrapper overhead,
  mostly two `performance.now()` calls per timed call. Functions that run once per cell are only
  counted. The rest still costs something on formula-heavy files: about +9 % after Editor.bin with
  150 k formulas (`compareFormula` is timed per formula), within noise on 1.28 M plain cells.
  Compare phase times only with other `--phases` runs, and open times only with runs without it.
  A function that a newer sdkjs renamed is listed under `phases.missing`.
- `--sdk FILE` replaces `sdkjs/cell/sdk-all.js` and `--sdk-min FILE` replaces
  `sdkjs/cell/sdk-all-min.js`. `sdk-all-min.js` holds `cell/api.js`, `cell/utils/utils.js` and
  the shared API code (the `sdk.min` list in sdkjs `configs/cell.json`): a change there needs
  `--sdk-min`, and `--sdk` alone leaves it out. The rest of the page comes from the server, so
  build the bundles from a commit close to the server's version. The browser gets these files
  from the harness, not over HTTP from nginx (no network, no gzip), so give every arm of an
  sdkjs comparison the same options, the baseline arm with the server's own files.
- A cold open includes the conversion. For browser-only changes, compare the warm opens.
- "Warm" means the server reuses its converted Editor.bin. The browser side is a first visit for
  every open: a new context has no HTTP cache and no compiled-code cache, and the editor's service
  worker installs again before it serves sdkjs and Editor.bin. That static part takes about 2 s
  before Editor.bin is requested (`bin_request_ms`). A returning user who reopened the same file in
  one context was ready in 2.5 s where a new context took 4.2 s. For sdkjs changes, compare
  `after_bin_ms`, which leaves out most of the static loading.
- `bin_bytes` is the decoded Editor.bin size. Chromium does not report the compressed size of this
  request; `x2tbench.py --gzip` reports the size at nginx's gzip level.
- The same x2t can write a different `bin_sha256` on every run for some workbooks
  (`perf-area-listeners` here). x2t reserves 640 bytes for the table of contents at the start of
  Editor.bin, writes only the entries it needs, and leaves the rest as uninitialized memory (core
  `BinaryWriterS.cpp`, `WriteMainTableStart`). Run `--reps 2` before an x2t comparison; `ab.ts`
  marks an arm whose own runs disagree.
- `x2tbench.py` does not pass the server's input limits (`FileConverter.converter.inputLimits`,
  by default 500 MB of uncompressed XML per xlsx), so it also converts files that the server
  refuses to open. Check a large file with `open.ts` too.
- For x2t on the host, copy the converter out of the image:
  `docker cp perf-ds:/var/www/euro-office/documentserver/server/FileConverter/bin x2t-bin`, then
  `--x2t x2t-bin/x2t`.

## Test data

Do not commit customer workbooks, or name them in code, defaults or this README. Use the generator,
or files from the public test corpus, so that anyone can reproduce a number.
