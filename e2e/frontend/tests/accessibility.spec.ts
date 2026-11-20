import { test, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { mkdirSync, writeFileSync } from 'fs';
import { openNewEditor } from './helpers';

const WCAG_TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'];

async function scan(page: Page, name: string) {
  const { violations } = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
  const summary = violations.map((v) => ({
    id: v.id,
    impact: v.impact,
    help: v.help,
    nodes: v.nodes.length,
    targets: v.nodes.slice(0, 5).map((n) => n.target.join(' >> ')),
  }));
  mkdirSync('a11y-report', { recursive: true });
  writeFileSync(`a11y-report/${name}.json`, JSON.stringify(summary, null, 2));
}

test('example page', async ({ page }) => {
  await page.goto('/example/');
  await scan(page, 'example');
});

for (const [editor, ext] of [
  ['word', /\.docx/],
  ['cell', /\.xlsx/],
  ['slide', /\.pptx/],
] as const) {
  test(`${editor} editor`, async ({ page }) => {
    const { editorPage, frame } = await openNewEditor(page, `a.try-editor.${editor}`, ext);
    await scan(editorPage, `${editor}-toolbar`);
    await frame.locator('#fm-btn-info, .btn-file, [data-tab="file"]').first().click();
    await editorPage.waitForTimeout(1000);
    await scan(editorPage, `${editor}-filemenu`);
  });
}
