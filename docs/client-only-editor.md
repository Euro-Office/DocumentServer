# Client-only editor: integration guide

The Euro-Office editor can open a document **without a Document Server session**.
The integrator hands the file bytes to the editor, the browser converts them with
x2t compiled to WebAssembly, and the editor runs against an in-page session instead
of the DocService socket. No server receives the document.

This mode is called a **local session**. It is view-only in its first version.
Use it when the file is not reachable by the Document Server, or must not be:

- mail attachments and other documents that are not files on the server,
- end-to-end encrypted files that only exist as plaintext in the browser,
- any integration that already holds the bytes and wants to skip the download
  callback.

For everything else keep using a server session: it supports editing,
co-editing, history, and large spreadsheets convert faster on the server.

## 1. Prerequisites

- A Document Server that ships `x2t/` next to `web-apps/` and `sdkjs/`
  (`<ds>/x2t/x2t.wasm`, `x2t.js`, `converter.js`, `x2t-worker.js`). See
  section 6 for how it is built and served.
- Feature detection in the browser, after loading the API script:

```html
<script src="https://ds.example.org/web-apps/apps/api/documents/api.js"></script>
<script>
  const canRunLocally = DocsAPI.DocEditor.capabilities?.localSession === true;
</script>
```

Older servers have no `capabilities` object; treat that as unsupported and fall
back to a server session.

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
    },
    permissions: { download: true, print: true, copy: true },
  },
  editorConfig: {
    session: {
      type: "local",                    // "server" (default) | "local"
      x2tUrl: undefined,                // optional, defaults to <ds>/x2t/
    },
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

- A local session is view-only. `editorConfig.mode` is forced to `view`,
  `permissions.edit` to `false`, and co-editing is disabled.
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
| `destroyEditor()` | terminates the worker and revokes the object URLs |
| `requestClose()` | unchanged |
| `refreshHistory`, `setHistoryData`, `serviceCommand` and other server-backed methods | no-ops |

Print goes through the same converter (editor print data wrapped as PDF).

### Supported input formats

The first WebAssembly link covers docx, dotx, docm, doc, odt, rtf, txt, html,
epub, xlsx, xltx, xlsm, xls, ods, csv, pptx, potx, pptm, ppt and odp. PDF, DjVu,
XPS and OXPS are opened by the editor's own renderer without conversion. iWork,
HWP and FB2 are not linked; they fail with `-102`.

## 3. Using the converter on its own

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

## 4. Nextcloud apps

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

## 5. How a local session works

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
```

- web-apps registers the transport with `AscCommon.setLocalSessionTransport`
  before `asc_setDocInfo`; sdkjs wraps it so `DocsCoApi` keeps its normal
  `auth`/`license`/`documentOpen` flow. Reconnection is not modelled.
- The `documentOpen` reply lists every extracted image as `media/<name>`, which
  `g_oDocumentUrls` resolves like a server session. No image hook exists.
- `auth` carries the real build version, so the editor's server-version check
  passes without a bypass. License and connection-quota checks return early on
  `appOptions.isLocalSession`.
- Transport methods used by sdkjs: `connect(handlers)`, `send(obj)`, `close()`,
  optional `convert(request, cb)` and `uploadImages(files, cb)`. `convert`
  receives `{ data, format, fileType, title, isPrint, options }` and answers
  `{ status: "ok", data: url }` or `{ status: "err", error }`.

Code: `sdkjs/common/docscoapi.js` (transport registry and adapter),
`web-apps/apps/common/main/lib/util/LocalSession.js` (session logic, tested
without the UI), `web-apps/apps/common/main/lib/controller/LocalSession.js`,
`web-apps/apps/api/documents/api.js`, `core/X2tConverter/build/wasm/`
(converter, worker, README with the build details).

## 6. Building and serving

- **core**: `emcmake cmake -DEO_WASM_X2T=ON …` builds `x2t.js`, `x2t.wasm`,
  `converter.js` and `x2t-worker.js` into `<output>/x2t/`. The option is off by
  default; see `core/X2tConverter/build/wasm/README.md`.
- **Document Server image**: the bundle copies the core-wasm stage's `x2t/` to
  `/x2t/` next to `web-apps/`. Serve it with the same version-hashed path and
  cache policy as `web-apps/`; brotli pays off, the file is large.
- **Develop container**: `make core/wasm/x2t` builds and deploys it in place.
- The editor and x2t must come from the same build: `Editor.bin` is versioned.

## 7. Limitations and roadmap

- View-only. Saving is planned as `exportDocument()` plus a host-side write
  (for E2E files through the browser's encrypting PUT). Collaboration needs a
  host-provided transport relaying the same messages a DocService would; the
  transport interface above is the hook for it.
- No image upload, server spellcheck, plugins that call the server, version
  history, chat, or presenter mode in a local session.
- Visio and the forms app are not wired. Mobile editor untouched.
- Conversion runs in the user's browser: expect seconds and hundreds of MB of
  memory for large spreadsheets. Keep the size limit and fall back to a server
  session for files that may be seen by the server.
