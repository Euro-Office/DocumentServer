import { test, expect } from '@playwright/test';
import { editorApi } from '../helpers';

const EDITOR_IFRAME = 'iframe[name="frameEditor"]';

// Menu bar tabs a new presentation shows, with their element ids. "Slide
// Master" and "Plugins" are left out because they are hidden by default.
const MENU_BAR_TABS = [
  { id: 'file', label: 'File' },
  { id: 'home', label: 'Home' },
  { id: 'ins', label: 'Insert' },
  { id: 'draw', label: 'Draw' },
  { id: 'design', label: 'Design' },
  { id: 'transit', label: 'Transitions' },
  { id: 'animate', label: 'Animation' },
  { id: 'review', label: 'Collaboration' },
  { id: 'view', label: 'View' },
] as const;

test.describe('Presentation - create new presentation', () => {
  test('opens a new presentation with the full menu bar visible', async ({ page }) => {
    // 1. Open the example page; the root URL comes from E2E_BASE_URL (or the
    //    Docker default), so this relative path works against any server.
    await page.goto('/example/');

    // 2. Confirm the example page itself loaded before interacting with it.
    await expect(page).toHaveTitle(/ONLYOFFICE|euro-office/i);

    // 3. Register the new-window handler BEFORE clicking so the event is not
    //    missed. The link has target="_blank", so it always opens a new window.
    const newPagePromise = page.context().waitForEvent('page');

    // 4. Click the "Presentation" link under "Create new". It has no id, so it
    //    is found by its title.
    await page.locator('a[title="Create new presentation"]').click();

    // 5. The editor opens in the new window.
    const editorPage = await newPagePromise;

    // 6. Wait for the editor route; a new window starts as about:blank and
    //    navigates afterwards.
    await editorPage.waitForURL(/\/example\/editor/);
    await editorPage.waitForLoadState('domcontentloaded');

    // 7. The new presentation is a .pptx file.
    await expect(editorPage).toHaveURL(/\.pptx/);

    // 8. The editor iframe is mounted and points at the presentation editor app.
    const editorIframe = editorPage.locator(EDITOR_IFRAME);
    await expect(editorIframe).toBeAttached({ timeout: 15_000 });
    await expect(editorIframe).toHaveAttribute('src', /presentationeditor/);

    // 9. Wait until the editor has finished loading (the loading mask is
    //    removed), so the menu bar is rendered before we assert on it.
    const frame = editorPage.frameLocator(EDITOR_IFRAME);
    await expect(frame.locator('#loading-mask')).toBeHidden({ timeout: 30_000 });

    // 10. A new presentation starts with a single slide.
    await expect.poll(() => editorApi(editorPage, (api) => api.getCountPages())).toBe(1);

    // 11. Every expected menu bar tab is visible and shows its label. Each tab
    //     is <a role="tab" id="..."> inside the ribbon tab list.
    for (const tab of MENU_BAR_TABS) {
      const menuTab = frame.locator(`a[role="tab"]#${tab.id}`);
      await expect(menuTab).toBeVisible();
      await expect(menuTab).toHaveText(tab.label);
    }
  });
});
