# Client-only editor: plan and integration API

Status: plan under review; first implementation on feature branches (see section 8).

Goal: open office documents in the Euro-Office editor **without a Document Server
session**, so that

1. Nextcloud Mail can show office attachments in the viewer (no Nextcloud file id),
2. end-to-end encrypted files can be viewed in the browser without any server ever
   seeing plaintext,
3. any other integrator (Talk, Deck, public links, third parties) can open a document
   from bytes it already holds.

Viewing is the first milestone. Saving and collaboration are designed for but
explicitly out of scope for the first delivery.

Related tickets: eurooffice-nextcloud#104, nextcloud/mail#5988,
nextcloud/end_to_end_encryption#1495.

---

## 1. Summary of the approach

Today the editor iframe talks to the DocService over socket.io, and the DocService
downloads the file from `document.url`, converts it with x2t to the editor's binary
format (`Editor.bin`), and streams it back. Every integration therefore needs a URL
the server can fetch, and the server always holds plaintext.

CryptPad proved the alternative: compile x2t to WebAssembly, run it in the browser,
and replace the socket with an in-page message channel. Their patch set is small and
we already own every repository it touches.

We will build this as a **supported mode of the editor**, called a *local session*,
not as a per-integration hack:

```
host page (Nextcloud, Mail, anything)        editor iframe (DS origin)
┌─────────────────────────────────┐          ┌────────────────────────────────┐
│ DocsAPI.DocEditor(config)       │ postMsg  │ web-apps  LocalSession         │
│   document.source = { data }  ──┼─────────►│   ├─ x2t worker  (x2t.wasm)    │
│   editorConfig.session.type     │          │   │    bytes ──► Editor.bin    │
│     = "local"                   │◄─────────┤   └─ answers auth/documentOpen │
│ events: onAppReady, onError,    │  events  │ sdkjs  DocsCoApi.transport     │
│   onDownloadAs(blob) …          │          │   (in-page instead of socket)  │
└─────────────────────────────────┘          └────────────────────────────────┘
                                                no DocService, no converter,
                                                no callback URL
```

The document bytes cross exactly one boundary: from the host page into the editor
iframe via `postMessage`. They never leave the browser.

What we reuse from CryptPad and what we do not:

| Piece | CryptPad repo | Decision |
|---|---|---|
| x2t compiled with emscripten (core patches, build recipe, node test harness) | `onlyoffice-x2t-wasm` | **Port.** Core patches are small. Build with our existing `core-wasm` CMake/emcmake pipeline instead of their qmake Dockerfile. |
| In-browser mock server, `Editor.bin` handshake, image URL resolution, print/download hooks | `onlyoffice-editor` wrapper + sdkjs/web-apps patches | **Reimplement** as a formal API. Their version couples to `window.parent.APP` and comments out license checks globally. Offer the result back to CryptPad. |
| Font table generation (`fonts-js-tmp.js`, 43k lines) | `onlyoffice-editor` | **Not needed.** Our chain already generates `AllFonts.js` from `core-fonts` via `AllFontsGen`. |
| Realtime layer (ChainPad) | `cryptpad` | **Not reused.** Only the message relay shape informs our transport interface. |

Facts measured from their repositories (sdkjs/web-apps at tag v9.3.0.140, our
DocumentServer is at 9.3.8-rc.1):

- sdkjs source diff: ~500 lines across `common/docscoapi.js`, `common/apiBase.js`,
  `common/GlobalLoaders.js`, `common/CollaborativeEditingBase.js`,
  `common/editorscommon.js`, plus `word/api.js`, `slide/api.js`, `cell/api.js`.
- web-apps diff: ~200 lines (`apps/api/documents/api.js`, `apps/common/Gateway.js`,
  `*/controller/Main.js` license and version bypass, `protect` disabled).
- x2t driver JS: ~300 lines (writes fonts, media, themes, input and `params.xml` into
  the Emscripten FS, calls exported `main1(xmlPath)`, reads back `<file>.bin` and
  `media/*`).
- Their test stage already compares output against `ghcr.io/euro-office/documentserver`.

---

## 2. Workstreams

The three editor-side tracks (A, B, C) are independent of the Nextcloud tracks (E, F)
and of each other until integration. They can start in parallel immediately.

