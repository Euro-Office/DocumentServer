# Client-only editor: integration guide

The Euro-Office editor can open a document **without a Document Server session**.
The integrator hands the file bytes to the editor, the browser converts them with
x2t compiled to WebAssembly, and the editor runs against an in-page session instead
of the DocService socket. No server receives the document.

This mode is called a **local session**. It opens documents for viewing and,
where the server's web-apps supports it, for editing; the host page receives the
saved file and decides where it goes. Several editors can co-edit when the host
page relays their messages (section 4), the model CryptPad uses.
Use it when the file is not reachable by the Document Server, or must not be:

- mail attachments and other documents that are not files on the server,
- end-to-end encrypted files that only exist as plaintext in the browser,
- any integration that already holds the bytes and wants to skip the download
  callback.

For everything else keep using a server session: it brings co-editing without
a relay of your own, version history, forcesave callbacks, and large
spreadsheets convert faster on the server.

## 1. Prerequisites

- A Document Server that ships `x2t/` next to `web-apps/` and `sdkjs/`
  (`<ds>/x2t/x2t.wasm`, `x2t.js`, `converter.js`, `x2t-worker.js`). See
  section 9 for how it is built and served.
- Feature detection in the browser, after loading the API script:

```html
<script src="https://ds.example.org/web-apps/apps/api/documents/api.js"></script>
<script>
  const caps = DocsAPI.DocEditor.capabilities || {};
  const canRunLocally = caps.localSession === true;          // open and view
  const canEditLocally = caps.localSessionEditing === true;  // mode "edit", onLocalSessionSave
  const canRelay = caps.localSessionHostTransport === true;  // transport "host"
</script>
```

Older servers have no `capabilities` object, or only `localSession`; treat a
missing flag as unsupported and fall back to a view-only local session or a
server session.

## 2. Opening a document from bytes

The config is the normal `DocsAPI.DocEditor` config with two additions:
`document.source` carries the file, and `editorConfig.session.type` selects the
mode.

```js
const editor = new DocsAPI.DocEditor("placeholder", {
  documentType: "word",                 // word | cell | slide | pdf
  document: {
    title: "report.docx",
    fileType: "docx",                   // selects the converter input format
    source: {
      data: bytes,                      // ArrayBuffer | Uint8Array | Blob
      media: { "image1.png": blob },    // optional, pre-extracted media
      format: undefined,                // optional, "bin": data is Editor.bin (section 5)
      changes: undefined,               // optional, changes to replay (section 5)
    },
    permissions: { download: true, print: true, copy: true },
  },
  editorConfig: {
    session: {
      type: "local",                    // "server" (default) | "local"
      transport: "self",                // "self" (default) | "host" (section 4)
      x2tUrl: undefined,                // optional, defaults to <ds>/x2t/
    },
    mode: "view",                       // default; "edit" in section 3
    lang: "de-DE",
    user: { id: "u1", name: "Alice" },
    customization: { close: { visible: true } },
  },
  events: {
    onAppReady() {},
    onDocumentReady() {},
    onError(e) {},                      // e.data = { errorCode, errorDescription }
    onRequestClose() {},
    onDownloadAs(e) {},                 // e.data = { fileType, url, blob }
    onLocalSessionProgress(e) {},       // e.data = { phase, percent }
  },
});
```

Rules the API enforces (each one logs a `console.warn`):

- `editorConfig.mode` defaults to `view`. `edit` is honoured when
  `permissions.edit !== false` (section 3); review and comments follow the
  usual permission logic. Servers without `localSessionEditing` force `view`.
- `document.url`, `document.key` and `editorConfig.callbackUrl` are ignored.
  `document.source` is ignored unless `session.type` is `local`.
- `fileType` (or `documentType`) is still required; it selects the converter's
  input format. Take it from the real file name, not from the mime type.
- `token` (JWT) is accepted but **not validated by anyone** in a local session.
  Authorize the user before you hand out the bytes.

The bytes are transferred into the editor iframe with `postMessage`. An
`ArrayBuffer` is transferred (detached in the host page); pass a copy if you
need it afterwards. A `Blob` or typed array is copied.

### Events and errors

