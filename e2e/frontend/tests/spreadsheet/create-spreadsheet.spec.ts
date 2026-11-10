import { test, expect } from '@playwright/test';
import { openNewEditor } from '../helpers';

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
    // Opens <baseURL>/example/, clicks the "Spreadsheet" link (matched by the file
    // type it creates, not by wording or styling) and waits for the editor to load.
    const { editorPage, frame } = await openNewEditor(page, 'a[href*="fileExt=xlsx"]', /\.xlsx/);

    // The editor iframe points at the spreadsheet editor app.
    await expect(editorPage.locator(EDITOR_IFRAME)).toHaveAttribute('src', /spreadsheeteditor/);

    // Every expected menu bar tab is visible and shows its label. Each tab
    // is <a role="tab" id="..."> inside the ribbon tab list.
    for (const tab of MENU_BAR_TABS) {
      const menuTab = frame.locator(`a[role="tab"]#${tab.id}`);
      await expect(menuTab).toBeVisible();
      await expect(menuTab).toHaveText(tab.label);
    }
  });
});