### Track A: x2t as a WebAssembly target of `core` (owner: core/DS build)

Deliverable: `x2t.js` + `x2t.wasm` produced by `docker buildx bake core-wasm` and
shipped by the DS image under a versioned static path, e.g.
`/{version}/x2t/x2t.js`, next to `web-apps`, `sdkjs` and `fonts`.

Steps:

1. Spike (1–2 weeks): build `cryptpad/onlyoffice-x2t-wasm` as-is against its vendored
   core, then rebase its core patches onto `Euro-Office/core`. Record WASM size
   (uncompressed and brotli), startup time, and conversion time for a representative
   docx, xlsx, pptx and odt set. These numbers decide the local-versus-server
   thresholds in Track E.
2. Add an emcmake entry for `core/X2tConverter` to `core/.docker/core-wasm.bake.Dockerfile`
   and a `build-x2t` target in `develop/setup/Makefile` using the existing `build_wasm`
   macro (`EO_CORE_3RD_PARTY_DIR`, `/opt/emsdk`). Link flags from CryptPad:
   `-sEXPORTED_RUNTIME_METHODS=ccall,FS -sEXPORTED_FUNCTIONS=_main1 -sALLOW_MEMORY_GROWTH`,
   plus the `main1(char*)` wrapper and the `noInitialRun` pre-js.
3. Port the core patches needed for emscripten (ICU disabled in `UnicodeConverter`,
   empty `doctrenderer`/`docbuilder`, boost header-only use, freetype and katana fixes).
   Keep them behind an `EO_WASM` CMake option so native builds are untouched.
4. Node test harness: adapt CryptPad's `test.js` to run the WASM converter against the
   native `x2t` from our own image and diff the resulting `Editor.bin`. Run it in CI
   for the `core-wasm` target.
5. Publish the artifact in the DS image and in `document-server-package`. Serve with
   long cache headers under the version-hashed path and with brotli.

Out of scope for A: PDF *input* (sdkjs already renders PDF client-side via
`drawingfile.wasm`), diagram formats, HWP/iWork (keep the libraries out of the first
link to reduce size; add on demand).

### Track B: sdkjs transport and local hooks (owner: sdkjs)

Deliverable: a `transport` option on `DocsCoApi` and explicit host hooks, no
`window.parent` access.

1. `common/docscoapi.js`: extract socket creation into a transport. Default
   `SocketIoTransport` (current behaviour). New `MessageTransport` that sends every
   outgoing command to the web-apps frame through `Common.Gateway` and receives
   `_onServerMessage` calls from it. Selected by `editorConfig.session.type`.
2. `common/GlobalLoaders.js`: image loading asks an `Asc.editor.resolveImageUrl(name)`
   hook before falling back to the URL in the bin. In local mode web-apps answers from
   the media map produced by the conversion. (CryptPad: `APP.getImageURL`.)
3. `common/CollaborativeEditingBase.js`: the `imgurls` round trip to the server is
   answered locally when a transport is in local mode.
4. `common/apiBase.js` and `common/editorscommon.js`: `downloadAs`, print and image
   upload route through `sendEvent("asc_onRequestLocalConvert", …)` /
   `"asc_onRequestLocalUpload"` instead of the DS upload and convert endpoints when in
   local mode.
5. `cell/api.js`, `slide/api.js`, `word/api.js`: audit CryptPad's remaining diffs; most
   are whitespace. Take only the image-callback additions.
6. Keep `BroadcastChannel` guarded (their Tor fix is a harmless upstreamable change).

Everything is additive and defaults to current behaviour. Unit tests exist for
`docscoapi` message encoding; add a test that drives the editor through
`MessageTransport` with a recorded `auth`/`documentOpen` exchange.

### Track C: web-apps local session (owner: web-apps)

Deliverable: `DocsAPI.DocEditor` accepts a local session and a `LocalSession`
controller replaces the DocService for that session.

1. `apps/api/documents/api.js`: accept `document.source` (Blob, ArrayBuffer or
   Uint8Array, plus optional `media` map) and `editorConfig.session`. Transfer the
   bytes to the iframe with `postMessage` (transferable). Expose
   `DocsAPI.DocEditor.capabilities.localSession = true` for feature detection.
