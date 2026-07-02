import { test, expect } from '@playwright/test';

// Canvas id differs by engine: doc/presentation/pdf use #id_viewer, spreadsheet #ws-canvas.
// Visio excluded: create-new has no blank vsdx template (fileExt=vsdx 500s). The build-time
// verify-deploy.mjs check still gates the visio mobile bundle.
const MOBILE_EDITOR_TYPES = [
  { label: 'Document',     fileExt: 'docx', canvasSelector: '#id_viewer' },
  { label: 'Spreadsheet',  fileExt: 'xlsx', canvasSelector: '#ws-canvas' },
  { label: 'Presentation', fileExt: 'pptx', canvasSelector: '#id_viewer' },
  { label: 'PDF form',     fileExt: 'pdf',  canvasSelector: '#id_viewer' },
] as const;

// Fatal errors surface as an f7 dialog or, for LoadingScriptError, a notification — check both.
// See apps/*/mobile/src/controller/Error.jsx.
const ERROR_SURFACE_SELECTOR = '.dialog.modal-in, .notification.modal-in';

// Remit: verify the mobile build is present and actually renders a document (the #258 class of
// failure). Infra faults such as an unresponsive docservice channel are out of scope — the app
// can go false-ready over a dead channel; see cm-findings/DocumentServer/pr-262-ws-hang-false-pass.md.
test.describe('Mobile editor smoke', () => {
  test.use({ viewport: { width: 414, height: 896 } });

  for (const editor of MOBILE_EDITOR_TYPES) {
    test(`${editor.label} mobile editor loads`, async ({ page }) => {
      // ?type=mobile forces the mobile bundle (bypasses UA sniffing in nodejs/app.js).
      await page.goto(`/example/editor?fileExt=${editor.fileExt}&type=mobile`);

      const editorIframe = page.locator('iframe[name="frameEditor"]');
      await expect(editorIframe).toBeAttached({ timeout: 15_000 });
      await expect(editorIframe).toHaveAttribute('src', /type=mobile/);

      // The real "document loaded" signal is the loading skeleton clearing, not the canvas:
      // .doc-placeholder (uniform across editors) shows while !isDocReady and is removed when
      // the doc loads — the mobile analog of the desktop suite's #loading-mask. #id_viewer alone
      // mounts with the SDK bundle before any document loads, so it can't tell "loaded" apart
      // from "never loaded". Assert the skeleton appears, then clears, then the shell is clean.
      const frame = page.frameLocator('iframe[name="frameEditor"]');
      const placeholder = frame.locator('.doc-placeholder');
      await expect(placeholder.first()).toBeVisible({ timeout: 15_000 });
      await expect(placeholder).toHaveCount(0, { timeout: 30_000 });
      await expect(frame.locator(ERROR_SURFACE_SELECTOR)).toHaveCount(0, { timeout: 5_000 });
      await expect(frame.locator(editor.canvasSelector)).toBeVisible({ timeout: 5_000 });
    });
  }
});
