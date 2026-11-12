// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Opens workbooks in the Document Server example editor and measures each open: a cold open
// (conversion included) and warm opens (Editor.bin from the cache). Prints one JSON line per
// open on stdout and a short summary on stderr. See README.md.

import { chromium } from '@playwright/test';
import type { Browser, Page } from '@playwright/test';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { loadavg } from 'node:os';
import { basename, join } from 'node:path';
import { parseArgs } from 'node:util';

const USAGE = `usage: node perf/open.ts [options] <file.xlsx | @uploaded-name>...

  --url URL       Document Server with the example app enabled
                  (default: $DS_URL or http://localhost)
  --runs N        warm opens after the cold open (default 1)
  --warm-only     skip the cold open; use with @uploaded-name from an earlier run
  --phases        wrap sdkjs functions to report call counts and time per phase.
                  The wrappers add overhead: compare phases only with phases.
  --verify        hash every cell's formula and value per sheet after the open (VERIFY=1)
  --dump DIR      also write each sheet's cells to DIR/<doc>.<open>.<sheet>.tsv (implies --verify)
  --sdk FILE      serve FILE instead of the server's sdkjs/cell/sdk-all.js (PATCH_SDK=FILE)
  --sdk-min FILE  serve FILE instead of sdkjs/cell/sdk-all-min.js (PATCH_SDK_MIN=FILE). That
                  bundle holds cell/api.js, cell/utils/utils.js and the shared API code.
  --profile DIR   write a CPU profile of each open to DIR
  --gap S         seconds to wait between opens, so the server closes the session (default 10)
  --timeout S     seconds to wait for onDocumentReady (default 900)
  --label TEXT    copied into every output line
  --headed        show the browser
`;

/** [object path in the editor frame, method, label, count only]. */
type PhaseSpec = [string, string, string, boolean];

// Timed functions are measured at the outermost call only, so recursion is not counted twice.
// Count-only wrappers are for hot functions, where timing each call would distort the result:
// two performance.now() calls cost more than a call that runs once per cell. setFormulaOpen runs
// for every cell, formula or not; timed, it added 0.9 s to the open of a 1.28 M-cell workbook.
const PHASE_SPECS: PhaseSpec[] = [
  // BinaryFileReader.Read is set per instance in its constructor, so it cannot be wrapped here;
  // OpenDocumentFromBin covers it.
  ['Asc.spreadsheet_api.prototype', 'OpenDocumentFromBin', 'OpenDocumentFromBin', false],
  ['AscCommonExcel.Worksheet.prototype', 'fromXLSB', 'Worksheet.fromXLSB', false],
  ['AscCommonExcel.Cell.prototype', 'fromXLSB', 'Cell.fromXLSB', true],
  ['AscCommonExcel.InitOpenManager.prototype', 'setFormulaOpen', 'setFormulaOpen', true],
  ['AscCommonExcel', 'compareFormula', 'compareFormula', false],
  ['AscCommonExcel.parserFormula.prototype', 'parse', 'parserFormula.parse', false],
  ['AscCommonExcel.parserFormula.prototype', 'calculate', 'parserFormula.calculate', true],
  ['AscCommon.openXml.SaxParserBase.prototype', 'parse', 'SaxParserBase.parse', false],
  ['AscCommonExcel.Workbook.prototype', 'init', 'Workbook.init', false],
  ['AscCommonExcel.DependencyGraph.prototype', 'initOpen', 'DependencyGraph.initOpen', false],
  ['AscCommonExcel.DependencyGraph.prototype', 'addToChangedCell', 'addToChangedCell', true],
  ['AscCommonExcel.DependencyGraph.prototype', 'addToChangedRange', 'addToChangedRange', true],
  ['AscCommonExcel.DependencyGraph.prototype', 'calcTree', 'calcTree', false],
  ['AscCommonExcel.Cell.prototype', 'getListeners', 'Cell.getListeners', true],
  ['AscCommonExcel.Worksheet.prototype', 'initPostOpen', 'Worksheet.initPostOpen', false],
  ['Asc.spreadsheet_api.prototype', '_openDocumentEndCallback', '_openDocumentEndCallback', false],
  ['Asc.spreadsheet_api.prototype', 'asc_ApplyColorScheme', 'asc_ApplyColorScheme', false],
  ['AscCommonExcel', 'generateCellStyles', 'generateCellStyles', false],
  ['Asc.spreadsheet_api.prototype', '_applyFirstLoadChanges', '_applyFirstLoadChanges', false],
  ['AscCommonExcel.WorkbookView.prototype', '_init', 'WorkbookView._init', false],
  ['AscCommonExcel.WorksheetView.prototype', 'draw', 'WorksheetView.draw', false],
  ['Asc.spreadsheet_api.prototype', 'onDocumentContentReady', 'onDocumentContentReady', false],
  ['Asc.spreadsheet_api.prototype', '_onEndOpen', '_onEndOpen', false],
  ['AscCommon.g_font_loader', 'LoadDocumentFonts', 'LoadDocumentFonts', false],
];

