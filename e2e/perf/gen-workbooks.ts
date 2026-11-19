// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

// Writes synthetic xlsx workbooks that reproduce the patterns that make a first open slow.
// Content is deterministic: the same --scale and --mutate always give the same sheet XML.
// See README.md.

import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import { crc32, deflateRawSync } from 'node:zlib';

const USAGE = `usage: node perf/gen-workbooks.ts <outdir> [--scale N] [--only NAME,...] [--mutate]

  --scale N    multiply the row counts (default 1; fractions allowed)
  --only LIST  comma-separated workbook names (default: all)
  --mutate     change one input cell per workbook; the formula results that depend
               on it change with it. Use it to check that --verify sees a change.
`;

// ---------------------------------------------------------------------------------------------
// Small helpers

/** Deterministic PRNG (mulberry32), so every run writes the same numbers. */
function prng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function xmlText(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/** 0-based column index to letters: 0 -> A, 26 -> AA. */
function colName(c: number): string {
  let s = '';
  for (let n = c + 1; n > 0; n = Math.floor((n - 1) / 26)) {
    s = String.fromCharCode(65 + ((n - 1) % 26)) + s;
  }
  return s;
}

/** Cell reference from a 0-based column and a 1-based row. */
function ref(c: number, r: number): string {
  return colName(c) + r;
}

class SharedStrings {
  private index = new Map<string, number>();
  private list: string[] = [];
  count = 0;

  add(s: string): number {
    this.count++;
    let i = this.index.get(s);
    if (i === undefined) {
      i = this.list.length;
      this.list.push(s);
      this.index.set(s, i);
    }
    return i;
  }

  xml(): string {
    const items = this.list.map((s) => `<si><t xml:space="preserve">${xmlText(s)}</t></si>`);
    return (
      XML_DECL +
      `<sst xmlns="${NS_MAIN}" count="${this.count}" uniqueCount="${this.list.length}">` +
      items.join('') +
      '</sst>'
    );
  }
}

/** Builds one worksheet part. Rows must be added in ascending order. */
class Sheet {
  readonly chunks: Buffer[] = [];
  private pending: string[] = [];
  private pendingLength = 0;
  rows = 0;
  cells = 0;
  formulas = 0;
  readonly name: string;
  private readonly sst: SharedStrings;
  private readonly cols: string;

  // No parameter properties: Node runs this file by stripping types, which does not support them.
  constructor(name: string, sst: SharedStrings, cols = '') {
    this.name = name;
    this.sst = sst;
    this.cols = cols;
  }

  private push(s: string): void {
    this.pending.push(s);
    this.pendingLength += s.length;
    if (this.pendingLength > 1 << 20) this.flush();
  }

  private flush(): void {
    if (this.pending.length) this.chunks.push(Buffer.from(this.pending.join(''), 'utf8'));
    this.pending = [];
    this.pendingLength = 0;
  }

  row(r: number, cells: string[]): void {
    this.rows++;
    this.push(`<row r="${r}">${cells.join('')}</row>`);
  }

  // Cell writers. c is the 0-based column, r the 1-based row, s an optional style index.
  num(c: number, r: number, v: number, s = 0): string {
    this.cells++;
    return `<c r="${ref(c, r)}"${s ? ` s="${s}"` : ''}><v>${v}</v></c>`;
  }

  str(c: number, r: number, v: string, s = 0): string {
    this.cells++;
    return `<c r="${ref(c, r)}"${s ? ` s="${s}"` : ''} t="s"><v>${this.sst.add(v)}</v></c>`;
  }

  inlineStr(c: number, r: number, v: string): string {
    this.cells++;
    return `<c r="${ref(c, r)}" t="inlineStr"><is><t>${xmlText(v)}</t></is></c>`;
  }

  bool(c: number, r: number, v: boolean): string {
    this.cells++;
    return `<c r="${ref(c, r)}" t="b"><v>${v ? 1 : 0}</v></c>`;
  }

  error(c: number, r: number, v: string): string {
    this.cells++;
    return `<c r="${ref(c, r)}" t="e"><v>${v}</v></c>`;
  }

  /** A cell with a style and no value. */
  styled(c: number, r: number, s: number): string {
    this.cells++;
    return `<c r="${ref(c, r)}" s="${s}"/>`;
  }

  /** A formula cell with its cached result, written in full (no shared formula). */
  formula(c: number, r: number, f: string, v: number | string): string {
    this.cells++;
    this.formulas++;
    const t = typeof v === 'string' ? ' t="str"' : '';
    return `<c r="${ref(c, r)}"${t}><f>${xmlText(f)}</f><v>${xmlText(String(v))}</v></c>`;
  }

  /** The head of an array formula over `range`, with the cached value of the head cell. */
  arrayFormula(c: number, r: number, range: string, f: string, v: number | string): string {
    this.cells++;
    this.formulas++;
    const t = typeof v === 'string' ? ' t="str"' : '';
    return `<c r="${ref(c, r)}"${t}><f t="array" ref="${range}">${xmlText(f)}</f><v>${xmlText(String(v))}</v></c>`;
  }

  /** A member of an array formula: only the cached value, or nothing for a blank member. */
  arrayMember(c: number, r: number, v: number | string | null): string {
    this.cells++;
    if (v === null) return `<c r="${ref(c, r)}"/>`;
    const t = typeof v === 'string' ? ' t="str"' : '';
    return `<c r="${ref(c, r)}"${t}><v>${xmlText(String(v))}</v></c>`;
  }

  finish(): Buffer[] {
    this.flush();
    const head = `${XML_DECL}<worksheet xmlns="${NS_MAIN}" xmlns:r="${NS_REL}">${this.cols}<sheetData>`;
    return [Buffer.from(head, 'utf8'), ...this.chunks, Buffer.from('</sheetData></worksheet>')];
  }
}

// ---------------------------------------------------------------------------------------------
// Package parts

const XML_DECL = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const NS_MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const NS_REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const NS_PKG_REL = 'http://schemas.openxmlformats.org/package/2006/relationships';
const CT_SHEET = 'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml';

// Style indexes used by the generators.
const S_BOLD = 1;
const S_DATE = 2;
const S_MONEY = 3;
const S_FILL = 4;

const STYLES =
  XML_DECL +
  `<styleSheet xmlns="${NS_MAIN}">` +
  '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>' +
  '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
  '<fills count="3"><fill><patternFill patternType="none"/></fill>' +
  '<fill><patternFill patternType="gray125"/></fill>' +
  '<fill><patternFill patternType="solid"><fgColor rgb="FFFFF2CC"/></patternFill></fill></fills>' +
  '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
  '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
  '<cellXfs count="5">' +
  '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
  '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>' +
  '<xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' +
  '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' +
  '<xf numFmtId="0" fontId="0" fillId="2" borderId="0" xfId="0" applyFill="1"/>' +
  '</cellXfs>' +
  '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>' +
  '<dxfs count="0"/></styleSheet>';

function packageParts(sheets: Sheet[], sst: SharedStrings): { name: string; data: Buffer[] }[] {
  const text = (name: string, s: string) => ({ name, data: [Buffer.from(s, 'utf8')] });
  const n = sheets.length;
  const overrides = sheets
    .map(
      (_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="${CT_SHEET}"/>`,
    )
    .join('');
  const sheetEntries = sheets
    .map((s, i) => `<sheet name="${xmlText(s.name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`)
    .join('');
  const sheetRels = sheets
    .map(
      (_, i) =>
        `<Relationship Id="rId${i + 1}" Type="${NS_REL}/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`,
    )
    .join('');
  return [
    text(
      '[Content_Types].xml',
      XML_DECL +
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
        '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>' +
        overrides +
        '</Types>',
    ),
    text(
      '_rels/.rels',
      XML_DECL +
        `<Relationships xmlns="${NS_PKG_REL}">` +
        `<Relationship Id="rId1" Type="${NS_REL}/officeDocument" Target="xl/workbook.xml"/>` +
        '</Relationships>',
    ),
    text(
      'xl/workbook.xml',
      XML_DECL +
        `<workbook xmlns="${NS_MAIN}" xmlns:r="${NS_REL}">` +
        '<bookViews><workbookView activeTab="0"/></bookViews>' +
        `<sheets>${sheetEntries}</sheets></workbook>`,
    ),
    text(
      'xl/_rels/workbook.xml.rels',
      XML_DECL +
        `<Relationships xmlns="${NS_PKG_REL}">${sheetRels}` +
        `<Relationship Id="rId${n + 1}" Type="${NS_REL}/styles" Target="styles.xml"/>` +
        `<Relationship Id="rId${n + 2}" Type="${NS_REL}/sharedStrings" Target="sharedStrings.xml"/>` +
        '</Relationships>',
    ),
    text('xl/styles.xml', STYLES),
    text('xl/sharedStrings.xml', sst.xml()),
    ...sheets.map((s, i) => ({ name: `xl/worksheets/sheet${i + 1}.xml`, data: s.finish() })),
  ];
}

/** Minimal zip writer (deflate, no zip64). Fixed timestamps keep the output reproducible. */
function zip(parts: { name: string; data: Buffer[] }[]): Buffer {
  const DOS_DATE_1980_01_01 = 0x21;
  const locals: Buffer[] = [];
  const central: Buffer[] = [];
  let offset = 0;
  for (const part of parts) {
    const raw = Buffer.concat(part.data);
    const packed = deflateRawSync(raw, { level: 6 });
    const crc = crc32(raw);
    const name = Buffer.from(part.name, 'utf8');
    if (raw.length > 0xfffffffe || offset > 0xfffffffe) {
      throw new Error(`${part.name} is too large for a zip without zip64; use a smaller --scale`);
    }
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4); // version needed
    local.writeUInt16LE(0, 6); // flags
    local.writeUInt16LE(8, 8); // deflate
    local.writeUInt16LE(0, 10); // time
    local.writeUInt16LE(DOS_DATE_1980_01_01, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(packed.length, 18);
    local.writeUInt32LE(raw.length, 22);
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(0, 28);
    const dir = Buffer.alloc(46);
    dir.writeUInt32LE(0x02014b50, 0);
    dir.writeUInt16LE(20, 4); // version made by
    dir.writeUInt16LE(20, 6); // version needed
    dir.writeUInt16LE(0, 8);
    dir.writeUInt16LE(8, 10);
    dir.writeUInt16LE(0, 12);
    dir.writeUInt16LE(DOS_DATE_1980_01_01, 14);
    dir.writeUInt32LE(crc, 16);
    dir.writeUInt32LE(packed.length, 20);
    dir.writeUInt32LE(raw.length, 24);
    dir.writeUInt16LE(name.length, 28);
    dir.writeUInt32LE(offset, 42); // the fields in between stay 0
    locals.push(local, name, packed);
    central.push(dir, name);
    offset += local.length + name.length + packed.length;
  }
  const centralSize = central.reduce((sum, b) => sum + b.length, 0);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(parts.length, 8);
  end.writeUInt16LE(parts.length, 10);
  end.writeUInt32LE(centralSize, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, ...central, end]);
}

// ---------------------------------------------------------------------------------------------
// Workbooks

interface Ctx {
  scale: number;
  mutate: boolean;
}

interface Workbook {
  description: string;
  build(ctx: Ctx, sst: SharedStrings): Sheet[];
}

const rows = (ctx: Ctx, n: number) => Math.max(10, Math.round(n * ctx.scale));

const WORKBOOKS: Record<string, Workbook> = {
  'formula-runs': {
    description:
      'Long same-column runs of identical (R1C1) formulas, each written in full without ' +
      'shared formulas, as Google Sheets exports them; one column uses the ' +
      '__xludf.DUMMYFUNCTION wrapper. Exercises Editor.bin size and open-time formula handling.',
    build(ctx, sst) {
      const n = rows(ctx, 25_000);
      const rnd = prng(1);
      const sheet = new Sheet('Runs', sst);
      const head = ['Amount', 'Group', 'Odd', 'Band', 'Scaled', 'Mod 7', 'Sum', 'Label'];
      sheet.row(1, [
        ...head.map((h, c) => sheet.str(c, 1, h, S_BOLD)),
        sheet.str(9, 1, 'Factor', S_BOLD),
        sheet.num(10, 1, 3),
      ]);
      for (let r = 2; r <= n + 1; r++) {
        let a = 1 + Math.floor(rnd() * 1000);
        if (ctx.mutate && r === Math.floor(n / 2)) a += 1;
        const group = `Group ${r % 40}`;
        const odd = a * 2 + 1;
        const label = `${group}-${a}`;
        sheet.row(r, [
          sheet.num(0, r, a),
          sheet.str(1, r, group),
          sheet.formula(2, r, `A${r}*2+1`, odd),
          sheet.formula(3, r, `IF(A${r}>500,"high","low")`, a > 500 ? 'high' : 'low'),
          sheet.formula(4, r, `A${r}*$K$1`, a * 3),
          sheet.formula(5, r, `MOD(A${r},7)`, a % 7),
          sheet.formula(6, r, `C${r}+F${r}`, odd + (a % 7)),
          sheet.formula(
            7,
            r,
            `IFERROR(__xludf.DUMMYFUNCTION("B${r}&""-""&A${r}"),"${label}")`,
            label,
          ),
        ]);
      }
      return [sheet];
    },
  },

  'large-sheetdata': {
    description:
      'Two large value sheets (numbers, dates, shared and inline strings with entities and ' +
      'non-ASCII text, booleans, errors, styled empty cells) behind a tiny active sheet. ' +
      'Exercises the x2t sheetData parser, per-sheet conversion and reading every sheet.',
    build(ctx, sst) {
      const n = rows(ctx, 40_000);
      const words = [
        'Nord',
        'Süd',
        'Ost',
        'West',
        'Zürich',
        'Łódź',
        'Évora',
        '東京',
        'R&D',
        '<tag>',
      ];
      const pool = Array.from({ length: 500 }, (_, i) => `${words[i % words.length]} item ${i}`);
      const sheets: Sheet[] = [];
      const totals: number[] = [];
      for (const [k, name] of ['Data1', 'Data2'].entries()) {
        const rnd = prng(10 + k);
        const sheet = new Sheet(
          name,
          sst,
          '<cols><col min="4" max="4" width="24" customWidth="1"/></cols>',
        );
        const head = ['Id', 'Date', 'Amount', 'Name', 'Flag', 'Note', 'V1', 'V2', 'V3', 'V4'];
        sheet.row(1, [
          ...head.map((h, c) => sheet.str(c, 1, h, S_BOLD)),
          ...['V5', 'V6', 'Tiny', 'Big', 'Empty', 'Status'].map((h, c) =>
            sheet.str(10 + c, 1, h, S_BOLD),
          ),
        ]);
        let total = 0;
        for (let r = 2; r <= n + 1; r++) {
          let amount = Math.round(rnd() * 1_000_000) / 100;
          if (ctx.mutate && k === 0 && r === Math.floor(n / 2)) amount += 1;
          total += amount;
          const cells = [
            sheet.num(0, r, r - 1),
            sheet.num(1, r, 45_000 + (r % 730), S_DATE),
            sheet.num(2, r, amount, S_MONEY),
            sheet.str(3, r, pool[Math.floor(rnd() * pool.length)]),
            sheet.bool(4, r, rnd() < 0.5),
            sheet.inlineStr(5, r, `note ${r} & more`),
          ];
          for (let c = 6; c < 12; c++) cells.push(sheet.num(c, r, Math.round(rnd() * 2e6) - 1e6));
          cells.push(sheet.num(12, r, Math.round(rnd() * 1000) / 1e7));
          cells.push(sheet.num(13, r, Math.round(rnd() * 1e9) * 1000));
          cells.push(sheet.styled(14, r, S_FILL));
          cells.push(
            r % 50 === 0 ? sheet.error(15, r, '#N/A') : sheet.str(15, r, r % 3 ? 'open' : 'done'),
          );
          sheet.row(r, cells);
        }
        totals.push(Math.round(total * 100) / 100);
        sheets.push(sheet);
      }
      const summary = new Sheet('Summary', sst);
      summary.row(1, [summary.str(0, 1, 'Sheet', S_BOLD), summary.str(1, 1, 'Rows', S_BOLD)]);
      sheets.forEach((s, i) =>
        summary.row(i + 2, [summary.str(0, i + 2, s.name), summary.num(1, i + 2, n)]),
      );
      summary.row(5, [
        summary.str(0, 5, 'Total Data1'),
        summary.formula(1, 5, 'SUM(Data1!C:C)', totals[0]),
      ]);
      return [summary, ...sheets];
    },
  },

  'array-blank': {
    description:
      'An array formula whose cached result has a blank member (UNIQUE over a whole column), ' +
      'and many VLOOKUPs that depend on it. Today the blank member makes the open recalculate ' +
      'all of them.',
    build(ctx, sst) {
      const keyCount = 50;
      const keys = Array.from({ length: keyCount }, (_, i) => `K${String(i + 1).padStart(3, '0')}`);
      const valueOf = (i: number) => (i + 1) * 10 + (ctx.mutate && i === 0 ? 1 : 0);

      const data = new Sheet('Data', sst);
      data.row(1, [data.str(0, 1, 'key', S_BOLD)]);
      const dataRows = rows(ctx, 2_000);
      for (let r = 2; r <= dataRows + 1; r++)
        data.row(r, [data.str(0, r, keys[(r - 2) % keyCount])]);

      // UNIQUE(Data!A:A) returns the header, the keys in order of appearance, and one blank for
      // the empty rows. Google Sheets stores that last member without a value.
      const legend = new Sheet('Legend', sst);
      const results: (string | null)[] = ['key', ...keys, null];
      const last = 2 + results.length - 1;
      legend.row(1, [legend.str(0, 1, 'Keys', S_BOLD), legend.str(1, 1, 'Value', S_BOLD)]);
      results.forEach((v, i) => {
        const r = 2 + i;
        const cells =
          i === 0
            ? [legend.arrayFormula(0, r, `A2:A${last}`, '_xlfn.UNIQUE(Data!A:A)', 'key')]
            : [legend.arrayMember(0, r, v)];
        if (i >= 1 && i <= keyCount) cells.push(legend.num(1, r, valueOf(i - 1)));
        legend.row(r, cells);
      });

      const lookup = new Sheet('Lookup', sst);
      lookup.row(
        1,
        ['Key', 'Value', 'Double'].map((h, c) => lookup.str(c, 1, h, S_BOLD)),
      );
      const lookupRows = rows(ctx, 20_000);
      for (let r = 2; r <= lookupRows + 1; r++) {
        const i = (r * 7) % keyCount;
        lookup.row(r, [
          lookup.str(0, r, keys[i]),
          lookup.formula(1, r, `VLOOKUP(A${r},Legend!A:B,2,FALSE)`, valueOf(i)),
          lookup.formula(2, r, `B${r}*2`, valueOf(i) * 2),
        ]);
      }
      return [lookup, legend, data];
    },
  },

  'area-listeners': {
    description:
      'Many distinct area references on one sheet over volatile cells (INDIRECT). Opening ' +
      'recalculates the volatile cells, and the circular-reference check then looks up the ' +
      'area listeners of every formula cell inside every referenced range.',
    build(ctx, sst) {
      const n = rows(ctx, 3_000);
      // The window width alternates, so neighbouring formulas are not identical in R1C1 form.
      // Otherwise sdkjs would turn the column into one shared formula at open, with a single
      // area listener instead of one per row.
      const widthAt = (r: number) => 10 + (r % 2);
      const rnd = prng(3);
      const values: number[] = [];
      for (let r = 2; r <= n + 1; r++) {
        values[r] = 1 + Math.floor(rnd() * 100) + (ctx.mutate && r === Math.floor(n / 2) ? 1 : 0);
      }
      const sheet = new Sheet('Calc', sst);
      sheet.row(
        1,
        ['Value', 'Volatile', 'Window sum'].map((h, c) => sheet.str(c, 1, h, S_BOLD)),
      );
      for (let r = 2; r <= n + 1; r++) {
        const width = widthAt(r);
        let sum = 0;
        for (let k = r; k < r + width && k <= n + 1; k++) sum += values[k];
        sheet.row(r, [
          sheet.num(0, r, values[r]),
          sheet.formula(1, r, 'INDIRECT("A"&ROW())', values[r]),
          sheet.formula(2, r, `SUM(B${r}:B${r + width - 1})`, sum),
        ]);
      }
      return [sheet];
    },
  },
};

// ---------------------------------------------------------------------------------------------

function main(): void {
  const usage = `${USAGE}\nworkbooks: ${Object.keys(WORKBOOKS).join(', ')}`;
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      scale: { type: 'string', default: '1' },
      only: { type: 'string' },
      mutate: { type: 'boolean', default: false },
      help: { type: 'boolean', short: 'h', default: false },
    },
  });
  if (values.help || positionals.length !== 1) {
    console.error(usage);
    process.exit(values.help ? 0 : 2);
  }
  const outDir = positionals[0];
  const ctx: Ctx = { scale: Number(values.scale), mutate: values.mutate };
  if (!(ctx.scale > 0)) throw new Error('--scale must be a positive number');
  const names = values.only ? values.only.split(',') : Object.keys(WORKBOOKS);
  for (const name of names) {
    if (!WORKBOOKS[name]) throw new Error(`unknown workbook ${name}\n${usage}`);
  }
  mkdirSync(outDir, { recursive: true });
  for (const name of names) {
    const sst = new SharedStrings();
    const sheets = WORKBOOKS[name].build(ctx, sst);
    const parts = packageParts(sheets, sst);
    const contentHash = createHash('sha256');
    for (const part of parts) for (const b of part.data) contentHash.update(b);
    const file = join(outDir, `perf-${name}${ctx.mutate ? '-mutated' : ''}.xlsx`);
    const data = zip(parts);
    writeFileSync(file, data);
    const sheetXml = sheets.reduce((sum, s) => sum + s.chunks.reduce((t, b) => t + b.length, 0), 0);
    console.log(
      JSON.stringify({
        file,
        bytes: data.length,
        sheet_xml_bytes: sheetXml,
        sheets: sheets.map((s) => ({
          name: s.name,
          rows: s.rows,
          cells: s.cells,
          formulas: s.formulas,
        })),
        content_sha256: contentHash.digest('hex'),
      }),
    );
  }
}

main();
