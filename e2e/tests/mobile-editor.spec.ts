import { test, expect } from '@playwright/test';

// Each mobile editor names its main rendering canvas differently: the
// document/presentation/pdf engines share `#id_viewer`, but the spreadsheet
// engine uses its own `#ws-canvas`.
//
// Visio (vsdx) is excluded: the example app's create-new flow has no blank
// vsdx template (`fileExt=vsdx` 500s — "new.vsdx was not included into
// executable at compilation stage"), so there's no way to exercise it via
// this create-new-document pattern. web-apps' build still gates a visio
// mobile bundle (verify-deploy.mjs), but that's a build-time artifact check,
// not something this runtime smoke test can reach without a pre-existing
// sample file.
const MOBILE_EDITOR_TYPES = [
  { label: 'Document',     fileExt: 'docx', canvasSelector: '#id_viewer' },
  { label: 'Spreadsheet',  fileExt: 'xlsx', canvasSelector: '#ws-canvas' },
  { label: 'Presentation', fileExt: 'pptx', canvasSelector: '#id_viewer' },
  { label: 'PDF form',     fileExt: 'pdf',  canvasSelector: '#id_viewer' },
] as const;

// framework7 error surfaces use two distinct components depending on error
// type: most fatal errors (Unknown, version mismatch, conversion failures)
// go through `f7.dialog.create` (`.dialog.modal-in`), but LoadingScriptError
// specifically uses `f7.notification.create` (`.notification.modal-in`) —
// see apps/documenteditor/mobile/src/controller/Error.jsx. Check both.
//
// This selector also matches the loading preloader (`f7.dialog.preloader()`
// renders as `.dialog.dialog-preloader`, `.modal-in` while open) — that's
// intentional, not a false positive: it means a permanent loading skeleton
// (#258's actual failure mode) is caught too, since the preloader never
// closes. It does mean this assertion is also the "document actually
// finished loading" gate, not just an error check — give it the same
// timeout as the canvas-visible check below, not the default.
const ERROR_SURFACE_SELECTOR = '.dialog.modal-in, .notification.modal-in';

test.describe('Mobile editor smoke', () => {
  test.use({ viewport: { width: 414, height: 896 } });

  for (const editor of MOBILE_EDITOR_TYPES) {
    test(`${editor.label} mobile editor mounts past the loading skeleton`, async ({ page }) => {
      // ?type=mobile forces the mobile bundle deterministically. The example
      // app only falls back to User-Agent sniffing when ?type= is absent
      // (nodejs/app.js) — the emulated viewport above is for CSS realism,
      // unrelated to which bundle gets selected.
      await page.goto(`/example/editor?fileExt=${editor.fileExt}&type=mobile`);

      const editorIframe = page.locator('iframe[name="frameEditor"]');
      await expect(editorIframe).toBeAttached({ timeout: 15_000 });
      await expect(editorIframe).toHaveAttribute('src', /type=mobile/);

      // #258's actual failure mode: mobile artifacts deploy correctly, but the
      // app never gets past the loading skeleton (or hits a fatal error, e.g.
      // version mismatch) once it talks to a live docservice — a build-time
      // check like verify-deploy.mjs can't catch that.
      //
      // The rendering canvas alone isn't a sufficient signal: it's part of the
      // static UI scaffold and stays present (and "visible") even when the
      // document itself fails to load — verified by reproducing a fatal load
      // error, which left the canvas visible but surfaced a framework7 error
      // surface on top of it. So this asserts both: the canvas mounted AND no
      // error dialog/notification is showing.
      const frame = page.frameLocator('iframe[name="frameEditor"]');
      await expect(frame.locator(editor.canvasSelector)).toBeVisible({ timeout: 30_000 });
      await expect(frame.locator(ERROR_SURFACE_SELECTOR)).toHaveCount(0, { timeout: 30_000 });
    });
  }
});
