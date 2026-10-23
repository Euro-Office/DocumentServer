import { test, expect, FrameLocator, Page } from '@playwright/test';
import {
  openNewEditor,
  openRibbonTab,
  expectUndoDisabled,
  expectUndoEnabled,
  editorFrameEvaluateFn,
  EDITOR_TYPES,
  editorFor,
} from './helpers';
import { editorViewOffset } from './document.helpers';

// Zen mode (web-apps feature/zen-mode): the View tab button hides all chrome
// (toolbar, statusbar, left/right menus, title header) via the body-level
// `zen-mode` class and the `.zen-mode-hideable` CSS contract, and shows an
// overlay with an exit button. Esc exits as well.

/** While zen mode is on, the controller toggles this class on the editor iframe's body. */
const ZEN_BODY_CLASS = 'zen-mode';

/** Selector of the exit button in the zen mode overlay. */
const ZEN_EXIT_BUTTON = '#zen-mode-exit-btn';

/**
 * Zen mode is active: the editor body carries the `zen-mode` class and the
 * exit overlay with its button is shown.
 */
async function expectZenModeActive(frame: FrameLocator) {
  await expect(frame.locator('body')).toContainClass(ZEN_BODY_CLASS);
  await expect(frame.locator('.zen-mode-overlay')).toBeVisible();
  await expect(frame.locator(ZEN_EXIT_BUTTON)).toBeVisible();
}

/**
 * Zen mode has been exited: the editor body no longer carries the class and
 * the exit overlay with its button is hidden.
 */
async function expectZenModeExited(frame: FrameLocator) {
  await expect(frame.locator('body')).not.toContainClass(ZEN_BODY_CLASS);
  await expect(frame.locator('.zen-mode-overlay')).toBeHidden();
  await expect(frame.locator(ZEN_EXIT_BUTTON)).toBeHidden();
}

/** Click the zen mode overlay's exit button. */
async function clickZenModeExitButton(frame: FrameLocator) {
  await frame.locator(ZEN_EXIT_BUTTON).click();
}

/** Open the View tab and click the Zen Mode button. */
async function enterZenMode(frame: FrameLocator) {
  await openRibbonTab(frame, 'view');

  await frame.locator('#slot-btn-zenmode button').click();

  await expectZenModeActive(frame);
}

test.describe('Zen mode', () => {
  for (const editor of EDITOR_TYPES) {
    test(`hide chrome and exit via Esc (${editor.label})`, async ({ page }) => {
      const { editorPage, frame } = await openNewEditor(page, editor.selector, editor.fileExt);

      await enterZenMode(frame);

      // Every element marked hideable is gone — the toolbar, statusbar, left
      // and right menus, and the title header all carry the class. Checking
      // the class contract (not individual ids) keeps this stable across
      // editor layouts.
      const hideables = frame.locator('.zen-mode-hideable');
      const count = await hideables.count();
      expect(count).toBeGreaterThan(0);
      for (let i = 0; i < count; i++) {
        await expect(hideables.nth(i)).toBeHidden();
      }

      // Esc leaves Zen mode and restores the chrome (the overlay visibility
      // is asserted by expectZenModeActive/Exited).
      await editorPage.keyboard.press('Escape');
      await expectZenModeExited(frame);
      await expect(frame.locator('#toolbar')).toBeVisible();
      await expect(frame.locator('#statusbar')).toBeVisible();
    });
  }
});

// ---------------------------------------------------------------------------
// Review regressions (web-apps PR #324 review): focus handling, Esc in
// non-modal windows, the File-menu exit path, and localization.
// ---------------------------------------------------------------------------

/** Evaluate a void function inside the editor iframe. */
async function editorFrameEvaluate(page: Page, fn: () => void): Promise<void> {
  await editorFrameEvaluateFn(page, fn);
}

