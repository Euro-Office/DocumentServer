// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Runs two or more variants ("arms") of a benchmark interleaved, so that changes in machine
// load hit every arm alike. Prints the median of every metric per arm and checks that the
// result hashes (open.ts --verify, x2tbench.py's Editor.bin SHA-256) agree. See README.md.

import { spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { parseArgs } from 'node:util';

const USAGE = `usage: node perf/ab.ts [--reps N] [--compare formulas|values] [--out FILE]
                      --arm 'NAME=COMMAND' --arm 'NAME=COMMAND'...

  --arm NAME=COMMAND  a shell command that prints JSON lines, such as perf/open.ts or
                      perf/x2tbench.py. Every arm must print the same number of lines in the
                      same order: line k of each arm is compared with line k of the others.
  --reps N            rounds (default 3). Odd rounds run the arms in the given order, even
                      rounds in reverse order.
  --compare MODE      formulas (default): formula text and value of every cell must match.
                      values: only values must match, formulas may be spelled differently.
  --out FILE          also write every result line, tagged with arm and round, to FILE

Exit status: 0 if every run succeeded, printed the same number of lines and the hashes
agree, 1 otherwise.
`;

type Row = Record<string, unknown>;
type Compare = 'formulas' | 'values';

interface Arm {
  name: string;
  cmd: string;
  rounds: Row[][];
}

/** Numeric leaves worth comparing: top-level numbers, phase times and call counts. */
function metrics(row: Row): Map<string, number> {
  const out = new Map<string, number>();
  for (const [key, value] of Object.entries(row)) {
    if (typeof value === 'number' && key !== 'rep' && key !== 'rc') out.set(key, value);
  }
  const phases = row.phases as { ms?: Record<string, number>; calls?: Record<string, number> };
  for (const [key, value] of Object.entries(phases?.ms ?? {})) out.set(`ms ${key}`, value);
  for (const [key, value] of Object.entries(phases?.calls ?? {})) out.set(`calls ${key}`, value);
  return out;
}

interface VerifyRow {
  workbook?: string;
  workbookValues?: string;
  sheets?: { name: string; hash: string; valueHash: string }[];
}

/** What must be identical between arms: the workbook hash or the Editor.bin SHA-256. */
function identity(row: Row, compare: Compare): string | undefined {
  const verify = row.verify as VerifyRow | undefined;
  const workbook = compare === 'values' ? verify?.workbookValues : verify?.workbook;
  return workbook ?? (row.bin_sha256 as string | undefined);
}

function sheetHashes(row: Row, compare: Compare): Map<string, string> {
  const verify = row.verify as VerifyRow | undefined;
  return new Map(
    (verify?.sheets ?? []).map((s) => [s.name, compare === 'values' ? s.valueHash : s.hash]),
  );
}

function median(values: number[]): number {
  const s = [...values].sort((a, b) => a - b);
  const mid = s.length >> 1;
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

function fmt(x: number): string {
  return Math.abs(x) >= 100 || Number.isInteger(x) ? String(Math.round(x)) : x.toFixed(2);
}

function runArm(arm: Arm, round: number, reps: number): boolean {
  const started = Date.now();
  const res = spawnSync('sh', ['-c', arm.cmd], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'inherit'],
    maxBuffer: 1 << 30,
  });
  const rows = (res.stdout ?? '')
    .split('\n')
    .filter((line) => line.startsWith('{'))
    .map((line) => JSON.parse(line) as Row);
  arm.rounds.push(rows);
  // No result lines with exit 0 is a failure too, for example a crash piped through `| tee`.
  const failure =
    res.status !== 0
      ? `exit ${res.status ?? res.signal}`
      : rows.length === 0
        ? 'no result lines'
        : rows.some((r) => r.error)
          ? 'a run reported an error'
          : '';
  const ok = !failure;
  const secs = ((Date.now() - started) / 1000).toFixed(0);
  // The measured part, to spot time lost outside it (upload, browser start, a stalled exit).
  const measured = rows.reduce(
    (sum, r) => sum + (Number(r.wall_ms) / 1000 || 0) + (Number(r.wall_s) || 0),
    0,
  );
  console.error(
    `[round ${round}/${reps}] ${arm.name}: ${rows.length} results in ${secs} s ` +
      `(measured ${measured.toFixed(0)} s)` +
      (ok ? '' : ` FAILED (${failure})`),
  );
  return ok;
}