| Event | Payload | Notes |
|---|---|---|
| `onLocalSessionProgress` | `{ phase: "load" \| "convert" \| "open", percent }` | `load` while `x2t.wasm` downloads, `convert` while x2t runs, `open` while the editor loads the result |
| `onDownloadAs` | `{ fileType, url, blob }` | `blob` is the converted file; `url` is an object URL on the host page's origin, revoke it when done |
| `onLocalSessionSave` | `{ blob, fileType }` | the user saved; `blob` is the whole document in `document.fileType` (section 3) |
| `onLocalSessionMedia` | `{ name, blob }` | the user inserted an image (section 3) |
| `onSessionMessage` | the message object sdkjs sent | transport `host` only (section 4) |
| `onError` | `{ errorCode, errorDescription }` | codes below, in addition to the server-session codes |

| Code | Meaning |
|---|---|
| `-100` | the converter (`x2t.js`/`x2t.wasm`/worker) could not be loaded |
| `-101` | conversion failed (unreadable file, unusable `source.data`) |
| `-102` | the format is not supported in a local session |
| `-103` | out of memory in the converter |

### Methods

| Method | Local session behaviour |
|---|---|
| `downloadAs(format)` | converts in the browser and fires `onDownloadAs` with `blob` and `url` |
| `sendSessionMessage(message)` | transport `host`: delivers `message` to sdkjs as if the DocService had sent it |
| `addSessionMedia({ name: blob })` | makes images from elsewhere (other editors, storage) resolvable by name |
| `destroyEditor()` | terminates the worker and revokes the object URLs |
| `requestClose()` | unchanged |
| `refreshHistory`, `setHistoryData`, `serviceCommand` and other server-backed methods | no-ops |

Print goes through the same converter (editor print data wrapped as PDF).

### Supported input formats

The first WebAssembly link covers docx, dotx, docm, doc, odt, rtf, txt, html,
epub, xlsx, xltx, xlsm, xls, ods, csv, pptx, potx, pptm, ppt and odp. PDF, DjVu,
XPS and OXPS are opened by the editor's own renderer without conversion. iWork,
HWP and FB2 are not linked; they fail with `-102`.

## 3. Editing in a local session

Needs `capabilities.localSessionEditing`.

```js
const editor = new DocsAPI.DocEditor("placeholder", {
  documentType: "word",
  document: {
    title: "report.docx",
    fileType: "docx",                   // also the format saves are written in
    permissions: { edit: true },
    source: { data: bytes },
  },
  editorConfig: {
    mode: "edit",
    session: { type: "local" },         // transport "self" is the default
    user: { id: "u1", name: "Alice" },
  },
  events: {
    async onLocalSessionSave(e) {       // e.data = { blob, fileType }
      await store("report.docx", e.data.blob);
    },
    onLocalSessionMedia(e) {},          // e.data = { name, blob }
  },
});
```

- **Transport `self`** (default): the editor is the only user and answers its
  own co-editing messages. Locks are granted to itself, changes are kept in
  memory since the document was opened, there is no co-authoring.
- **Saving**: the save button, Ctrl+S and `asc_Save` export the current
  document to `document.fileType` in the browser (x2t `bin → <fileType>`, with
  all media including inserted images) and fire `onLocalSessionSave`. The
  document then counts as unmodified. The editor writes nothing anywhere: the
  host stores the blob, for end-to-end encrypted files through the browser's
  encrypting upload. Only user saves fire the event, not autosave or the
  change sends of co-editing.
- **Images**: inserting or pasting an image stores it as session media
  `media/<generated name>`, shows it from a blob URL, includes it in later
  exports and fires `onLocalSessionMedia`. `addSessionMedia({ name: blob })`
  adds images that come from elsewhere, for example another editor (section 4).
- Off in a local session: chat, version history, the server spellchecker,
  plugins that call the server, forcesave callbacks.

Open in the contract:

- `fileType` formats x2t cannot write (`doc`, `xls`, `ppt`, `epub`, `html`, …;
  the writers are listed in section 6) have no defined save behaviour. Convert
  such files first (section 6) and open the result, or keep them view-only.
- Whether Ctrl+S on an unmodified document fires `onLocalSessionSave` again.
- Images inserted by URL (fetched by the DocService in a server session).

## 4. Co-editing through the host page