2. `apps/common/Gateway.js`: two generic channels, `localSessionCommand` (to editor)
   and `localSessionEvent` (from editor), replacing CryptPad's `cryptPad*` names.
3. New `apps/common/main/lib/controller/LocalSession.js`:
   - starts the x2t worker from `../x2t/x2t.js` (same origin as the editor),
   - fetches the fonts the converter needs from `/fonts/` and theme binaries from
     `sdkjs/slide/themes/`,
   - converts `source` to `Editor.bin`, keeps the extracted media as blob URLs,
   - answers `auth` with `{ result: 1, licenseType: 3, participants: [self], changes: [] }`,
     then `documentOpen` with `{ "Editor.bin": <blob url> }`,
   - answers `imgurls`, `saveChanges` (view mode: reject), `getLock`, `unLockDocument`
     with local no-ops,
   - implements `downloadAs`/print by converting the bin back with x2t and emitting
     `onDownloadAs` with a `Blob`.
4. `*/controller/Main.js`: skip `applyLicense`, `onServerVersion` and the connection
   quota checks **only when** `session.type === "local"`; force
   `permissions.protect = false`, `canCoAuthoring = false`, and `mode = "view"` for the
   first milestone.
5. Mobile editor build stays untouched (CryptPad disables it; we do not).

### Track D: Document Server packaging (owner: DS/server)

- Serve `/x2t/` from nginx with the same version-hash prefix and cache policy as
  `web-apps`.
- Add `localSession: true` to the `info` endpoint the connector already queries for
  version checks, so integrators can detect support server-side too.
- No DocService changes. No callback. Document key is not needed.

### Track E: Nextcloud connector (`eurooffice-nextcloud`) (owner: connector)

1. Refactor: extract config building from `EditorApiController::config()` into a
   document-source abstraction (node, share, external URL, client bytes). This also
   serves the server-side Mail fallback later.
2. Viewer handler (`src/viewer.js`): accept `source`, `basename`, `mime` props; the
   Viewer binds the whole fileInfo so no Viewer change is needed.
3. New open path in the handler:
   - decide mode: `local` when the node has `e2ee-is-encrypted`, when there is no file
     id, when the admin forced it, or when the file is below the size threshold from
     Track A; otherwise the existing server session,
   - fetch bytes in the browser (`fetch(node.encodedSource)`; the E2E GET interceptor
     decrypts transparently; a Mail attachment URL works with the session cookie),
   - load `api.js` from the DS as today and construct a local session.
4. Public JS entry for other Nextcloud apps:
   `OCA.Eurooffice.openSource({ data | url, name, mime, mode })` (see API section).
5. CSP on pages that embed the editor: `allowEvalWasm(true)` is not required on the
   Nextcloud origin because x2t runs inside the DS-origin iframe; `blob:` frame and
   media sources are already added by the E2E app and by `EditorController::index`.
6. Admin settings: enable client-side viewing (default on when the DS reports
   `localSession`), size threshold, force-local for E2E.
7. E2E specifics: take the extension from the decrypted display name, not the DAV
   name. On Nextcloud 36 the Viewer is E2E-aware; verify the handler opts in.

### Track F: Nextcloud Mail (owner: mail)

1. `src/mixins/AttachmentMixin.js`: include office mimes when a viewer handler
   advertises `source` support (`OCA.Viewer.availableHandlers` entry with
   `supportsSource === true`, set by the connector on registration).
2. `showViewer`: `OCA.Viewer.openWith('eurooffice', { fileInfo: { source: downloadUrl,
   basename, mime } })`.
3. Optional later: signed session-free attachment URL (HMAC via `ICrypto`, pattern in
   `lib/Html/ProxyHmacGenerator.php`) for the server-side fallback on large files.

Ticket nextcloud/mail#5988 is open and triaged; the connector change should land
first so Mail can feature-detect it.

---

## 3. Public API for integrators

### 3.1 Editor: local session

Load the API from the Document Server as today:

```html
<script src="https://ds.example.org/web-apps/apps/api/documents/api.js"></script>
```

Feature detection:

```js
const canRunLocally = DocsAPI.DocEditor.capabilities?.localSession === true;
```

Open a document from bytes:

