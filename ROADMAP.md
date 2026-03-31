<!--
SPDX-FileCopyrightText: 2026 Euro-Office contributors
SPDX-License-Identifier: CC0-1.0
-->

# Euro-Office Integration Roadmap

> This roadmap covers the integration of Euro-Office DocumentServer with external platforms (OpenCloud, SOGo, Open-Xchange, Zimbra) via WOPI and Docs API protocols.
>
> Full integration planning document: [.github/INTEGRATION-PLANNING.md](https://github.com/Euro-Office/DocumentServer/blob/main/.github/INTEGRATION-PLANNING.md)

## Role in Integration

This is the **integration orchestration repo** — it assembles all component repos (server, sdkjs, web-apps, core) into a deployable DocumentServer. It also contains the top-level integration planning, Dockerfiles, and build scripts.

## Roadmap Items

### Phase 1 — Foundation

- [ ] Verify end-to-end WOPI flow works through the assembled DocumentServer
- [ ] Validate Docker image works correctly for platform integrations
- [ ] Test JWT secret exchange configuration between DocumentServer and host platforms

### Phase 2 — OpenCloud Integration (P1)

- [ ] Test full OpenCloud ↔ DocumentServer integration via the eurooffice-nextcloud connector

### Phase 3 — Zimbra Integration (P1)

- [ ] Test Euro-Office DocumentServer as a drop-in replacement for Zimbra's `zm-onlyoffice`
- [ ] Document migration path from `zm-onlyoffice` to Euro-Office

### Phase 4 — Open-Xchange Integration (P2)

- [ ] Test DocumentServer with OX App Suite's WOPI integration

### Phase 5 — SOGo Integration (P2)

- [ ] Test DocumentServer as WOPI server for a SOGo WOPI client module

### Shared Requirements (this repo)

- [ ] **Docker image** — Containerized deployment alongside host platforms
- [ ] **Helm chart** — Kubernetes deployment for OpenCloud and Open-Xchange
- [ ] **Environment variable configuration** — WOPI enable, JWT secret, allowed origins

---

## Cross-Repo References

| Repo | Role |
|------|------|
| [server](https://github.com/Euro-Office/server) | WOPI endpoints, discovery, proof keys, JWT, admin panel |
| [sdkjs](https://github.com/Euro-Office/sdkjs) | Docs API, editor engine, co-editing, format conversion |
| [web-apps](https://github.com/Euro-Office/web-apps) | Editor UI, toolbar, plugins, branding |
| [core](https://github.com/Euro-Office/core) | File format conversion engine (OOXML, ODF, PDF) |
| [eurooffice-nextcloud](https://github.com/Euro-Office/eurooffice-nextcloud) | OpenCloud/Nextcloud WOPI connector |
| [DocumentServer](https://github.com/Euro-Office/DocumentServer) | Integration orchestration, Docker, Helm |
| [document-server-integration](https://github.com/Euro-Office/document-server-integration) | Integration examples & API docs |
| [document-server-package](https://github.com/Euro-Office/document-server-package) | DEB/RPM/Helm packaging |
| [docker-ci](https://github.com/Euro-Office/docker-ci) | Docker images for deployment |
| [desktop-sdk](https://github.com/Euro-Office/desktop-sdk) | Desktop CEF integration |
| [desktop-apps](https://github.com/Euro-Office/desktop-apps) | Desktop packaging & Electron wrappers |

## Protocol Documentation

- [WOPI Protocol Overview — Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-365/cloud-storage-partner-program/online/)
- [WOPI Overview — ONLYOFFICE API](https://api.onlyoffice.com/docs/docs-api/using-wopi/overview/)
- [WOPI REST API — ONLYOFFICE API](https://api.onlyoffice.com/docs/docs-api/using-wopi/wopi-rest-api/)
- [WOPI Discovery — ONLYOFFICE API](https://api.onlyoffice.com/docs/docs-api/using-wopi/wopi-discovery/)
- [Docs API Basic Concepts — ONLYOFFICE API](https://api.onlyoffice.com/docs/docs-api/get-started/basic-concepts/)
