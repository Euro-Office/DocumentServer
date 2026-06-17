<!--
SPDX-FileCopyrightText: 2026 Euro-Office contributors
SPDX-License-Identifier: AGPL
-->

# How Nextcloud and Euro-Office Work Together

This document explains how a Nextcloud Server operates together with the
Euro-Office Document Server to enable real-time document collaboration: what
happens in the background, what travels across the network, and how the two
systems are secured and deployed.

It is written in two layers:

- **Part 1 — Overview** for decision-makers.
- **Part 2 — Technical detail** for IT and network teams.

---

## Part 1 — Overview

**The short version.** Nextcloud stores the files. Euro-Office (the "Document
Server") is a separate service that does the actual document rendering and
editing. The **Euro-Office app for Nextcloud** is a connector that wires the two
together so that when a user clicks a `.docx`, `.xlsx`, or `.pptx` in Nextcloud,
it opens in a full office editor inside the browser — and multiple people can
edit the same file at the same time.

Three parts are involved:

| Component | Role | Where it runs |
|---|---|---|
| **Nextcloud Server** | Stores files, manages users, permissions, sharing | Customer's infrastructure |
| **Euro-Office Document Server** | Renders and edits documents; coordinates co-editing | Customer's infrastructure (separate host/container) |
| **Euro-Office Nextcloud app** (connector) | Glue between the two; runs inside Nextcloud | Inside Nextcloud |

What this means for the customer:

- **Everything stays on their infrastructure.** Both Nextcloud and the Document
  Server are self-hosted. No document content is sent to Euro-Office,
  ONLYOFFICE, or any third party during editing. There are **no outbound calls
  to any cloud service** in the editing path.
- **The browser is a thin client.** The editing software (JavaScript) is
  delivered from the Document Server to the user's browser. The browser never
  talks directly to Nextcloud's storage for the editing session — it talks to
  the Document Server.
- **Files only move between two trusted servers.** When a document is opened,
  the Document Server fetches it from Nextcloud; when editing finishes, the
  Document Server pushes the saved version back to Nextcloud. Both directions
  are authenticated.
- **Real-time collaboration is genuine co-editing**, not file-locking. Several
  users edit simultaneously and see each other's changes live, similar to
  Google Docs or Microsoft 365 — but on the customer's own servers.

---

## Part 2 — Technical detail

### 2.1 Network & data flow

There are **two distinct communication channels**, and this is the single most
important thing to understand for firewall planning.

**Channel A — Browser ↔ Document Server (the editing session)**

- The user's browser loads the editor's JavaScript API
  (`/web-apps/apps/api/documents/api.js`) directly from the Document Server.
- The live editing session runs over a **persistent WebSocket** connection from
  the browser to the Document Server's `DocService`. All keystrokes, cursor
  positions, and document operations flow over this socket in real time.
- This means **the browser must be able to reach the Document Server's public
  URL** (the `DocumentServerUrl` configured in Nextcloud).

**Channel B — Document Server ↔ Nextcloud (server-to-server)**

- **Load (inbox):** When a document is opened, the Document Server downloads the
  original file from a temporary, signed Nextcloud download URL.
- **Save (outbox/callback):** While editing and when the last user closes the
  document, the Document Server POSTs the updated file back to a Nextcloud
  **callback URL**. Nextcloud verifies it and writes the new version to storage.
- The connector also calls the Document Server directly for **conversions**
  (`/converter`) and **commands** (`/coauthoring/CommandService.ashx`), e.g.
  format conversion and version info.

The network requirement is therefore **bidirectional reachability**:

```
                    ┌─────────────────────────────────────────┐
                    │                Browser                    │
                    │  (loads editor JS, holds WebSocket)       │
                    └───────▲───────────────────────┬───────────┘
                            │ HTTPS + WSS           │ HTTPS
            loads UI from   │  (Channel A)          │ normal Nextcloud
            Document Server │                       │ web/login
                            │                       ▼
        ┌───────────────────┴────────┐     ┌──────────────────────┐
        │  Euro-Office Doc Server     │     │   Nextcloud Server    │
        │  (DocService, Converter)    │◄───►│  + Euro-Office app    │
        └─────────────────────────────┘     └──────────────────────┘
              ▲          Channel B (server-to-server, signed JWT)
              │   • Doc Server downloads original file from Nextcloud (inbox)
              │   • Doc Server POSTs saved file to Nextcloud callback (outbox)
              │   • Nextcloud calls /converter, /CommandService, /healthcheck
              └────────────────────────────────────────────────────────────
```

**Endpoints on the Document Server** (behind its nginx reverse proxy):

| Path | Purpose |
|---|---|
| `/web-apps/apps/api/documents/api.js` | Editor JavaScript API loaded by the browser |
| `/healthcheck` | Readiness probe (returns `true`); used by the connector's daily availability check |
| `/coauthoring/...` (WebSocket) | Real-time co-editing session transport |
| `/coauthoring/CommandService.ashx` | Command service (version info, force-save, etc.) |
| `/converter` | Document format conversion service |

**Internally**, the Document Server is a set of microservices fronted by nginx:

| Service | Default internal port | Role |
|---|---|---|
| **DocService** | 8000 | Co-editing WebSocket, client API, session coordination |
| **FileConverter** | internal | Format conversion (the `x2t` engine) |
| **Metrics** | 8125 (StatsD) | Optional metrics (off by default) |
| **AdminPanel** | 9000 | Optional admin console (off by default) |

nginx exposes everything on one public port (**80/443**; the development image
maps host **8080 → container 80**). Backing stores — **PostgreSQL (5432)**,
**Redis (6379)**, **RabbitMQ/AMQP (5672)** — hold session and co-editing state.
In the all-in-one image these run inside the container and need no external
exposure.

> Note: the exact internal port numbers and the `/coauthoring` WebSocket path
> are implementation details of the bundled image and can vary by deployment;
> the customer only needs to expose the single nginx front-end port.

### 2.2 Security & sovereignty

- **JWT signing on every request.** All traffic between Nextcloud and the
  Document Server is signed with a shared secret (HS256 JWT). Both sides must be
  configured with the **same secret** (`JWT_SECRET` on the Document Server; the
  *Secret key* in the Nextcloud app, stored as the `jwt_secret` app config). JWT
  has been **enabled by default since v7.2**; unsigned requests are rejected
  with HTTP 403.
- **Three independent token scopes** can be secured (and even given separate
  secrets for rotation):
  - **Browser** — client-to-server editing session
  - **Inbox** — Nextcloud → Document Server load requests
  - **Outbox** — Document Server → Nextcloud save callbacks

  Controlled by
  `services.CoAuthoring.token.enable.{browser,request.inbox,request.outbox}` /
  env vars `JWT_ENABLED[_INBOX|_OUTBOX]`, with optional separate
  `JWT_SECRET_INBOX` / `JWT_SECRET_OUTBOX`.
- **Token delivery** defaults to the `Authorization` HTTP header (configurable;
  can also be placed in the request body for the conversion service).
- **Transport:** HTTPS/WSS end-to-end in production. The Document Server
  supports TLS directly (`SSL_CERTIFICATE_PATH` / `SSL_KEY_PATH`) with **HSTS on
  by default (1 year)**, or it can sit behind the customer's own reverse proxy.
- **Self-signed certificates:** if internal CAs are used, there are explicit
  knobs — "Disable certificate verification" in the Nextcloud app or
  `'verify_peer_off' => true` in `config.php`. Using a real CA-issued
  certificate in production is recommended.
- **Data residency / sovereignty:** documents are only ever stored in
  **Nextcloud's storage**. The Document Server keeps **transient** working
  copies in a local cache (`App_Data/cache`) and session state in
  Redis/RabbitMQ for the duration of co-editing; these are not permanent
  document stores. Nothing leaves the two servers. This is the core sovereignty
  property — full self-hosting, no third-party processing.
- **Availability safeguard:** the connector runs a daily background job hitting
  `/healthcheck`; if the Document Server is unreachable it disables the editor
  rather than failing silently.

### 2.3 Real-time co-editing internals

1. A user opens a document in Nextcloud. The connector (`EditorController` /
   `editor.php` template) builds a **signed JSON config** containing the
   document's signed download URL, a unique document key, the user identity,
   permissions, and the callback URL.
2. The browser loads the editor JS from the Document Server and hands it that
   config.
3. The Document Server validates the JWT, **downloads the original file** from
   Nextcloud (inbox), converts it to its internal format if needed, and opens
   the editing session.
4. The browser joins the session over **WebSocket**. `DocService` is the
   authority for document state; concurrent edits are merged and broadcast to
   all connected clients. Session state is held in Redis, with RabbitMQ
   coordinating async work.
5. **Two co-editing modes** (set by the connector, exposed in the Nextcloud
   app):
   - **Fast** (default) — changes are shared in real time as you type; all
     co-authors see edits immediately.
   - **Strict** — changes are buffered and only published when the user
     explicitly saves, giving paragraph/cell-level locking. Useful when users
     prefer to review before sharing.

   Also available: track changes, comments, and built-in chat.
6. **Saving:** the Document Server sends **callbacks** to Nextcloud carrying a
   status code:

   | Status | Meaning | Connector action |
   |---|---|---|
   | 1 | Editing (user joined) | Lock the file |
   | 2 | Ready to save (last user left) | Download edited file → write new version |
   | 3 | Save error / corrupted | Log error, don't overwrite |
   | 4 | Closed with no changes | Unlock |
   | 6 | Force-save (e.g. periodic / explicit) | Save current state, keep editing |
   | 7 | Force-save error | Log error |

   On a save status the connector downloads the new file from the URL in the
   callback, acquires a Nextcloud lock, writes it, and optionally records a
   version and author metadata. It returns `{"error": 0}` on success.

   Because the file is only written back to storage when the **last** editor
   leaves (or on force-save), parallel editing is collision-free. The app
   additionally recommends Nextcloud's *Temporary File Lock* app to prevent a
   second, non-Euro-Office process editing the same file.

### 2.4 Deployment topology

- **Separate hosts.** Nextcloud and the Document Server should be deployed as
  distinct services (separate VMs/containers). The Document Server ships as a
  Docker image (`ghcr.io/euro-office/documentserver`) bundling nginx,
  PostgreSQL, Redis and RabbitMQ, or as deb/rpm packages.
- **The `DocumentServerUrl` is the external address** the *browser* uses, set in
  Nextcloud via the admin UI, `occ config:app:set eurooffice DocumentServerUrl`,
  or `config.php`.
- **Split-horizon / internal URL.** When the public URL isn't reachable
  server-to-server (NAT, segmented networks), the app's *Advanced server
  settings* let you set a **separate internal address** for the Document
  Server ↔ Nextcloud channel while the browser keeps using the external one.
  Likewise an internal Nextcloud "Server address for internal requests" can be
  set for the callback path.
- **Private-IP callbacks.** If Nextcloud is on a private/RFC1918 address, the
  Document Server must be allowed to call it. In the development compose this is
  `ALLOW_PRIVATE_IP_ADDRESS=true`; production deployments behind a proxy
  typically expose Nextcloud on a routable internal hostname instead.
  Nextcloud's `trusted_domains` must include whatever host the editor/clients
  use.
- **Reverse proxy.** A single proxy in front of the Document Server terminating
  TLS and forwarding `/` (HTTP + WebSocket upgrade) to nginx is the standard
  production setup. WebSocket upgrade headers must be passed through.
- **Scaling:** the architecture (a largely stateless DocService backed by shared
  Redis/RabbitMQ/Postgres) supports horizontal scaling of the Document Server
  tier for larger deployments.

### 2.5 Firewall / connectivity checklist

- [ ] Browser → Document Server public URL: **HTTPS + WebSocket (WSS)** on 443
- [ ] Browser → Nextcloud: normal HTTPS (443)
- [ ] Document Server → Nextcloud (download + callback): HTTPS, reachable host
      (use internal URL if needed)
- [ ] Nextcloud → Document Server (`/healthcheck`, `/converter`,
      `/CommandService`): HTTPS
- [ ] Same **JWT secret** configured on both sides
- [ ] Valid TLS certificates (or documented `verify_peer_off` exception for
      internal CAs)
- [ ] Nextcloud `trusted_domains` includes the client-facing host
- [ ] WebSocket upgrade allowed through any reverse proxy

---

## Supported formats

- **Viewing:** DOCX, ODT, PDF, RTF, TXT, EPUB and many legacy word-processing
  formats; XLSX, ODS, CSV, XLS and variants; PPTX, ODP, POTX and variants;
  diagram formats such as VSDX.
- **Editing:** DOCX/DOCM, XLSX/XLSM, PPTX/PPSM variants, and PDF (including
  forms).

## Notes on sourcing

This document is based on the current Euro-Office `DocumentServer` codebase
(services, JWT configuration, nginx/ports, callback flow) and the
`eurooffice-nextcloud` connector app (callback handling, document-server
communication, supported formats, co-editing modes, internal/external URL
configuration). Euro-Office is an ONLYOFFICE-derived engine, so the integration
protocol matches the well-documented model ONLYOFFICE uses, which can be used
for cross-reference.
