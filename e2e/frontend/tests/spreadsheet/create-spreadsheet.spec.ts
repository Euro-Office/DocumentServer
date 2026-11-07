import { test, expect } from '@playwright/test';

const EDITOR_IFRAME = 'iframe[name="frameEditor"]';

// Menu bar tabs a new spreadsheet shows, with their element ids. "Plugins",
// "Pivot Table" and "Table Design" are left out because they are hidden by
// default.
const MENU_BAR_TABS = [
  { id: 'file', label: 'File' },
  { id: 'home', label: 'Home' },
  { id: 'ins', label: 'Insert' },
  { id: 'draw', label: 'Draw' },
  { id: 'layout', label: 'Layout' },
  { id: 'formula', label: 'Formula' },
  { id: 'data', label: 'Data' },
  { id: 'review', label: 'Collaboration' },
  { id: 'protect', label: 'Protection' },
  { id: 'view', label: 'View' },
] as const;

test.describe('Spreadsheet - create new spreadsheet', () => {
  test('opens a new spreadsheet with the full menu bar visible', async ({ page }) => {
    // 1. Open the example page; the root URL comes from E2E_BASE_URL (or the
    //    Docker default), so this relative path works against any server.
    await page.goto('/example/');

    // 2. Confirm the example page itself loaded before interacting with it.
    await expect(page).toHaveTitle(/ONLYOFFICE|euro-office/i);

    // 3. Register the new-window handler BEFORE clicking so the event is not
    //    missed. The link has target="_blank", so it always opens a new window.
    const newPagePromise = page.context().waitForEvent('page');

    // 4. Click the "Spreadsheet" link under "Create new". It has no id, so it
    //    is found by its title.
    await page.locator('a[title="Create new spreadsheet"]').click();

    // 5. The editor opens in the new window.
    const editorPage = await newPagePromise;

    // 6. Wait for the editor route; a new window starts as about:blank and
    //    navigates afterwards.
    await editorPage.waitForURL(/\/example\/editor/);
    await editorPage.waitForLoadState('domcontentloaded');

    // 7. The new spreadsheet is an .xlsx file.
    await expect(editorPage).toHaveURL(/\.xlsx/);

    // 8. The editor iframe is mounted and points at the spreadsheet editor app.
    const editorIframe = editorPage.locator(EDITOR_IFRAME);
    await expect(editorIframe).toBeAttached({ timeout: 15_000 });
    await expect(editorIframe).toHaveAttribute('src', /spreadsheeteditor/);

    // 9. Wait until the editor has finished loading (the loading mask is
    //    removed), so the menu bar is rendered before we assert on it.
    const frame = editorPage.frameLocator(EDITOR_IFRAME);
    await expect(frame.locator('#loading-mask')).toBeHidden({ timeout: 30_000 });

    // 10. Every expected menu bar tab is visible and shows its label. Each tab
    //     is <a role="tab" id="..."> inside the ribbon tab list.
    for (const tab of MENU_BAR_TABS) {
      const menuTab = frame.locator(`a[role="tab"]#${tab.id}`);
      await expect(menuTab).toBeVisible();
      await expect(menuTab).toHaveText(tab.label);
    }
  });
});
