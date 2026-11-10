import { test, expect } from '@playwright/test';
import { openNewEditor } from '../helpers';

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
    // Opens <baseURL>/example/, clicks the "Document" link (matched by the file
    // type it creates, not by wording or styling) and waits for the editor to load.
    const { editorPage, frame } = await openNewEditor(page, 'a[href*="fileExt=docx"]', /\.docx/);

    // The editor iframe points at the document editor app.
    await expect(editorPage.locator(EDITOR_IFRAME)).toHaveAttribute('src', /documenteditor/);

    // Every expected menu bar tab (File, Home, Insert, ...) is visible.
    //     Each tab is <a role="tab" data-title="<label>">; only the File tab's
    //     id (#file) is confirmed, so all tabs are matched by data-title.
    for (const name of MENU_BAR_TABS) {
      await expect(frame.locator(`a[role="tab"][data-title="${name}"]`)).toBeVisible();
    }
  });
});