Needs `capabilities.localSessionHostTransport`. With `transport: "host"` the
editor still answers `license`, `auth`, `documentOpen` and `imgurls` itself;
every other message sdkjs would send to the DocService goes to
`onSessionMessage`, and whatever the host passes to `sendSessionMessage` reaches
sdkjs unchanged. Lock arbitration, change order and the participant list are
the host's job, as in CryptPad, where the host relays over its encrypted
realtime channel. Messages are plain JSON (changes are strings), so any
channel works.

```js
editorConfig: {
  mode: "edit",
  session: { type: "local", transport: "host" },
  coEditing: { mode: "fast", change: false },   // or "strict"
  user: { id: "u1", name: "Alice" },
},
events: {
  onSessionMessage(e) { relay.receive("alice", e.data); },
},
// and: relay sends with editor.sendSessionMessage(message)
```

Locks and changes name their owner by the **connection id**, `user.id` followed
by `indexUser` (sdkjs `_userId`, for example `u10`), and sdkjs compares against
it. The host must use the same id. Open in the contract: the editor's local
`auth` reply chooses `indexUser` (0 today) and the host has no way to read or
set it. Editors with the same `indexUser` generate the same ids for new objects
(`<indexUser>_<n>`), so co-editing editors need distinct values.

### Editor → host (`onSessionMessage`)

| `type` | Fields | Host answers |
|---|---|---|
| `getLock` | `block`: array of block ids (word) or objects with `guid` (cell, slide, pdf) | `getLock` to the sender and every other editor |
| `isSaveLock` | `syncChangesIndex` | `saveLock` to the sender |
| `saveChanges` | `changes` (JSON string of an array of change strings), `startSaveChanges`, `endSaveChanges`, `deleteIndex`, `releaseLocks`, `unlock`, `isCoAuthoring`, `isExcel`, `excelAdditionalInfo` (JSON string or `null`), `reSave` | `saveChanges` to the others; `savePartChanges` to the sender, or `unSaveLock` after the last chunk |
| `unSaveLock` | – | `unSaveLock` with `index`, `time`, `syncChangesIndex` all `-1` |
| `unLockDocument` | `isSave`, `unlock`, `deleteIndex`, `releaseLocks` | `releaseLock` to everyone if the sender held locks and `releaseLocks`; `unSaveLock` (`-1`s) if `isSave` |
| `cursor` | `cursor` | `cursor` to the others |
| `close` | – | drop the sender's locks (`releaseLock`), new `connectState` |
| `message`, `getMessages` | – | chat, off in local sessions; ignore |
| `authChangesAck`, `extendSession`, `clientLog`, `updateVersion` | – | nothing |
| `forceSaveStart`, `rpc` | – | open in the contract; ignore |

### Host → editor (`sendSessionMessage`)

```js
{ type: "connectState", participantsTimestamp, waitAuth: false, participants: [
    { id: "u10", idOriginal: "u1", username: "Alice", indexUser: 0,
      connectionId: "c1", isCloseCoAuthoring: false, view: false } ] }
{ type: "getLock", locks: { [lockId]: { time, user, block } } }           // every current lock
{ type: "releaseLock", locks: [{ block, user, time, changes: null }] }
{ type: "saveLock", saveLock: false }                                      // true: someone else saves, retry
{ type: "savePartChanges", changesIndex, syncChangesIndex }
{ type: "unSaveLock", index, time, syncChangesIndex }
{ type: "saveChanges", changes: [{ docid, change, time, user, useridoriginal }],
  changesIndex, syncChangesIndex, endSaveChanges, locks, excelAdditionalInfo }
{ type: "cursor", messages: [{ cursor, time, user, useridoriginal }] }
```

The rules, from `server/DocService/sources/DocsCoServer.js`:

- **Participants**: send the full list to every editor, the one that joined
  included (it did not get the list from the host in its `auth` reply).
  `participantsTimestamp` must not go backwards. Two or more participants with
  `view: false` switch the editors into co-editing; the editors then send
  `unLockDocument`.
- **Locks**: the lock id is the block (word) or `block.guid` (others). Word
  keeps the free blocks of a request; the other editors get all or none, and
  the DocService also checks Excel range overlaps (`_checkLockExcel`).
- **Save lock**: one editor saves at a time. `isSaveLock` takes it, the last
  `saveChanges` chunk or `unSaveLock` releases it.
