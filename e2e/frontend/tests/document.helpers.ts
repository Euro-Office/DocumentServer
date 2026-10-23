// Helpers specific to the document editor (rulers and other document-only
// layout features). Generic editor helpers live in helpers.ts.
import { FrameLocator, Page } from '@playwright/test';

import { editorFrameEvaluateFn, openRibbonTab } from './helpers';

/**
 * The document view is inset from the editor surface while the rulers take
 * layout space; with the rulers hidden the offsets are zero. Returns null
 * until the editor surface has rendered.
 */
export async function editorViewOffset(
  editorPage: Page,
): Promise<{ left: number; top: number } | null> {
  return editorFrameEvaluateFn<{ left: number; top: number } | null>(editorPage, () => {
    const view = document.querySelector('#id_main_view');
    const sdk = document.querySelector('#editor_sdk');
    if (!view || !sdk) return null;
    const v = (view as HTMLElement).getBoundingClientRect();
    const s = (sdk as HTMLElement).getBoundingClientRect();
    return { left: Math.round(v.left - s.left), top: Math.round(v.top - s.top) };
  });
}

/**
 * Set the "Rulers" checkbox in the document editor's View tab. It drives the
 * same api.asc_SetViewRulers state zen mode uses to reclaim the ruler space.
 */
export async function setRulersVisible(frame: FrameLocator, visible: boolean): Promise<void> {
  await openRibbonTab(frame, 'view');

  const checkbox = frame.locator('#slot-chk-rulers input[type="checkbox"]');
  if ((await checkbox.isChecked()) !== visible) {
    await frame.locator('#slot-chk-rulers label.checkbox__shape').click();
  }
}
