import { test, expect } from '@playwright/test';
import { editorApi, openNewEditor } from '../helpers';

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
    // Opens <baseURL>/example/, clicks the "Presentation" link (matched by the file
    // type it creates, not by wording or styling) and waits for the editor to load.
    const { editorPage, frame } = await openNewEditor(page, 'a[href*="fileExt=pptx"]', /\.pptx/);

    // The editor iframe points at the presentation editor app.
    await expect(editorPage.locator(EDITOR_IFRAME)).toHaveAttribute('src', /presentationeditor/);

    // A new presentation starts with a single slide.
    await expect.poll(() => editorApi(editorPage, (api) => api.getCountPages())).toBe(1);

    // Every expected menu bar tab is visible and shows its label. Each tab
    // is <a role="tab" id="..."> inside the ribbon tab list.
    for (const tab of MENU_BAR_TABS) {
      const menuTab = frame.locator(`a[role="tab"]#${tab.id}`);
      await expect(menuTab).toBeVisible();
      await expect(menuTab).toHaveText(tab.label);
    }
  });
});