- **Change order**: the host keeps one ordered list of change records. Each
  change string of a batch becomes `{ docid, change: JSON.stringify(item), time,
  user: <connection id>, useridoriginal: <user.id> }`. On `startSaveChanges`
  with a `deleteIndex` other than `null`/`-1`, truncate the list to that length
  first; `unLockDocument` does the same. To the others, `changesIndex` and
  `syncChangesIndex` are the list length after appending. To the sender,
  `index` (or `changesIndex` in `savePartChanges`) is the batch's start index
  when it is the first chunk without `deleteIndex`, else `-1`;
  `syncChangesIndex` is the list length and `time` the batch time in ms.
- **Releasing with the save**: with `releaseLocks` on the last chunk, remove the
  sender's locks and send them as `locks` in the others' `saveChanges`.

Not covered: the `waitAuth` handshake and `authChanges` for editors that join
after changes were made. Open such an editor from the same base with the
changes so far (section 5) instead.

### A minimal relay

Two editors in one page. Across browsers, put your channel between `receive`
and `send`, and keep one instance of this state per document on the side that
orders the changes. A fuller version with logging, `close`/leave and
all-or-none locks is the e2e test relay,
`e2e/frontend/tests/local-session-relay.ts`.

```js
function createRelay() {
  const editors = new Map();              // name -> { userId, indexUser, user, send }
  const locks = {};
  const changes = [];
  let saving = null;
  const others = (me) => [...editors.values()].filter((e) => e !== me);
  const all = () => [...editors.values()];
  const lockList = (userId) => Object.keys(locks).filter((id) => locks[id].user === userId)
    .map((id) => { const l = locks[id]; delete locks[id]; return { ...l, changes: null }; });

  return {
    join(name, editor) {
      editors.set(name, editor);
      const participants = all().map((e) => ({ id: e.userId, idOriginal: e.user.id,
        username: e.user.name, indexUser: e.indexUser, connectionId: e.userId,
        isCloseCoAuthoring: false, view: false }));
      all().forEach((e) => e.send({ type: "connectState", participantsTimestamp: Date.now(),
        participants, waitAuth: false }));
    },
    receive(name, msg) {
      const me = editors.get(name);
      if (!me) return;                    // not joined yet
      switch (msg.type) {
        case "getLock":
          for (const block of msg.block) {
            const id = block.guid ?? block;
            if (!locks[id] || locks[id].user === me.userId)
              locks[id] = { time: Date.now(), user: me.userId, block };
          }
          all().forEach((e) => e.send({ type: "getLock", locks }));
          break;
        case "isSaveLock": {
          const busy = saving !== null && saving !== me.userId;
          if (!busy) saving = me.userId;
          me.send({ type: "saveLock", saveLock: busy });
          break;
        }
        case "saveChanges": {
          const noDelete = msg.deleteIndex == null || msg.deleteIndex === -1;
          if (msg.startSaveChanges && !noDelete) changes.length = msg.deleteIndex;
          const start = changes.length, time = Date.now();
          const batch = JSON.parse(msg.changes).map((c) => ({ docid: "doc",
            change: JSON.stringify(c), time, user: me.userId, useridoriginal: me.user.id }));
          changes.push(...batch);
          const released = msg.endSaveChanges && msg.releaseLocks ? lockList(me.userId) : [];
          others(me).forEach((e) => e.send({ type: "saveChanges", changes: batch,
            changesIndex: changes.length, syncChangesIndex: changes.length,
            endSaveChanges: msg.endSaveChanges, locks: released,
            excelAdditionalInfo: msg.excelAdditionalInfo }));
          const index = msg.startSaveChanges && noDelete ? start : -1;
          if (!msg.endSaveChanges) {
            me.send({ type: "savePartChanges", changesIndex: index, syncChangesIndex: changes.length });
          } else {
            saving = null;
            me.send({ type: "unSaveLock", index, time, syncChangesIndex: changes.length });
          }
          break;
        }
        case "unSaveLock":
          saving = null;
          me.send({ type: "unSaveLock", index: -1, time: -1, syncChangesIndex: -1 });
          break;
        case "unLockDocument": {
          if (msg.deleteIndex != null && msg.deleteIndex !== -1) changes.length = msg.deleteIndex;
          const released = msg.releaseLocks ? lockList(me.userId) : [];
          if (released.length) all().forEach((e) => e.send({ type: "releaseLock", locks: released }));
          if (msg.isSave) { saving = null; me.send({ type: "unSaveLock", index: -1, time: -1, syncChangesIndex: -1 }); }
          break;
        }
        case "cursor":
          others(me).forEach((e) => e.send({ type: "cursor", messages: [{ cursor: msg.cursor,
            time: Date.now(), user: me.userId, useridoriginal: me.user.id }] }));
          break;
      }
    },
  };
}

const relay = createRelay();
const user = { id: "alice", name: "Alice" };
const alice = new DocsAPI.DocEditor("left", {
  /* document as in section 3, editorConfig as above with this user */
  events: {
    onSessionMessage: (e) => relay.receive("alice", e.data),
    // "alice0": user.id + indexUser, see the open point on the connection id
    onDocumentReady: () => relay.join("alice", { userId: "alice0", indexUser: 0, user,
      send: (m) => alice.sendSessionMessage(m) }),
  },
});
// the same for "bob" in a second placeholder
```