interface Marks {
  onAppReady?: number;
  onDocumentReady?: number;
  onError?: number;
  error?: string;
}

interface PhaseState {
  t: Record<string, number>;
  n: Record<string, number>;
  depth: Record<string, number>;
  sheets: [string, number][];
  hooked: string[];
}

interface SheetHash {
  name: string;
  cells: number;
  formulas: number;
  hash: string;
  valueHash: string;
}

interface Verify {
  workbook: string;
  workbookValues: string;
  sheets: SheetHash[];
  dump?: { name: string; tsv: string }[];
}

// The functions below run in the browser. Playwright serializes them, so they must not use
// anything from this module's scope.

/** Top window: wraps DocsAPI.DocEditor to timestamp the editor events. */
function hookDocEditor(): void {
  if (window.top !== window) return;
  type EventHandler = (this: unknown, ...args: unknown[]) => unknown;
  type Config = { events?: Record<string, EventHandler | undefined> };
  type DocEditor = new (id: string, config: Config) => unknown;
  const w = window as unknown as { __perfMarks: Marks; DocsAPI?: unknown };
  const marks: Marks = {};
  w.__perfMarks = marks;
  let wrapped: DocEditor | undefined;
  const api = {};
  Object.defineProperty(api, 'DocEditor', {
    configurable: true,
    get: () => wrapped,
    set(real: DocEditor) {
      const Wrapper = function (id: string, config: Config) {
        const events = (config.events = config.events || {});
        for (const name of ['onAppReady', 'onDocumentReady', 'onError'] as const) {
          const original = events[name];
          events[name] = function (this: unknown, ...args: unknown[]) {
            marks[name] = performance.now();
            if (name === 'onError')
              marks.error = JSON.stringify((args[0] as { data?: unknown })?.data);
            return original?.apply(this, args);
          };
        }
        return new real(id, config);
      };
      Object.assign(Wrapper, real);
      wrapped = Wrapper as unknown as DocEditor;
    },
  });
  w.DocsAPI = api;
}

/** Editor frame: wraps sdkjs functions as soon as they exist. */
function hookPhases(specs: PhaseSpec[]): void {
  if (window.top === window) return;
  type Fn = (this: unknown, ...args: unknown[]) => unknown;
  type Bag = Record<string, unknown>;
  const w = window as unknown as Bag & { __perfPhases: PhaseState };
  const P: PhaseState = { t: {}, n: {}, depth: {}, sheets: [], hooked: [] };
  w.__perfPhases = P;
  const resolve = (path: string): Bag | undefined => {
    let o: unknown = w;
    for (const key of path.split('.')) o = o ? (o as Bag)[key] : undefined;
    return o ? (o as Bag) : undefined;
  };
  const pending = new Set(specs.map((_, i) => i));
  let timer: ReturnType<typeof setInterval> | undefined;
  const tryHook = () => {
    for (const i of pending) {
      const [path, method, label, countOnly] = specs[i];
      const obj = resolve(path);
      const original = obj?.[method];
      if (!obj || typeof original !== 'function') continue;
      const f = original as Fn;
      obj[method] = function (this: unknown, ...args: unknown[]) {
        P.n[label] = (P.n[label] || 0) + 1;
        if (label === 'OpenDocumentFromBin' && timer !== undefined) {
          // Every bundle has loaded once the binary is opened: hook what is left, stop polling.
          // A function that is still missing was renamed in this sdkjs version.
          clearInterval(timer);
          timer = undefined;
          tryHook();
        }
        if (countOnly || P.depth[label]) return f.apply(this, args);
        P.depth[label] = 1;
        const start = performance.now();
        try {
          return f.apply(this, args);
        } finally {
          const ms = performance.now() - start;
          P.depth[label] = 0;
          P.t[label] = (P.t[label] || 0) + ms;
          if (label === 'Worksheet.fromXLSB') {
            const ws = this as { getName?: () => string };
            P.sheets.push([ws.getName ? ws.getName() : '?', Math.round(ms)]);
          }
        }
      };
      P.hooked.push(label);
      pending.delete(i);
    }
    return pending.size === 0;
  };
  const started = Date.now();
  timer = setInterval(() => {
    if ((tryHook() || Date.now() - started > 300_000) && timer !== undefined) {
      clearInterval(timer);
      timer = undefined;
    }
  }, 2);
}

