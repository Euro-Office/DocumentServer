import { test, expect } from '@playwright/test';

const EDITOR_IFRAME = 'iframe[name="frameEditor"]';

// Menu bar tabs the Document editor shows to a user who can edit.
const MENU_BAR_TABS = [
  'File',
  'Home',
  'Insert',
  'Draw',
  'Layout',
  'References',
  'Collaboration',
  'Protection',
  'View',
] as const;

test.describe('Document - create new document', () => {
  test('opens a new document with the full menu bar visible', async ({ page }) => {
    // 1. Open the example page; the root URL comes from E2E_BASE_URL (or the
    //    Docker default), so this relative path works against any server.
    await page.goto('/example/');

    // 2. Confirm the example page itself loaded before interacting with it.
    await expect(page).toHaveTitle(/ONLYOFFICE|euro-office/i);

    // 3. Register the new-window handler BEFORE clicking so the event is not
    //    missed. The link has target="_blank", so it always opens a new window.
    const newPagePromise = page.context().waitForEvent('page');

    // 4. Click the "Document" link under "Create new". It has no id, so it is
    //    found by its title.
    await page.locator('a[title="Create new document"]').click();

    // 5. The editor opens in the new window.
    const editorPage = await newPagePromise;

    // 6. Wait for the editor route; a new window starts as about:blank and
    //    navigates afterwards.
    await editorPage.waitForURL(/\/example\/editor/);
    await editorPage.waitForLoadState('domcontentloaded');

    // 7. The new document is a .docx file.
    await expect(editorPage).toHaveURL(/\.docx/);

    // 8. The editor iframe is mounted and points at the document editor app.
    const editorIframe = editorPage.locator(EDITOR_IFRAME);
    await expect(editorIframe).toBeAttached({ timeout: 15_000 });
    await expect(editorIframe).toHaveAttribute('src', /documenteditor/);

    // 9. Wait until the editor has finished loading (the loading mask is
    //    removed), so the menu bar is rendered before we assert on it.
    const frame = editorPage.frameLocator(EDITOR_IFRAME);
    await expect(frame.locator('#loading-mask')).toBeHidden({ timeout: 30_000 });

    // 10. Every expected menu bar tab (File, Home, Insert, ...) is visible.
    //     Each tab is <a role="tab" data-title="<label>">; only the File tab's
    //     id (#file) is confirmed, so all tabs are matched by data-title.
    for (const name of MENU_BAR_TABS) {
      await expect(frame.locator(`a[role="tab"][data-title="${name}"]`)).toBeVisible();
    }
  });
});
