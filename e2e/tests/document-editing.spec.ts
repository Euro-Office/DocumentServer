import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi } from './helpers';

test.describe('Document editor - typing and formatting', () => {
  test('type text and apply bold/italic', async ({ page }) => {
    const { editorPage, frame } = await openNewEditor(page, 'a.try-editor.word', /\.docx/);

    await editorPage.keyboard.type('Hello world');
    await editorPage.keyboard.press('Control+A');
    await editorPage.keyboard.press('Control+b');
    await editorPage.keyboard.press('Control+i');

    // The edit registered: the undo button is no longer disabled.
    await expect(frame.locator('#slot-btn-undo button').first()).not.toHaveClass(/disabled/);

    // The typed text round-trips through the automation API.
    const text = await editorApi(editorPage, (api) => api.asc_GetSelectedText());
    expect(text).toContain('Hello world');
  });
});
