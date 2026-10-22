import { test, expect } from '@playwright/test';
import { EDITOR_TYPES, openRibbonTab } from './helpers';

const EXAMPLE_PATH = '/example/';

test.describe('Example page - Create new', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(EXAMPLE_PATH);
    await expect(page).toHaveTitle(/ONLYOFFICE|euro-office/i);
  });

  for (const editor of EDITOR_TYPES) {
    test(`Create new ${editor.label}`, async ({ page }) => {
      // Register the new-tab handler BEFORE clicking so the event is not missed
      const newPagePromise = page.context().waitForEvent('page');

      await page.click(editor.selector);

      const editorPage = await newPagePromise;

      // The page opens as about:blank then navigates to the editor URL.
      // Wait for the URL to match the editor route before asserting content.
      await editorPage.waitForURL(/\/example\/editor/);
      await editorPage.waitForLoadState('domcontentloaded');

      // 1. URL contains the correct file extension in the fileName param
      await expect(editorPage).toHaveURL(editor.fileExt);

      // 2. DocsAPI replaces the #iframeEditor mount point with an <iframe name="frameEditor">.
      //    Assert that iframe is present and its src points to the document editor app.
      const editorIframe = editorPage.locator('iframe[name="frameEditor"]');
      await expect(editorIframe).toBeAttached({ timeout: 15_000 });
      // The PDF editor is hosted by the shared `common` app (fileType=pdf),
      // not a dedicated editor app like the other types.
      const srcPattern =
        editor.label === 'PDF'
          ? /apps\/common\/index\.html\?.*fileType=pdf/
          : /documenteditor|spreadsheeteditor|presentationeditor/;
      await expect(editorIframe).toHaveAttribute('src', srcPattern);

      // 3. Wait for the file to finish loading inside the editor iframe.
      //    The loading mask (#loading-mask) is removed from the DOM once ready.
      const frame = editorPage.frameLocator('iframe[name="frameEditor"]');
      await expect(frame.locator('#loading-mask')).toBeHidden({ timeout: 30_000 });

      // 4. Verify the Insert tab is clickable and becomes active.
      await openRibbonTab(frame, 'ins');

      // 5. Verify the View tab is clickable and becomes active.
      await openRibbonTab(frame, 'view');

      // 6. Verify typing into the editor works.
      //    Click the Home tab first to return to the editing surface, then click
      //    the canvas area and type. A successful keystroke enables the undo button.
      await openRibbonTab(frame, 'home');
      await frame.locator('#editor_sdk').click();
      await editorPage.keyboard.type('Hello');
      await expect(frame.locator('#slot-btn-undo button').first()).not.toHaveClass(/disabled/, {
        timeout: 5_000,
      });
    });
  }
});
