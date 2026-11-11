import { test, expect } from '@playwright/test';
import { openNewEditor } from '../helpers';

// Ribbon tabs a new PDF form shows. Plugins, Header & Footer are hidden, and
// Draw depends on the build and on permissions, so none of them are checked.
const MENU_TABS = [
  'File',
  'Home',
  'Insert',
  'Layout',
  'References',
  'Forms',
  'Collaboration',
  'Protection',
  'View',
] as const;

test.describe('PDF form editor - create new', () => {
  test('creates a PDF form in a new window with the full menu bar', async ({ page }) => {
    // Opens <baseURL>/example/, clicks "PDF form" and waits for the editor to load.
    // The example page links it as editor?fileExt=pdf.
    const { editorPage, frame } = await openNewEditor(page, 'a[href*="fileExt=pdf"]', /\.pdf/);

    await test.step('PDF form opens in a new window', async () => {
      expect(editorPage).not.toBe(page);
      expect(page.context().pages()).toContain(editorPage);
      await expect(editorPage).toHaveURL(/\/example\/editor/);
    });

    await test.step('file has the .pdf extension', async () => {
      const fileName = new URL(editorPage.url()).searchParams.get('fileName');
      expect(fileName).toMatch(/\.pdf$/);
    });

    await test.step('all menu bar tabs are displayed', async () => {
      for (const tab of MENU_TABS) {
        await expect
          .soft(
            frame.locator(`section.tabs a[role="tab"][data-title="${tab}"]`),
            `menu tab "${tab}" is visible`,
          )
          .toBeVisible();
      }
    });
  });
});
