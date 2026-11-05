// SPDX-FileCopyrightText: 2026 Euro-Office contributors
// SPDX-License-Identifier: AGPL-3.0-only

import { test, expect, Page } from '@playwright/test';
import { readFileSync } from 'fs';
import path from 'path';
import { editorApi } from './helpers';
import {
  installLocalSessionRelay,
  LocalSessionRelay,
  RelayEditorType,
  RelayIdentity,
} from './local-session-relay';

// Editing in a client-only ("local") session. With transport "self" the editor
// is its own single-user DocService; with transport "host" the co-editing
// messages go to the host page, which relays them between editors the way
// CryptPad does. See docs/client-only-editor.md.

const HOST_PATH = '/e2e-local-session-editing.html';
const FIXTURE = path.join(__dirname, '..', 'fixtures', 'local-session.docx');
const FIXTURE_TEXT = 'Opened in a local session';
const TYPED_TEXT = 'Typed in a local session';
const EDITOR_IFRAME = 'iframe[name="frameEditor"]';
const SERVER_SESSION = /\/doc\/[^/]+\/c\//;

const SINGLE_HOST_PAGE = `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <script src="/web-apps/apps/api/documents/api.js"></script>
  </head>
  <body style="margin: 0">
    <div id="placeholder" style="width: 100vw; height: 100vh"></div>
  </body>
</html>`;

// api.js replaces each placeholder with the editor iframe, so the wrappers
// are what tells the two editors apart.
const PAIR_HOST_PAGE = `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <script src="/web-apps/apps/api/documents/api.js"></script>
  </head>
  <body style="margin: 0; display: flex">
    <div id="editor-alice" style="width: 50vw; height: 100vh"><div id="placeholder-alice"></div></div>
    <div id="editor-bob" style="width: 50vw; height: 100vh"><div id="placeholder-bob"></div></div>
  </body>
</html>`;

type Capability = 'localSession' | 'localSessionEditing' | 'localSessionHostTransport';

type DocsApiWindow = {
  DocsAPI: {
    DocEditor: (new (
      id: string,
      config: unknown,
    ) => {
      sendSessionMessage(message: unknown): void;
    }) & { capabilities?: Partial<Record<Capability, boolean>> };
  };
};

type SavedFile = { fileType: string; blob: Blob };

type SingleWindow = DocsApiWindow & { e2eSaves: SavedFile[] };

type PairWindow = DocsApiWindow & { localSessionRelay: LocalSessionRelay };

async function openHostPage(page: Page, html: string) {
  await page.route(`**${HOST_PATH}`, (route) =>
    route.fulfill({ contentType: 'text/html', body: html }),
  );
  await page.goto(HOST_PATH);
  await page.waitForFunction(() => 'DocsAPI' in window);
}

async function missingCapabilities(page: Page, wanted: Capability[]): Promise<Capability[]> {
  const capabilities = await page.evaluate(
    () => (window as unknown as DocsApiWindow).DocsAPI.DocEditor.capabilities ?? {},
  );
  return wanted.filter((name) => capabilities[name] !== true);
}

function watchServerSession(page: Page): string[] {
  const urls: string[] = [];
  page.on('request', (req) => {
    if (SERVER_SESSION.test(req.url())) urls.push(req.url());
  });
  return urls;
}

// Reads the whole document text without leaving a selection behind.
function documentText(page: Page, iframe = EDITOR_IFRAME): Promise<string> {
  return editorApi(
    page,
    (api) => {
      const doc = api.WordControl.m_oLogicDocument;
      doc.SelectAll();
      const text = api.asc_GetSelectedText();
      doc.RemoveSelection();
      return text;
    },
    iframe,
  );
}