Messages an editor sends before `join` need the connection id; the e2e relay
queues them until the editor has joined.

## 5. Opening from Editor.bin and saved changes

A host that relays changes can store the document the way CryptPad does: a
checkpoint in the editor's own format plus the changes made since.

```js
document: {
  title: "report.docx",
  fileType: "docx",                     // still the format saves are written in
  source: {
    data: editorBin,                    // Editor.bin, e.g. converter.convert({ to: "bin" })
    format: "bin",                      // skip the x2t import
    media: { "image1.png": blob },      // the checkpoint's images, plus images added since
    changes: savedChanges,              // replayed in order after the open
  },
},
```

- `Editor.bin` is tied to the editor build that wrote it (section 9). Keep the
  original file, or a saved one, to rebuild the checkpoint after an upgrade.
- `changes` go into the editor's local `auth` reply (and `authChanges`), so
  sdkjs replays them as it does a server session's pending changes. They also
  work with a normal (`format` unset) source.
- Open in the contract: the element shape of `changes`. It says "as sdkjs sends
  them in `saveChanges`"; the simplest reading is the change strings of every
  batch in list order (`JSON.parse(msg.changes)` of each `saveChanges`,
  flattened). Whether DocService-style records (`{ change, user, time, … }`)
  are accepted as well is for the implementation to settle.

## 6. Using the converter on its own

`converter.js` is an ES module and can be used without the editor, for example
to export a file the user already has in the browser.

```js
import { createConverter } from "https://ds.example.org/x2t/converter.js";

const x2t = await createConverter();          // { baseUrl } overrides the directory
const { data, media } = await x2t.convert({
  data: bytes,                                // ArrayBuffer | Uint8Array | Blob
  fileName: "report.docx",                    // extension selects the input format
  to: "bin",                                  // bin | docx | xlsx | pptx | odt | ods | odp | csv | txt | rtf | pdf
  fonts: { "arial.ttf": arrayBufferOrUrl },   // optional, needed for layout-dependent output
  themes: { "theme1/theme.xml": buffer },     // optional, presentations
  media: { "image1.png": buffer },            // optional, for exports from bin
  type: "word",                               // word | cell | slide, required when fileName ends in .bin
  pdfBin: printBytes,                         // required for to: "pdf"
});
x2t.terminate();
```

`data` is a `Uint8Array` with the output file. `media` holds the images x2t
extracted when `to` is `bin`. Errors reject with an `Error` whose `code` is
`load`, `convert` (with `exitCode`), `unsupported` or `memory`. The conversion
runs in a Web Worker started from the same directory, so the module must be
loaded from the Document Server origin or a copy of the whole `x2t/` directory.

## 7. Nextcloud apps

The Euro-Office Nextcloud app wraps all of the above. Other Nextcloud apps have
three entry points.

### Through the Viewer

The app registers its Viewer handler with `supportsSource: true` when the admin
has enabled local sessions. Any app can then open a document that has no file id:

