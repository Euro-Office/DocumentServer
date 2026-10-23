import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi } from './helpers';

const slideCount = (p: import('@playwright/test').Page) =>
  editorApi(p, (api) => api.getCountPages());

test.describe('Presentation editor - building a deck', () => {
  test('create a deck of 3 slides', async ({ page }) => {
    const { editorPage, frame } = await openNewEditor(page, 'a.try-editor.slide', /\.pptx/);

    // A fresh presentation starts with a single slide.
    expect(await slideCount(editorPage)).toBe(1);

    // The Ctrl+M shortcut only fires when the slide-thumbnail panel is focused
    // and toolbar button ids are renamed in this build, so drive slide creation
    // through the automation API (AddSlide) instead.
    await editorApi(editorPage, (api) => { api.AddSlide(); api.AddSlide(); });

    await expect.poll(() => slideCount(editorPage)).toBe(3);

    // The document was mutated: undo is enabled.
    await expect(frame.locator('#slot-btn-undo button').first()).not.toHaveClass(/disabled/);
  });
});