test.describe('Zen mode keyboard flows', () => {
  // Typing only registers an undoable edit in Document and Spreadsheet; a
  // fresh Presentation slide has no focused text box, so every keyboard-
  // input test skips it.
  for (const editor of EDITOR_TYPES.filter((e) => e.label !== 'Presentation')) {
    // Clicking the View tab button must hand focus back to the document, so
    // typing right after entering Zen mode reaches the document.
    test(`typing reaches the document after entering zen mode (${editor.label})`, async ({
      page,
    }) => {
      const { editorPage, frame } = await openNewEditor(page, editor.selector, editor.fileExt);

      await expectUndoDisabled(frame);
      await enterZenMode(frame);

      await editorPage.keyboard.type('focus');
      if (editor.label === 'Spreadsheet') await editorPage.keyboard.press('Enter');
      await expectUndoEnabled(frame);
    });

    // The overlay exit button hides itself when leaving Zen mode; the focus
    // it still holds must not die with it.
    test(`typing reaches the document after leaving zen mode via the overlay button (${editor.label})`, async ({
      page,
    }) => {
      const { editorPage, frame } = await openNewEditor(page, editor.selector, editor.fileExt);

      await expectUndoDisabled(frame);
      await enterZenMode(frame);

      await clickZenModeExitButton(frame);
      await expectZenModeExited(frame);

      await editorPage.keyboard.type('focus');
      if (editor.label === 'Spreadsheet') await editorPage.keyboard.press('Enter');
      await expectUndoEnabled(frame);
    });

    // The overlay covers the viewport with pointer-events: none, so the
    // document surface stays reachable — click it, type while in Zen mode,
    // then leave via the overlay's button and keep editing.
    test(`exit via the overlay button and keep editing (${editor.label})`, async ({ page }) => {
      const { editorPage, frame } = await openNewEditor(page, editor.selector, editor.fileExt);

      await enterZenMode(frame);

      await frame.locator('#editor_sdk').click();
      await editorPage.keyboard.type('zen');
      if (editor.label === 'Spreadsheet') await editorPage.keyboard.press('Enter');
      await expectUndoEnabled(frame);

      await clickZenModeExitButton(frame);
      await expectZenModeExited(frame);
      await expect(frame.locator('#toolbar')).toBeVisible();
      await expect(frame.locator('#statusbar')).toBeVisible();
    });

    // The Ctrl+F search bar is a non-modal window (no .modals-mask counter):
    // Esc must close it without also leaving Zen mode.
    test(`Esc closes the Ctrl+F search bar without leaving zen mode (${editor.label})`, async ({
      page,
    }) => {
      const { editorPage, frame } = await openNewEditor(page, editor.selector, editor.fileExt);

      await enterZenMode(frame);

      await editorPage.keyboard.press('Control+f');
      const searchBar = frame.locator('.asc-window.search-bar');
      await expect(searchBar).toBeVisible();
      // Opening the search bar must not leave Zen mode either.
      await expectZenModeActive(frame);

      await editorPage.keyboard.press('Escape');
      await expect(searchBar).toBeHidden();
      // Zen mode survives closing the window; plain Esc afterwards still exits.
      await expectZenModeActive(frame);
      await editorPage.keyboard.press('Escape');
      await expectZenModeExited(frame);
    });
  }

  // Requesting the File menu from Zen mode must leave Zen mode so the menu
  // stays visible and keyboard input keeps working. The File menu and its
  // shortcut belong to the shared application shell, so this must hold for
  // every editor type.
  for (const editor of EDITOR_TYPES) {
    test(`requesting the File menu exits zen mode (${editor.label})`, async ({ page }) => {
      const { editorPage, frame } = await openNewEditor(page, editor.selector, editor.fileExt);

      await enterZenMode(frame);

      // The File menu shortcut is ctrl+alt+f on macOS and alt+f elsewhere (the
      // app decides from the user agent, not navigator.platform).
      const isMac = await editorFrameEvaluateFn(editorPage, () =>
        /macintosh|mac os x/i.test(navigator.userAgent),
      );
      const fileMenuShortcut = isMac ? 'Control+Alt+f' : 'Alt+f';
      await editorPage.keyboard.press(fileMenuShortcut);

      await expect(frame.locator('#file-menu-panel')).toBeVisible();
      await expectZenModeExited(frame);

      await editorPage.keyboard.press('Escape');
      await expect(frame.locator('#file-menu-panel')).toBeHidden();
    });
  }

  // An open modal window wins over the Esc handler: Esc closes the modal and
  // stays in Zen mode until a plain Esc with nothing else open. The window
  // machinery (Common.UI.Window, .modals-mask counter) is the same in every
  // editor, so this runs for all of them.
  for (const editor of EDITOR_TYPES) {
    test(`Esc closes an open modal window and stays in zen mode (${editor.label})`, async ({
      page,
    }) => {
      const { editorPage, frame } = await openNewEditor(page, editor.selector, editor.fileExt);

      await enterZenMode(frame);

      // Open a modal window through the application's own window component,
      // the same machinery every modal dialog uses (.modals-mask counter).
      await editorFrameEvaluate(editorPage, () => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const w = new (window as any).Common.UI.Window({
          id: 'zen-e2e-modal',
          modal: true,
          header: true,
          title: 'zen-e2e-modal',
          width: 320,
          height: 120,
          toolclose: 'hide',
          items: [],
        });
        w.show();
      });
      const modal = frame.locator('#zen-e2e-modal');
      await expect(modal).toBeVisible();
      await expectZenModeActive(frame);

      await editorPage.keyboard.press('Escape');
      await expect(modal).toBeHidden();
      await expectZenModeActive(frame);

      await editorPage.keyboard.press('Escape');
      await expectZenModeExited(frame);
    });
  }

  // Rulers hidden by the CSS alone still keep their space: the viewer
  // (sdkjs) positions the main view with the ruler offsets. Zen mode must
  // reclaim the space through the api and restore the setting on exit.
  // Rulers are a Document layout feature — the spreadsheet has no vertical
  // ruler, so the layout-offset preconditions only hold for the document
  // editor.
  test('zen mode reclaims the ruler space and restores it on exit (Document)', async ({ page }) => {
    const editor = editorFor('Document');
    const { editorPage, frame } = await openNewEditor(page, editor.selector, editor.fileExt);

    const before = await editorViewOffset(editorPage);
    expect(before).not.toBeNull();
    expect(before!.left).toBeGreaterThan(0); // rulers take space by default

    await enterZenMode(frame);
    expect(await editorViewOffset(editorPage)).toEqual({ left: 0, top: 0 });

    await editorPage.keyboard.press('Escape');
    await expectZenModeExited(frame);
    expect(await editorViewOffset(editorPage)).toEqual(before);
  });
});