```js
const editor = new DocsAPI.DocEditor("placeholder", {
  documentType: "word",                 // word | cell | slide | pdf
  document: {
    title: "report.docx",
    fileType: "docx",
    // NEW: bytes instead of url. Exactly one of url or source must be set.
    source: {
      data: arrayBufferOrBlob,          // ArrayBuffer | Blob | Uint8Array
      media: { "image1.png": blob },    // optional, pre-extracted media
    },
    permissions: { edit: false, download: true, print: true, copy: true },
  },
  editorConfig: {
    mode: "view",
    lang: "de-DE",
    user: { id: "u1", name: "Alice" },
    // NEW
    session: {
      type: "local",                    // "server" (default) | "local"
      x2tUrl: undefined,                // optional override, defaults to <ds>/x2t/
    },
    customization: { close: { visible: true } },
  },
  events: {
    onAppReady() {},
    onDocumentReady() {},
    onError(e) {},                      // { data: { errorCode, errorDescription } }
    onRequestClose() {},
    // NEW payload shape: blob is set in local mode, url in server mode
    onDownloadAs(e) {
      const { fileType, blob, url } = e.data;
    },
    // NEW: progress of local conversion, for a spinner
    onLocalSessionProgress(e) {},       // { data: { phase: "fonts"|"convert"|"load", percent } }
  },
});
```

Rules:

- `session.type === "local"` requires `document.source`; `document.url`,
  `editorConfig.callbackUrl` and `document.key` are ignored and a console warning is
  emitted if present.
- `token` (JWT) is still accepted. In local mode it is **not** validated by any server;
  integrators that use JWT for access control must enforce access before handing out
  the bytes.
- Formats supported in local mode are those linked into `x2t.wasm` (Track A decides
  the first set: docx, dotx, odt, rtf, txt, xlsx, xltx, ods, csv, pptx, potx, odp;
  PDF input is rendered by sdkjs directly without x2t).
- Errors: `onError` with new codes `-100` (x2t load failed), `-101` (conversion
  failed), `-102` (unsupported format in local mode), `-103` (memory limit).

Methods (existing names, local behaviour):

| Method | Local mode behaviour |
|---|---|
| `downloadAs(format)` | converts bin → `format` in the worker, fires `onDownloadAs` with `blob` |
| `destroyEditor()` | terminates the worker and revokes blob URLs |
| `requestClose()` | unchanged |
| `serviceCommand(...)`, `refreshHistory(...)`, `setHistoryData(...)` | no-op with console warning |

Phase 2 additions (editing, not in the first milestone):

```ts
editor.exportDocument({ format: "docx" }): Promise<Blob>   // current state as a file
editorConfig.session.transport?: LocalTransport            // collaboration plumbing
interface LocalTransport {
  send(message: object): void;          // editor → host
  onMessage(cb: (message: object) => void): void;  // host → editor
  close(): void;
}
```

The transport carries the same JSON messages the DocService uses (`auth`,
`saveChanges`, `getLock`, `cursor`, …). A host that wants collaboration relays them
between participants; `LocalSession` then stops answering them itself. This is what
makes a later Nextcloud-side collaboration layer possible without touching sdkjs
again.

### 3.2 Converter: standalone use

For integrators that only need conversion (thumbnails, format export):

```js
import { createConverter } from "https://ds.example.org/x2t/converter.js";
const x2t = await createConverter();          // loads x2t.wasm in a Worker
const { data, media } = await x2t.convert({
  data: bytes,
  fileName: "report.docx",
  to: "bin" | "docx" | "xlsx" | "pptx" | "pdf" | "odt" | "ods" | "odp",
  fonts: "auto",                                // fetch needed fonts from <ds>/fonts/
});
x2t.terminate();
```