```js
const handler = OCA.Viewer.availableHandlers.find(
  (h) => h.supportsSource && h.mimes.includes(mime));
if (handler) {
  OCA.Viewer.openWith(handler.id, {
    fileInfo: { source: downloadUrl, filename: downloadUrl, basename: "report.docx", mime, hasPreview: false },
  });
}
```

`source` is fetched with the user's session cookie, so a normal authenticated
route is enough. The Mail app uses exactly this for attachments. Files that
carry the `e2ee-is-encrypted` attribute are opened the same way from the Files
app; the E2E web client's fetch interceptor decrypts the DAV download in the
browser.

### Directly

```js
const session = OCA.Eurooffice.openSource({
  data: blob,                 // or url: string, fetched with credentials
  name: "report.docx",
  mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  mode: "auto",               // "auto" | "local" | "server"
  container: element,         // optional; without it the Viewer is used
});
session?.destroy();           // only when a container was given
```

Without `container` the call goes through `OCA.Viewer.openWith`. With a
container an iframe is mounted and `{ destroy }` is returned. The call returns
`null` and shows a toast when local sessions are disabled or the Viewer is
missing.

### The editor page and its config endpoint

Apps that embed the editor page themselves can use the two routes the app adds:

| Route | Purpose |
|---|---|
| `GET /apps/eurooffice/local?fileName=…&inframe=true&inviewer=true` | editor page for a local session; it posts `{ method: "localSessionReady" }` to its parent and expects `{ type: "eurooffice-local-source", buffer, name, mime }` back (same origin, transferable buffer) |
| `GET /ocs/v2.php/apps/eurooffice/api/v1/config/local?fileName=…` | the editor config without a document: user, language, customization, `documentServerUrl`, `session: { type: "local" }`; `422` for unsupported extensions, `403` when disabled |

Admin settings (`Administration → Euro-Office`): enable client-only sessions,
maximum file size for them, and whether end-to-end encrypted files always use
them. The viewer refuses larger files with a translated message instead of
falling back to a server session, because a server session would leak the
plaintext.

## 8. How a local session works

For editor developers; integrators do not need this.

```
host page                      editor iframe (Document Server origin)
DocsAPI.DocEditor ──postMessage openDocumentSource──► web-apps LocalSession controller
                                                        │ createConverter() in a Worker
                                                        │ bytes ──► Editor.bin + media
                                                        ▼
                               sdkjs DocsCoApi ◄── in-page transport ── LocalSession
                                 auth ───────────────────────────────► license, authChanges, auth,
                                                                       documentOpen { Editor.bin, media/* }
                                 openDocument imgurls ───────────────► documentOpen { imgurls }
                                 downloadAs ─────────────────────────► transport.convert → Blob → onDownloadAs
                                 asc_Save ───────────────────────────► saveChanges … → transport.convert → onLocalSessionSave
                                 insert image ───────────────────────► transport.uploadImages → media/<name> → onLocalSessionMedia
                                 getLock, saveChanges, … ────────────► "self": answered by LocalSession
                                                                       "host": Gateway → onSessionMessage
                               sendSessionMessage ───────────────────► sdkjs unchanged
```

- web-apps registers the transport with `AscCommon.setLocalSessionTransport`
  before `asc_setDocInfo`; sdkjs wraps it so `DocsCoApi` keeps its normal
  `auth`/`license`/`documentOpen` flow. Reconnection is not modelled.
- The `documentOpen` reply lists every extracted image as `media/<name>`, which
  `g_oDocumentUrls` resolves like a server session. Inserted images and
  `addSessionMedia` go into the same map, so no image hook exists.
- `auth` carries the real build version, so the editor's server-version check
  passes without a bypass. License and connection-quota checks return early on
  `appOptions.isLocalSession`.
- Transport methods used by sdkjs: `connect(handlers)`, `send(obj)`, `close()`,
  `convert(request, cb)` and `uploadImages(files, cb)`. `convert` receives
  `{ data, format, fileType, title, isPrint, options }` and answers
  `{ status: "ok", data: url }` or `{ status: "err", error }`. `uploadImages`
  answers with blob URLs of the stored media.
- In transport `host`, `auth` is still answered in the frame, so the host
  never sees it; the host's first messages are `connectState`.