/** Editor frame: an order-independent hash of every non-empty cell, per sheet. */
function hashWorkbook(withDump: boolean): Verify | null {
  interface SdkCell {
    nRow: number;
    nCol: number;
    isFormula(): boolean;
    getFormula(): string;
    getValueWithoutFormat(): string;
  }
  interface SdkSheet {
    getName(): string;
    getRowsCount(): number;
    getColsCount(): number;
    getRange3(
      r1: number,
      c1: number,
      r2: number,
      c2: number,
    ): { _foreachNoEmpty(cb: (cell: SdkCell) => void): void };
  }
  interface SdkWorkbook {
    getWorksheetCount(): number;
    getWorksheet(i: number): SdkSheet;
  }
  const w = window as unknown as { Asc?: { editor?: { wbModel?: SdkWorkbook } } };
  const wb = w.Asc?.editor?.wbModel;
  if (!wb) return null;
  // 64-bit string hash (two 32-bit lanes, cyrb53 mixing).
  const hash = (s: string): [number, number] => {
    let h1 = 0xdeadbeef;
    let h2 = 0x41c6ce57;
    for (let i = 0; i < s.length; i++) {
      const ch = s.charCodeAt(i);
      h1 = Math.imul(h1 ^ ch, 2654435761);
      h2 = Math.imul(h2 ^ ch, 1597334677);
    }
    h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
    h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
    return [h1 >>> 0, h2 >>> 0];
  };
  const hex = (a: number, b: number) =>
    (a >>> 0).toString(16).padStart(8, '0') + (b >>> 0).toString(16).padStart(8, '0');
  const sheets: SheetHash[] = [];
  const dump: { name: string; tsv: string }[] = [];
  for (let i = 0; i < wb.getWorksheetCount(); i++) {
    const ws = wb.getWorksheet(i);
    let cells = 0;
    let formulas = 0;
    // Per-cell hashes are summed, so the result does not depend on the iteration order.
    let a1 = 0;
    let a2 = 0;
    let v1 = 0;
    let v2 = 0;
    const lines: [number, number, string][] = [];
    const lastRow = Math.max(0, ws.getRowsCount() - 1);
    const lastCol = Math.max(0, ws.getColsCount() - 1);
    ws.getRange3(0, 0, lastRow, lastCol)._foreachNoEmpty((cell) => {
      cells++;
      const f = cell.isFormula() ? cell.getFormula() : '';
      if (f) formulas++;
      const v = cell.getValueWithoutFormat();
      const [h1, h2] = hash(`${cell.nRow},${cell.nCol}|${f}|${v}`);
      a1 = (a1 + h1) >>> 0;
      a2 = (a2 + h2) >>> 0;
      const [g1, g2] = hash(`${cell.nRow},${cell.nCol}|${f ? 'F' : ''}|${v}`);
      v1 = (v1 + g1) >>> 0;
      v2 = (v2 + g2) >>> 0;
      if (withDump) {
        lines.push([cell.nRow, cell.nCol, `${JSON.stringify(f)}\t${JSON.stringify(v)}`]);
      }
    });
    sheets.push({ name: ws.getName(), cells, formulas, hash: hex(a1, a2), valueHash: hex(v1, v2) });
    if (withDump) {
      lines.sort((x, y) => x[0] - y[0] || x[1] - y[1]);
      const tsv = lines.map(([r, c, rest]) => `${r + 1}\t${c + 1}\t${rest}\n`).join('');
      dump.push({ name: ws.getName(), tsv });
    }
  }
  const [w1, w2] = hash(sheets.map((s) => `${s.name}:${s.hash}`).join('\n'));
  const [x1, x2] = hash(sheets.map((s) => `${s.name}:${s.valueHash}`).join('\n'));
  return {
    workbook: hex(w1, w2),
    workbookValues: hex(x1, x2),
    sheets,
    ...(withDump ? { dump } : {}),
  };
}