async function openSingle(
  page: Page,
  options: { data: number[]; type: 'desktop' | 'mobile'; mode: 'edit' | 'view' },
) {
  return page.evaluate(({ data, type, mode }) => {
    return new Promise<{ ready: boolean; error?: unknown }>((resolve) => {
      const w = window as unknown as SingleWindow;
      w.e2eSaves = [];
      new w.DocsAPI.DocEditor('placeholder', {
        type,
        documentType: 'word',
        width: '100%',
        height: '100%',
        document: {
          title: 'local-session.docx',
          fileType: 'docx',
          permissions: { edit: mode === 'edit' },
          source: { data: new Uint8Array(data) },
        },
        editorConfig: {
          mode,
          session: { type: 'local', transport: 'self' },
          user: { id: 'alice', name: 'Alice' },
          // The mobile editors open read-only (forceView) and in the reflowed
          // mobile view by default; edit in the standard view instead.
          customization: { mobile: { forceView: false, standardView: true } },
        },
        events: {
          onDocumentReady: () => resolve({ ready: true }),
          onError: (e: { data: unknown }) => resolve({ ready: false, error: e.data }),
          onLocalSessionSave: (e: { data: SavedFile }) => w.e2eSaves.push(e.data),
        },
      });
    });
  }, options);
}

// Types TYPED_TEXT at the end of the document.
async function typeWithKeyboard(page: Page) {
  await page.frameLocator(EDITOR_IFRAME).locator('#editor_sdk').click();
  await page.keyboard.press('Control+End');
  await page.keyboard.type(` ${TYPED_TEXT}`);
}

async function saveWithKeyboard(page: Page) {
  await page.frameLocator(EDITOR_IFRAME).locator('#editor_sdk').click();
  await page.keyboard.press('Control+S');
}

// The mobile editor has no keyboard shortcuts; these drive the sdkjs entry
// points its on-screen keyboard and save action use. editorApi functions
// cannot close over TYPED_TEXT, hence the literal.
async function typeWithApi(page: Page) {
  await editorApi(page, (api) => {
    api.WordControl.m_oLogicDocument.MoveCursorToEndPos();
    api.asc_enterText(' Typed in a local session');
  });
}

async function saveWithApi(page: Page) {
  await editorApi(page, (api) => api.asc_Save(false));
}

function savedCount(page: Page, count: number) {
  return page.waitForFunction(
    (n) => (window as unknown as SingleWindow).e2eSaves.length >= n,
    count,
    { timeout: 60_000 },
  );
}

const EDITOR_TYPES = [
  {
    type: 'desktop',
    app: /\/documenteditor\/main\//,
    viewport: { width: 1280, height: 720 },
    typeText: typeWithKeyboard,
    save: saveWithKeyboard,
  },
  {
    type: 'mobile',
    app: /\/documenteditor\/mobile\//,
    viewport: { width: 390, height: 844 },
    typeText: typeWithApi,
    save: saveWithApi,
  },
] as const;