Internally `convert` writes `/working/<file>`, `/working/params.xml`
(`TaskQueueDataConvert` with `m_sFileFrom`, `m_sFileTo`, `m_sThemeDir`, `m_sFontDir`,
optional `m_nFormatFrom`/`m_nFormatTo` from core's format table), calls `main1`, and
reads `/working/<file>.<to>` and `/working/media/*`. ODF inputs go through an OOXML
intermediate as in CryptPad.

### 3.3 Nextcloud: opening a source document

For Nextcloud apps (Mail, Talk, Deck, …) the connector exposes:

```js
// Preferred: let the Viewer pick the handler.
OCA.Viewer.openWith("eurooffice", {
  fileInfo: { source: url, basename: "report.docx", mime: "application/vnd…" },
});

// Direct, when not inside the Viewer:
OCA.Eurooffice.openSource({
  data: blob,                 // or url: string (fetched with credentials)
  name: "report.docx",
  mime: "application/vnd…",
  mode: "auto" | "local" | "server",
  container: HTMLElement,     // optional, defaults to a modal
});
```

Handler registration adds `supportsSource: true` so apps can feature-detect.

---

## 4. Milestones

| # | Milestone | Depends on | Acceptance |
|---|---|---|---|
| 0 | Spike: CryptPad x2t-wasm built, sizes and timings recorded, CryptPad editor zip opens a converted bin in a static page | – | numbers in this doc, go/no-go on thresholds |
| 1 | `core-wasm` produces `x2t.wasm`; node harness green against native x2t | 0 | CI job on `core-wasm` |
| 2 | sdkjs `MessageTransport` + hooks merged behind option | – | existing tests green; recorded-session test |
| 3 | web-apps `LocalSession`, `document.source`, capabilities flag | 1, 2 | example app page opens docx/xlsx/pptx from a file picker with no DocService running |
| 4 | DS image serves `/x2t/`, `info` reports `localSession` | 1, 3 | `develop/` container, `eo.sh` instance |
| 5 | Connector: source handler + local open path + E2E + settings | 3, 4 | E2E docx opens in Files with Document Server access logs showing no download |
| 6 | Mail: office attachments open in the viewer | 5 | mail#5988 and eurooffice-nextcloud#104 closed |
| 7 | Phase 2: `exportDocument`, save to DAV through E2E PUT interceptor | 5 | edits survive reload |
| 8 | Phase 3: transport-based collaboration | 7 | design doc first |

Rough effort for viewing (milestones 0–6): six to eight weeks with three people in
parallel. The critical path is Track A.

---

## 5. Risks and open questions

- **WASM size and memory.** Expect tens of MB uncompressed. Mitigations: brotli, long
  cache, lazy load only on local open, a Worker so the UI stays responsive, size
  thresholds falling back to server mode for non-E2E files. Needs the spike numbers.
- **Core patch maintenance.** Every core release must re-verify the emscripten build.
  CryptPad does this per tag; we should coordinate so one patch set serves both.
  Keeping patches behind `EO_WASM` in CMake makes rebases mechanical.
- **Bin format coupling.** `Editor.bin` is versioned; sdkjs and x2t must come from the
  same build. Serving both from the DS under the version-hashed path guarantees it.
- **Fonts and themes in the converter.** x2t needs font files for PDF export and
  themes for presentations. Fetching from `/fonts/` on demand works (CryptPad does it);
  check whether docx→bin needs any fonts at all, which affects first-open latency.
- **Feature gaps in local mode.** No server spellcheck (sdkjs has a WASM hunspell
  already), no image upload, no version history, no plugins that call the DS. All
  acceptable for viewing; document them in the API.
- **Access control.** The JWT is not enforced by anyone in local mode. The host must
  authorize before fetching bytes. State this prominently in the integrator docs.
- **Nextcloud 36 Viewer E2E awareness.** Verify how the Viewer decides which handlers
  may open encrypted nodes.
- **Licensing.** All inputs are AGPL-3.0; CryptPad's files carry
  `AGPL-3.0-or-later` headers. Preserve their attribution on ported files per our
  contribution policy.

## 6. Decisions requested from reviewers

1. Agree that the first milestone is view-only and local sessions force `mode: "view"`.
2. Agree to port x2t-wasm into our CMake pipeline rather than vendoring CryptPad's
   Dockerfile.
3. Agree on the API names above (`document.source`, `editorConfig.session`,
   `capabilities.localSession`, `onDownloadAs` with `blob`) before Track C starts, since
   integrators and CryptPad will build against them.
4. Decide whether the Mail server-side fallback (signed URL) is in or out of the first
   delivery. Proposal: out.
5. Who contacts CryptPad about upstreaming; their tests already run against our DS image.

## 7. Repositories and expected PRs

| Repo | Change |
|---|---|
| `core` | emscripten patches behind `EO_WASM`, x2t wasm CMake target, test harness |
| `DocumentServer` | `core-wasm` bake wiring, `develop/setup/Makefile` target, nginx `/x2t/`, docs |
| `sdkjs` | transport abstraction, image/convert/upload hooks |
| `web-apps` | `document.source`, `session`, `LocalSession` controller, Gateway channels, gated checks |
| `server` | `info` capability flag only |
| `document-server-package` | ship `/x2t/` |
| `eurooffice-nextcloud` | source abstraction, viewer `source` handler, local open path, settings, `openSource` API |
| `mail` | attachment mime filter and `openWith` |

Each PR is single-concern and lands behind the local-session option, so trunk stays
releasable throughout.

---

## 8. Implementation status (first pass, view-only)

Branches, one per repository, all pushed and opened as draft pull requests:

| Repo | Branch | State |
|---|---|---|
| `core` | `feat/x2t-wasm` | x2t WASM CMake target, converter JS, worker, node harness. **Not compiled yet**: no emsdk in the authoring environment; a new `build-x2t-wasm` CI job (`continue-on-error`) attempts it on PRs. |
| `sdkjs` | `feat/local-session-transport` | transport registry + socket adapter, local `convert`/`uploadImages` routing. 9 QUnit tests, full build green. |
| `web-apps` | `feat/local-session` | `document.source`, `editorConfig.session`, `capabilities.localSession`, `LocalSession` util + controller wired in all four editors. Mocha: 38 passing. Verified against the real sdkjs adapter in a browser page. |
| `DocumentServer` | `feat/x2t-wasm-serving` | bundle copies `x2t/` from the core-wasm stage; `make core/wasm/x2t` in the develop container; docs. Only `bake --print` validated. |
| `eurooffice-nextcloud` | `feat/client-only-viewer` | `GET /api/v1/config/local`, `GET /local` page, admin settings, viewer handler with `source` support, `OCA.Eurooffice.openSource`. PHPUnit for the new controller code. |
| `mail` | `feat/office-attachments-viewer` | office attachments open through a handler advertising `supportsSource`. 6 vitest cases. |

Deviations from the plan above, decided during implementation:

- **`EO_WASM_X2T` defaults to OFF in core.** CryptPad's core snapshot builds with the qmake
  `.pro` files, which are dead in our tree (in-tree zlib removed). The converter graph has
  never been linked with Emscripten through our CMake path, so switching it on by default
  would break the existing `build-wasm` CI for the sdkjs modules until it links. Expected
  first-CI issues are listed in `X2tConverter/build/wasm/README.md`.
- **CryptPad's doctrenderer "empty" stubs were not ported.** They derive from an older
  `doctrenderer.cpp` and do not compile against our headers; a 70-line stub implementing
  exactly the API x2t references replaces them. Ported with attribution: `main.cpp`
  (`proclimits`), `pdf_image.h` (`pdf.bin` from the working dir), `html.h` (FB2 behind
  `X2T_NO_FB2`), `wasm_main.cpp`, `pre.js`.
- **First linked format set:** docx/dotx/docm/doc/odt/rtf/txt/html/epub,
  xlsx/xltx/xlsm/xls/ods/csv, pptx/potx/pptm/ppt/odp. PDF output only from the editor's
  `pdf.bin`. Not linked: PDF/XPS/DjVu/OFD input (sdkjs renders PDF itself), iWork, HWP, FB2.
- **No sdkjs image hook was needed.** Listing extracted media as `media/<name>` in the
  `documentOpen` url map is enough for `g_oDocumentUrls`; CryptPad's `GlobalLoaders` patch
  is unnecessary.
- **Converter request carries both `format` (extension) and `fileType` (numeric)**; the
  reply may include `filetype`. The adapter's `close()` moves DocsCoApi to `ClosedAll`
  itself, so the web-apps session only releases resources.
- **Presenter mode is hidden in local sessions** (the reporter window still expects a DS).
- **Connector:** the server-side document-source refactor is deferred (only needed for a
  Mail server-mode fallback). The `/x2t/` nginx location lives in
  `document-server-package` and is still to be added there.
- **Not wired:** Visio editor, forms app, mobile editor, image upload in local mode.

Still unverified end to end: a real document opened in a browser through the full chain
(needs the compiled `x2t.wasm` from CI and a Nextcloud with the Viewer).