// ---------------------------------------------------------------------------------------------

interface Options {
  url: string;
  runs: number;
  warmOnly: boolean;
  phases: boolean;
  verify: boolean;
  dump?: string;
  sdk?: Buffer;
  sdkMin?: Buffer;
  sdkPath?: string;
  sdkMinPath?: string;
  profile?: string;
  gapMs: number;
  timeoutMs: number;
  label?: string;
  headed: boolean;
}

function options(): { opts: Options; inputs: string[] } {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      url: { type: 'string', default: process.env.DS_URL || 'http://localhost' },
      runs: { type: 'string', default: '1' },
      'warm-only': { type: 'boolean', default: false },
      phases: { type: 'boolean', default: false },
      verify: { type: 'boolean', default: process.env.VERIFY === '1' },
      dump: { type: 'string' },
      sdk: { type: 'string', default: process.env.PATCH_SDK },
      'sdk-min': { type: 'string', default: process.env.PATCH_SDK_MIN },
      profile: { type: 'string' },
      gap: { type: 'string', default: '10' },
      timeout: { type: 'string', default: '900' },
      label: { type: 'string' },
      headed: { type: 'boolean', default: false },
      help: { type: 'boolean', short: 'h', default: false },
    },
  });
  if (values.help || positionals.length === 0) {
    console.error(USAGE);
    process.exit(values.help ? 0 : 2);
  }
  const opts: Options = {
    url: values.url.replace(/\/+$/, ''),
    runs: Number(values.runs),
    warmOnly: values['warm-only'],
    phases: values.phases,
    verify: values.verify || Boolean(values.dump),
    dump: values.dump,
    sdk: values.sdk ? readFileSync(values.sdk) : undefined,
    sdkMin: values['sdk-min'] ? readFileSync(values['sdk-min']) : undefined,
    sdkPath: values.sdk,
    sdkMinPath: values['sdk-min'],
    profile: values.profile,
    gapMs: Number(values.gap) * 1000,
    timeoutMs: Number(values.timeout) * 1000,
    label: values.label,
    headed: values.headed,
  };
  if (!(opts.runs >= 0) || !(opts.gapMs >= 0) || !(opts.timeoutMs > 0)) {
    throw new Error('--runs, --gap and --timeout must be numbers');
  }
  if (opts.warmOnly && positionals.some((p) => !p.startsWith('@'))) {
    throw new Error('--warm-only needs @uploaded-name inputs: a new upload is always a cold open');
  }
  return { opts, inputs: positionals };
}