Code: `sdkjs/common/docscoapi.js` (transport registry and adapter),
`web-apps/apps/common/main/lib/util/LocalSession.js` (session logic, tested
without the UI), `web-apps/apps/common/main/lib/controller/LocalSession.js`,
`web-apps/apps/api/documents/api.js`, `core/X2tConverter/build/wasm/`
(converter, worker, README with the build details).

## 9. Building and serving

- **core**: `emcmake cmake -DEO_WASM_X2T=ON …` builds `x2t.js`, `x2t.wasm`,
  `converter.js` and `x2t-worker.js` into `<output>/x2t/`. The option is off by
  default; see `core/X2tConverter/build/wasm/README.md`.
- **Document Server image**: the bundle copies the core-wasm stage's `x2t/` to
  `/x2t/` next to `web-apps/`. Serve it with the same version-hashed path and
  cache policy as `web-apps/`; brotli pays off, the file is large.
- **Develop container**: `make core/wasm/x2t` builds and deploys it in place.
- The editor and x2t must come from the same build: `Editor.bin` is versioned.

## 10. Limitations and roadmap

- Editing and host-relayed co-editing need a web-apps with
  `localSessionEditing` / `localSessionHostTransport`; older servers stay
  view-only.
- The host owns storage and, in transport `host`, the relay: lock arbitration,
  change order and participants. There is no `waitAuth` handshake for late
  joiners; open them from the same base plus the changes so far (section 5).
- Open in the contract: how the host learns or sets each editor's connection
  id and `indexUser` (section 4), the element shape of `source.changes`,
  saving to formats x2t cannot write, `forceSaveStart` and `rpc` in transport
  `host`, and images inserted by URL.
- No server spellcheck, plugins that call the server, version history, chat,
  forcesave callbacks or presenter mode in a local session.
- Visio and the forms app are not wired. The mobile document, spreadsheet and
  presentation editors (`type: "mobile"`) support local sessions like the
  desktop ones; phones have less memory for x2t, so use a lower size limit there.
- Conversion runs in the user's browser: expect seconds and hundreds of MB of
  memory for large spreadsheets. Keep the size limit and fall back to a server
  session for files that may be seen by the server.

## 11. Migrating from CryptPad's onlyoffice-editor

CryptPad's `onlyoffice-editor` package wraps a patched `api.js` (`api-orig.js`)
and plays the DocService in the host page through hooks. The local session
covers the same ground with the stock `api.js`:

| CryptPad | Local session |
|---|---|
| `connectMockServer(server)`, `server.onMessage(msg)` fed by the `cryptPadSendMessageFromOO` event | `session: { type: "local", transport: "host" }` and `events.onSessionMessage` |
| `cryptPadMessageToOO(msg)` / `sendMessageToOO(msg)` | `docEditor.sendSessionMessage(msg)`, same message shapes |
| the host answers `auth`: `authChanges`, `auth` with `server.getParticipants()` and `indexUser`, `documentOpen` with `Editor.bin` | answered in the frame; participants arrive with `connectState` from the host, `Editor.bin` with `source: { data, format: "bin" }`, initial changes with `source.changes`. Choosing `indexUser` is open (section 4) |
| `server.getInitialChanges()` (patches since the checkpoint) | `document.source.changes` |
| `getImageURL(name)` resolving images to blob URLs, `g_oDocumentUrls.addImageUrl` from the host | `source.media` at open, `addSessionMedia({ name: blob })` later |
| `APP.AddImage` / `APP.UploadImageFiles` with CryptPad's file picker | the editor's own image insert and paste; `onLocalSessionMedia { name, blob }` gives the host the file to encrypt and share |
| `APP.printPdf` and `x2tConvertData` running x2t in the host | print and `downloadAs` convert in the editor frame; `onLocalSessionSave` delivers the document in `fileType`; `converter.js` for conversions of your own (section 6) |
| the "History" participant that keeps the editor in co-editing mode | not needed for correctness: a single editor in transport `host` still sends its changes on save. Listing an extra participant keeps fast co-editing's immediate sends, as before |
| `installLegacyChannel`, `injectCSS`, `getIframe` reaching into the frame | not part of the API; style through `editorConfig.customization` |

The relay logic of CryptPad's `inner.js` (`handleLock`, `handleChanges`,
`handleNewIds`, checkpoints) stays in CryptPad; only the transport to the
editor changes.