test.describe('Local session editing', () => {
  for (const editor of EDITOR_TYPES) {
    test(`edits, saves and reopens a docx with transport "self" (${editor.type})`, async ({
      page,
    }) => {
      test.setTimeout(120_000);
      await page.setViewportSize(editor.viewport);
      await openHostPage(page, SINGLE_HOST_PAGE);
      const missing = await missingCapabilities(page, ['localSession', 'localSessionEditing']);
      // Skipped, not failed, while the image is built from a web-apps without
      // local session editing; once it has it, every failure below is real.
      // eslint-disable-next-line playwright/no-skipped-test
      test.skip(missing.length > 0, `this build of web-apps lacks ${missing.join(', ')}`);

      const serverSession = watchServerSession(page);
      const opened = await openSingle(page, {
        data: Array.from(readFileSync(FIXTURE)),
        type: editor.type,
        mode: 'edit',
      });
      expect(opened).toEqual({ ready: true });
      await expect(page.locator(EDITOR_IFRAME)).toHaveAttribute('src', editor.app);
      expect(await editorApi(page, (api) => api.isViewMode)).toBe(false);

      await editor.typeText(page);
      await editor.save(page);
      await savedCount(page, 1);
      const saved = await page.evaluate(async () => {
        const { fileType, blob } = (window as unknown as SingleWindow).e2eSaves[0];
        return {
          fileType,
          isBlob: blob instanceof Blob,
          bytes: Array.from(new Uint8Array(await blob.arrayBuffer())),
        };
      });
      expect(saved.fileType).toBe('docx');
      expect(saved.isBlob).toBe(true);
      // A docx is a zip archive: "PK\x03\x04".
      expect(saved.bytes.slice(0, 4)).toEqual([0x50, 0x4b, 0x03, 0x04]);

      const text = await documentText(page);
      expect(text).toContain(FIXTURE_TEXT);
      expect(text).toContain(TYPED_TEXT);
      await expect
        .poll(() => editorApi(page, (api) => api.isDocumentModified()), {
          message: 'the document is not modified after the save',
        })
        .toBe(false);

      // Saving again exports again, although nothing changed since.
      await editor.save(page);
      await savedCount(page, 2);
      expect(
        await page.evaluate(() => (window as unknown as SingleWindow).e2eSaves[1].fileType),
      ).toBe('docx');
      expect(serverSession).toEqual([]);

      // The saved file is what the host would store: it opens in a fresh
      // session with the typed text in it.
      await openHostPage(page, SINGLE_HOST_PAGE);
      const reopened = await openSingle(page, {
        data: saved.bytes,
        type: editor.type,
        mode: 'view',
      });
      expect(reopened).toEqual({ ready: true });
      const reopenedText = await documentText(page);
      expect(reopenedText).toContain(FIXTURE_TEXT);
      expect(reopenedText).toContain(TYPED_TEXT);
      expect(serverSession).toEqual([]);
    });
  }

  test('relays co-editing between two editors with transport "host"', async ({
    page,
  }, testInfo) => {
    test.setTimeout(180_000);
    await page.setViewportSize({ width: 1600, height: 800 });
    await openHostPage(page, PAIR_HOST_PAGE);
    const missing = await missingCapabilities(page, [
      'localSession',
      'localSessionEditing',
      'localSessionHostTransport',
    ]);
    // eslint-disable-next-line playwright/no-skipped-test
    test.skip(missing.length > 0, `this build of web-apps lacks ${missing.join(', ')}`);

    const serverSession = watchServerSession(page);
    await page.evaluate(installLocalSessionRelay, 'word' as RelayEditorType);

    // The host picks distinct indexes: they prefix the ids of new objects.
    const users = [
      { id: 'alice', name: 'Alice', indexUser: 1 },
      { id: 'bob', name: 'Bob', indexUser: 2 },
    ];
    const opened = await page.evaluate(
      ({ data, users }) => {
        const w = window as unknown as PairWindow;
        const relay = w.localSessionRelay;
        return Promise.all(
          users.map(
            (user) =>
              new Promise<{ ready: boolean; error?: unknown }>((resolve) => {
                const editor = new w.DocsAPI.DocEditor(`placeholder-${user.id}`, {
                  documentType: 'word',
                  width: '100%',
                  height: '100%',
                  document: {
                    title: 'local-session.docx',
                    fileType: 'docx',
                    permissions: { edit: true },
                    source: { data: new Uint8Array(data) },
                  },
                  editorConfig: {
                    mode: 'edit',
                    session: { type: 'local', transport: 'host', indexUser: user.indexUser },
                    coEditing: { mode: 'fast', change: false },
                    user: { id: user.id, name: user.name },
                  },
                  events: {
                    onDocumentReady: () => resolve({ ready: true }),
                    onError: (e: { data: unknown }) => resolve({ ready: false, error: e.data }),
                    onSessionMessage: (e: { data: unknown }) => relay.receive(user.id, e.data),
                  },
                });
                relay.addClient(user.id, {
                  user: { id: user.id, name: user.name },
                  send: (message) => editor.sendSessionMessage(message),
                });
              }),
          ),
        );
      },
      { data: Array.from(readFileSync(FIXTURE)), users },
    );
    expect(opened).toEqual([{ ready: true }, { ready: true }]);

    const iframeOf = (userId: string) => `#editor-${userId} ${EDITOR_IFRAME}`;
    const relayState = () =>
      page.evaluate(() => {
        const relay = (window as unknown as PairWindow).localSessionRelay;
        return { errors: relay.errors, log: relay.log, changes: relay.changeCount() };
      });

    try {
      // Each editor reports its connection id with sessionAuth; the relay
      // joins it on that message and announces the participants.
      for (const user of users) {
        await expect
          .poll(
            () =>
              page.evaluate(
                (clientId) =>
                  (window as unknown as PairWindow).localSessionRelay.identity(clientId),
                user.id,
              ),
            { message: `${user.id} sent sessionAuth` },
          )
          .toEqual(expect.objectContaining({ indexUser: user.indexUser }));
        const identity = (await page.evaluate(
          (clientId) => (window as unknown as PairWindow).localSessionRelay.identity(clientId),
          user.id,
        )) as RelayIdentity;
        const inFrame = await editorApi(
          page,
          (api) => ({
            userId: api.CoAuthoringApi.getUserConnectionId(),
            indexUser: api.CoAuthoringApi.get_indexUser(),
          }),
          iframeOf(user.id),
        );
        expect(inFrame, 'sessionAuth names the id sdkjs uses').toEqual(identity);
      }

      for (const user of users) {
        await expect
          .poll(
            () =>
              editorApi(
                page,
                () => {
                  const w = window as unknown as {
                    AscCommon: { CollaborativeEditing: { Is_SingleUser(): boolean } };
                  };
                  return w.AscCommon.CollaborativeEditing.Is_SingleUser();
                },
                iframeOf(user.id),
              ),
            { message: `${user.id} switched to co-editing`, timeout: 15_000 },
          )
          .toBe(false);
      }

      // Alice types at the end; fast co-editing sends the change on its own.
      const alice = page.frameLocator(iframeOf('alice'));
      await alice.locator('#editor_sdk').click();
      await page.keyboard.press('Control+End');
      await page.keyboard.type(` ${TYPED_TEXT} by Alice`);
      await expect
        .poll(() => documentText(page, iframeOf('bob')), { timeout: 30_000 })
        .toContain(`${TYPED_TEXT} by Alice`);

      // Bob answers at the start; his changes continue the change index.
      const bob = page.frameLocator(iframeOf('bob'));
      await bob.locator('#editor_sdk').click();
      await page.keyboard.press('Control+Home');
      await page.keyboard.type(`${TYPED_TEXT} by Bob `);
      await expect
        .poll(() => documentText(page, iframeOf('alice')), { timeout: 30_000 })
        .toContain(`${TYPED_TEXT} by Bob`);

      // Both editors converge on the same document.
      await expect
        .poll(async () => {
          const [a, b] = await Promise.all([
            documentText(page, iframeOf('alice')),
            documentText(page, iframeOf('bob')),
          ]);
          return a === b;
        })
        .toBe(true);
    } finally {
      // The message log is the first thing to look at when a run fails.
      await testInfo.attach('relay', {
        body: JSON.stringify(await relayState(), null, 2),
        contentType: 'application/json',
      });
    }

    const state = await relayState();
    expect(state.errors).toEqual([]);
    expect(state.changes).toBeGreaterThan(0);
    expect(state.log).toContainEqual({ dir: 'in', client: 'alice', type: 'saveChanges' });
    expect(state.log).toContainEqual({ dir: 'out', client: 'bob', type: 'saveChanges' });
    expect(state.log).toContainEqual({ dir: 'in', client: 'bob', type: 'saveChanges' });
    expect(state.log).toContainEqual({ dir: 'out', client: 'alice', type: 'saveChanges' });
    expect(serverSession).toEqual([]);
  });
});