async function upload(url: string, file: string): Promise<string> {
  const form = new FormData();
  form.append('uploadedFile', new Blob([readFileSync(file)]), basename(file));
  const res = await fetch(`${url}/example/upload`, {
    method: 'POST',
    body: form,
    signal: AbortSignal.timeout(300_000),
  });
  const text = await res.text();
  let body: { filename?: string; error?: string } = {};
  try {
    body = JSON.parse(text) as typeof body;
  } catch {
    // reported below
  }
  if (!res.ok || !body.filename) {
    throw new Error(`upload of ${file} failed: HTTP ${res.status} ${text.slice(0, 200)}`);
  }
  return body.filename;
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const round = (x: number | undefined) => (x === undefined ? undefined : Math.round(x));
const sha256 = (buf: Buffer) => createHash('sha256').update(buf).digest('hex');

async function evaluateInFrames<T>(page: Page, fn: (arg: boolean) => T, arg: boolean) {
  for (const frame of page.frames()) {
    try {
      const value = await frame.evaluate(fn, arg);
      if (value) return value;
    } catch {
      // frame without the editor, or navigated away
    }
  }
  return null;
}

async function openOnce(browser: Browser, opts: Options, doc: string, open: string) {
  const context = await browser.newContext({ viewport: { width: 1600, height: 900 } });
  try {
    const bundles: [RegExp, Buffer | undefined][] = [
      [/\/sdkjs\/cell\/sdk-all\.js(\?.*)?$/, opts.sdk],
      [/\/sdkjs\/cell\/sdk-all-min\.js(\?.*)?$/, opts.sdkMin],
    ];
    for (const [pattern, body] of bundles) {
      if (!body) continue;
      await context.route(pattern, (route) =>
        route.fulfill({ status: 200, contentType: 'application/javascript', body }),
      );
    }
    const page = await context.newPage();
    await page.addInitScript(hookDocEditor);
    if (opts.phases) await page.addInitScript(hookPhases, PHASE_SPECS);

    let bin: { start: number; ms: number; encoding?: string } | undefined;
    page.on('requestfinished', async (request) => {
      if (!/\/Editor\.bin(\?|$)/.test(request.url())) return;
      try {
        const timing = request.timing();
        const response = await request.response();
        bin = {
          start: timing.startTime,
          ms: timing.responseEnd,
          encoding: response?.headers()['content-encoding'],
        };
      } catch {
        // request.response() can reject ("target closed") if the context closes while this
        // handler is still awaiting. An unhandled rejection there would crash the process
        // (Node's default) before stdout flushes; a missed bin timing is not worth that.
      }
    });

    const cdp = opts.profile ? await context.newCDPSession(page) : undefined;
    if (cdp) {
      await cdp.send('Profiler.enable');
      await cdp.send('Profiler.setSamplingInterval', { interval: 1000 });
      await cdp.send('Profiler.start');
    }

    const editorUrl =
      `${opts.url}/example/editor?fileName=${encodeURIComponent(doc)}` +
      '&mode=edit&type=desktop&userid=uid-1&lang=en';
    const load1 = loadavg()[0];
    const t0 = Date.now();
    await page.goto(editorUrl, { waitUntil: 'domcontentloaded' });
    const timeOrigin = await page.evaluate(() => performance.timeOrigin);
    let marks: Marks = {};
    while (Date.now() - t0 < opts.timeoutMs) {
      try {
        marks = await page.evaluate(
          () => (window as unknown as { __perfMarks?: Marks }).__perfMarks ?? {},
        );
      } catch {
        // the page is busy navigating; poll again
      }
      if (marks.onDocumentReady || marks.onError) break;
      await sleep(100);
    }
    const wall = Date.now() - t0;
    if (opts.phases || opts.verify) await sleep(1500); // let post-ready work finish

    let profileFile: string | undefined;
    if (cdp && opts.profile) {
      const { profile } = await cdp.send('Profiler.stop');
      mkdirSync(opts.profile, { recursive: true });
      profileFile = join(opts.profile, `${doc}.${open}.${Date.now()}.cpuprofile`);
      writeFileSync(profileFile, JSON.stringify(profile));
    }

    const phases = opts.phases
      ? await evaluateInFrames(
          page,
          () => (window as unknown as { __perfPhases?: PhaseState }).__perfPhases ?? null,
          false,
        )
      : null;
    // Decoded size only: Chromium reports encodedBodySize == decodedBodySize for this gzip XHR,
    // and Playwright's request.sizes() has no body size for it.
    const binBytes = await evaluateInFrames(
      page,
      () =>
        performance
          .getEntriesByType('resource')
          .map((e) => e as PerformanceResourceTiming)
          .find((e) => /\/Editor\.bin(\?|$)/.test(e.name))?.decodedBodySize ?? null,
      false,
    );
    const verify = opts.verify
      ? await evaluateInFrames(page, hashWorkbook, Boolean(opts.dump))
      : null;
    if (verify?.dump && opts.dump) {
      mkdirSync(opts.dump, { recursive: true });
      for (const sheet of verify.dump) {
        const safe = sheet.name.replace(/[^\w.-]+/g, '_');
        writeFileSync(join(opts.dump, `${doc}.${open}.${safe}.tsv`), sheet.tsv);
      }
      delete verify.dump;
    }

    const binAt = bin ? bin.start - timeOrigin : undefined;
    const result = {
      label: opts.label,
      doc,
      open,
      error: marks.onError
        ? marks.error || 'onError'
        : marks.onDocumentReady
          ? undefined
          : 'timeout',
      wall_ms: wall,
      app_ready_ms: round(marks.onAppReady),
      doc_ready_ms: round(marks.onDocumentReady),
      bin_request_ms: round(binAt),
      bin_download_ms: round(bin?.ms),
      bin_bytes: binBytes ?? undefined,
      bin_encoding: bin?.encoding,
      after_bin_ms:
        bin && binAt !== undefined && marks.onDocumentReady
          ? Math.round(marks.onDocumentReady - binAt - bin.ms)
          : undefined,
      load1: Math.round(load1 * 100) / 100,
      sdk_patched: Boolean(opts.sdk || opts.sdkMin) || undefined,
      // Pin the exact A/B variable: path and content hash of each served sdkjs bundle.
      sdk:
        opts.sdk || opts.sdkMin
          ? {
              all: opts.sdk ? { path: opts.sdkPath, sha256: sha256(opts.sdk) } : undefined,
              min: opts.sdkMin ? { path: opts.sdkMinPath, sha256: sha256(opts.sdkMin) } : undefined,
            }
          : undefined,
      profile: profileFile,
      phases: phases
        ? {
            missing: PHASE_SPECS.map((s) => s[2]).filter((l) => !phases.hooked.includes(l)),
            calls: phases.n,
            ms: Object.fromEntries(Object.entries(phases.t).map(([k, v]) => [k, Math.round(v)])),
            sheets_ms: phases.sheets,
          }
        : undefined,
      verify: verify ?? undefined,
    };
    return result;
  } finally {
    await context.close();
  }
}

const started = Date.now();
/** Progress on stderr, stamped with the seconds since start, so a stall can be located. */
function log(message: string): void {
  console.error(`[+${((Date.now() - started) / 1000).toFixed(1)}s] ${message}`);
}

async function main(): Promise<void> {
  const { opts, inputs } = options();
  const browser = await chromium.launch({
    headless: !opts.headed,
    args: ['--disable-dev-shm-usage'],
  });
  log('browser started');
  let failures = 0;
  try {
    const opens: string[] = [...(opts.warmOnly ? [] : ['cold'])];
    for (let i = 1; i <= opts.runs; i++) opens.push(`warm${i}`);
    for (const input of inputs) {
      const isUpload = !input.startsWith('@');
      const doc = isUpload ? await upload(opts.url, input) : input.slice(1);
      if (isUpload) log(`uploaded ${input} as ${doc}`);
      for (const [i, open] of opens.entries()) {
        if (i > 0) await sleep(opts.gapMs);
        const result = await openOnce(browser, opts, doc, open);
        process.stdout.write(`${JSON.stringify({ file: basename(input), ...result })}\n`);
        if (result.error) failures++;
        const summary = [
          `${doc} ${open}: docReady ${result.doc_ready_ms ?? '-'} ms`,
          `Editor.bin ${result.bin_download_ms ?? '-'} ms`,
          `after Editor.bin ${result.after_bin_ms ?? '-'} ms`,
          result.verify ? `hash ${result.verify.workbook}` : '',
          result.error ? `ERROR ${result.error}` : '',
        ];
        log(summary.filter(Boolean).join(', '));
        if (result.phases?.missing.length) {
          log(`  not hooked: ${result.phases.missing.join(', ')}`);
        }
      }
    }
  } finally {
    await browser.close();
    log('browser closed');
  }
  process.exitCode = failures ? 1 : 0;
}

main().catch((err: unknown) => {
  console.error(err);
  // Not process.exit(1): that discards unflushed stdout, truncating the last result line when
  // ab.ts reads this script over a pipe. Let the event loop drain and set the code instead.
  process.exitCode = 1;
});