function report(arms: Arm[], compare: Compare): boolean {
  let agree = true;
  const lines = Math.min(...arms.flatMap((a) => a.rounds.map((r) => r.length)));
  if (arms.some((a) => a.rounds.some((r) => r.length !== lines))) {
    // Line k is matched with line k, so the comparison is not reliable: fail the run.
    agree = false;
    console.log('error: the runs printed different numbers of lines; comparing the first', lines);
  }
  const width = Math.max(28, ...arms.map((a) => a.name.length + 12));
  for (let i = 0; i < lines; i++) {
    const first = arms[0].rounds[0][i];
    const title = arms.map((a) => {
      const r = a.rounds[0][i];
      return `${a.name}: ${r.file ?? r.doc ?? '?'}${r.open ? ` ${r.open}` : ''}`;
    });
    console.log(`\n#${i + 1}  ${title.join('  |  ')}`);

    const perArm = arms.map((a) => a.rounds.map((r) => metrics(r[i])));
    const names = [...metrics(first).keys()].filter((k) =>
      perArm.every((rs) => rs.every((m) => m.has(k))),
    );
    console.log(
      'metric'.padEnd(36) + arms.map((a) => `${a.name} (median)`.padStart(width)).join(''),
    );
    for (const name of names) {
      const medians = perArm.map((rs) => median(rs.map((m) => m.get(name) as number)));
      // Call counts are only interesting when they differ between arms.
      if (name.startsWith('calls ') && medians.every((m) => m === medians[0])) continue;
      const cells = medians.map((m, k) => {
        const ratio = k === 0 ? '' : medians[0] ? `${(m / medians[0]).toFixed(2)}x` : '-';
        return `${fmt(m)}${ratio.padStart(k === 0 ? 0 : 7)}`.padStart(width);
      });
      console.log(name.padEnd(36) + cells.join(''));
    }

    const ids = arms.map((a) => new Set(a.rounds.map((r) => identity(r[i], compare))));
    const all = new Set(ids.flatMap((s) => [...s]));
    if (all.size === 1 && all.has(undefined)) {
      // nothing to compare: no --verify and no Editor.bin hash
    } else if (all.size === 1) {
      console.log(`result hash (${compare}): identical in all arms and rounds (${[...all][0]})`);
    } else {
      agree = false;
      console.log(`result hash (${compare}): DIFFERENT`);
      arms.forEach((a, k) => {
        // An arm that disagrees with itself has non-deterministic output, not a regression.
        const own = ids[k].size > 1 ? '  (differs between its own rounds: not deterministic)' : '';
        console.log(`  ${a.name}: ${[...ids[k]].join(', ')}${own}`);
      });
      const base = sheetHashes(first, compare);
      for (const a of arms.slice(1)) {
        const other = sheetHashes(a.rounds[0][i], compare);
        const differ = [...base.keys()].filter((s) => base.get(s) !== other.get(s));
        if (differ.length) console.log(`  sheets that differ in ${a.name}: ${differ.join(', ')}`);
      }
    }
  }
  return agree;
}

function main(): void {
  const { values } = parseArgs({
    options: {
      arm: { type: 'string', multiple: true, default: [] },
      reps: { type: 'string', default: '3' },
      compare: { type: 'string', default: 'formulas' },
      out: { type: 'string' },
      help: { type: 'boolean', short: 'h', default: false },
    },
  });
  const reps = Number(values.reps);
  const compare = values.compare as Compare;
  const badCompare = compare !== 'formulas' && compare !== 'values';
  if (values.help || values.arm.length < 2 || !(reps >= 1) || badCompare) {
    console.error(USAGE);
    process.exit(values.help ? 0 : 2);
  }
  const arms: Arm[] = values.arm.map((spec) => {
    const eq = spec.indexOf('=');
    if (eq <= 0) throw new Error(`--arm needs NAME=COMMAND, got: ${spec}`);
    return { name: spec.slice(0, eq), cmd: spec.slice(eq + 1), rounds: [] };
  });
  let ok = true;
  for (let round = 1; round <= reps; round++) {
    const order = round % 2 ? arms : [...arms].reverse();
    for (const arm of order) ok = runArm(arm, round, reps) && ok;
  }
  if (values.out) {
    const rows = arms.flatMap((a) =>
      a.rounds.flatMap((rows, k) =>
        rows.map((r) => JSON.stringify({ arm: a.name, round: k + 1, ...r })),
      ),
    );
    writeFileSync(values.out, rows.join('\n') + '\n');
  }
  ok = report(arms, compare) && ok;
  process.exitCode = ok ? 0 : 1;
}

main();
