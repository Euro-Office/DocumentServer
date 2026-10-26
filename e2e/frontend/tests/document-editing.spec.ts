import { test, expect } from '@playwright/test';
import { openNewEditor, editorApi, expectUndoEnabled, editorFor } from './helpers';
import { editorViewOffset, setRulersVisible } from './document.helpers';

test.describe('Document editor - typing and formatting', () => {
  test('type text and apply bold/italic', async ({ page }) => {
    const editor = editorFor('Document');
    const { editorPage, frame } = await openNewEditor(page, editor.selector, editor.fileExt);

    await editorPage.keyboard.type('Hello world');
    await editorPage.keyboard.press('Control+A');
    await editorPage.keyboard.press('Control+b');
    await editorPage.keyboard.press('Control+i');

    // The edit registered: the undo button is no longer disabled.
    await expectUndoEnabled(frame);

    // The typed text round-trips through the automation API.
    const text = await editorApi(editorPage, (api) => api.asc_GetSelectedText());
    expect(text).toContain('Hello world');

    // The Ctrl+b/Ctrl+i keystrokes actually applied bold/italic — not just that
    // "some edit" registered. Without this, the test stays green even with
    // formatting entirely removed.
    const isBold = await editorApi(editorPage, (api) =>
      api.get_TextProps().get_TextPr().get_Bold(),
    );
    const isItalic = await editorApi(editorPage, (api) =>
      api.get_TextProps().get_TextPr().get_Italic(),
    );
    expect(isBold).toBe(true);
    expect(isItalic).toBe(true);
  });
});

test.describe('Document editor - view settings', () => {
  // The View tab's "Rulers" checkbox drives api.asc_SetViewRulers(), the same
  // state zen mode uses to reclaim the ruler space. Unchecking it must remove
  // the rulers from the layout.
  test('disable rulers via the View tab checkbox', async ({ page }) => {
    const editor = editorFor('Document');
    const { editorPage, frame } = await openNewEditor(page, editor.selector, editor.fileExt);

    const before = await editorViewOffset(editorPage);
    expect(before).not.toBeNull();
    expect(before!.left).toBeGreaterThan(0); // rulers are shown by default

    await setRulersVisible(frame, false);

    // The checkbox reflects the change and the viewer reclaims the space.
    await expect(frame.locator('#slot-chk-rulers input[type="checkbox"]')).not.toBeChecked();
    await expect.poll(() => editorViewOffset(editorPage)).toEqual({ left: 0, top: 0 });
  });
});
