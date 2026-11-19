# Changelog

## v9.3.8

### Features

* DocumentServer: e2e: add eslint, prettier and make.sh tooling for frontend tests by bhumigopaniStarto in [DocumentServer#462](https://github.com/Euro-Office/DocumentServer/pull/462)
* DocumentServer: docker: ship DB schema in cluster-utils image under /scripts/schema by meisam-ui in [DocumentServer#484](https://github.com/Euro-Office/DocumentServer/pull/484)
* server: logger: report errors to Sentry when SENTRY_DSN is set by juliusknorr in [server#49](https://github.com/Euro-Office/server/pull/49)
* server: logger: tag errors with integrator referenceData by juliusknorr in [server#59](https://github.com/Euro-Office/server/pull/59)
* web-apps: documenteditor: show selection counts in the word count popup by martivilella in [web-apps#289](https://github.com/Euro-Office/web-apps/pull/289)
* sdkjs: word: add selection statistics API by martivilella in [sdkjs#98](https://github.com/Euro-Office/sdkjs/pull/98)
* core: Android build by rikled in [core#182](https://github.com/Euro-Office/core/pull/182)
* core: Move the third-party remote cache to S3 (eo-build-assets) by rikled in [core#178](https://github.com/Euro-Office/core/pull/178)
* document-server-package: nginx: add a Content-Security-Policy to the editor documents by chrip in [document-server-package#16](https://github.com/Euro-Office/document-server-package/pull/16)

### Bug fixes

* DocumentServer: docker: bind-mount packages instead of copying them by karlivory in [DocumentServer#451](https://github.com/Euro-Office/DocumentServer/pull/451)
* DocumentServer: docker: refresh OS packages on every daily build by juliusknorr in [DocumentServer#475](https://github.com/Euro-Office/DocumentServer/pull/475)
* DocumentServer: docker: add clang/llvm/lld and unzip to the develop image by robintel in [DocumentServer#443](https://github.com/Euro-Office/DocumentServer/pull/443)
* DocumentServer: normalize boolean input in entrypoint scripts by rikled in [DocumentServer#391](https://github.com/Euro-Office/DocumentServer/pull/391)
* DocumentServer: orchestrated: drop the chmod on FileConverter/bin in the font init by chrip in [DocumentServer#502](https://github.com/Euro-Office/DocumentServer/pull/502)
* server: server: clean up runtime config watcher on shutdown by nvanlaerebeke in [server#52](https://github.com/Euro-Office/server/pull/52)
* server: credit Google for the Material Symbols icons by juliusknorr in [server#67](https://github.com/Euro-Office/server/pull/67)
* server: branding: point installation instructions link at Euro-Office docs by NotAFlightRisk in [server#70](https://github.com/Euro-Office/server/pull/70)
* web-apps: l10n: a quality review of the Danish translation across all editors by bargib in [web-apps#329](https://github.com/Euro-Office/web-apps/pull/329)
* web-apps: mobile: don't crash in uk/pl locales due to undefined license warning translation by nykula in [web-apps#185](https://github.com/Euro-Office/web-apps/pull/185)
* web-apps: de: show the icons in the wrapping style and page number pickers by bargib in [web-apps#320](https://github.com/Euro-Office/web-apps/pull/320)
* web-apps: tips: drop the "Learn more" links to the ONLYOFFICE blog by bargib in [web-apps#354](https://github.com/Euro-Office/web-apps/pull/354)
* web-apps: l10n: fix typo in Danish track changes menu by bargib in [web-apps#361](https://github.com/Euro-Office/web-apps/pull/361)
* web-apps: Adding missing suggest_url to config.json by Aiiaiiio in [web-apps#365](https://github.com/Euro-Office/web-apps/pull/365)
* web-apps: header: use header icon colour for symbols on light themes by rikled in [web-apps#366](https://github.com/Euro-Office/web-apps/pull/366)
* sdkjs: use the standard wheel event in all editors (restores PDF scrolling in Chromium) by chrip in [sdkjs#110](https://github.com/Euro-Office/sdkjs/pull/110)
* sdkjs: word: skip unused built-in table styles equal to the defaults on save by delmarguillen in [sdkjs#112](https://github.com/Euro-Office/sdkjs/pull/112)
* core: Build amd64 desktop on Rocky Linux 9 (fixes Euro-Office/DesktopEditors#122) by rikled in [core#165](https://github.com/Euro-Office/core/pull/165)
* core: make zlib a 3rdparty dep by Aiiaiiio in [core#183](https://github.com/Euro-Office/core/pull/183)
* core: boost: name the MSVC toolset for bootstrap on Visual Studio 2026 by rikled in [core#185](https://github.com/Euro-Office/core/pull/185)
* core: minizip: disable libbsd for the WASM build by rikled in [core#188](https://github.com/Euro-Office/core/pull/188)
* core: Fixing minizip-ng build for macOS by Aiiaiiio in [core#192](https://github.com/Euro-Office/core/pull/192)
* core: libxml2 update by Aiiaiiio in [core#193](https://github.com/Euro-Office/core/pull/193)
* core: test: pass narrow UTF-8 paths to X2T_Convert in OOXML/test by robintel in [core#166](https://github.com/Euro-Office/core/pull/166)
* core: csv: drop empty row added for UTF-8 files ending with a line break by robintel in [core#170](https://github.com/Euro-Office/core/pull/170)
* core: xlsx: preserve pivot cache records on XLSB to XLSX conversion by robintel in [core#169](https://github.com/Euro-Office/core/pull/169)
* core: vsdx: Fix detection extension for empty vsdx by coffeemakr in [core#197](https://github.com/Euro-Office/core/pull/197)
* core: officeutils: restore compatible ZIP headers for saved documents by rikled in [core#289](https://github.com/Euro-Office/core/pull/289)
* document-server-integration: credit Google for the Material Symbols icons by juliusknorr in [document-server-integration#19](https://github.com/Euro-Office/document-server-integration/pull/19)
* document-server-integration: docker: normalize JWT_ENABLED in example entrypoint by rikled in [document-server-integration#21](https://github.com/Euro-Office/document-server-integration/pull/21)
* document-server-package: rpm: make msttcore-fonts-installer optional by juliusknorr in [document-server-package#19](https://github.com/Euro-Office/document-server-package/pull/19)
* document-server-package: package: declare AGPL, CC BY-SA and third-party licences per file class by juliusknorr in [document-server-package#21](https://github.com/Euro-Office/document-server-package/pull/21)
* document-server-package: packaging: let root own what the root scripts execute by chrip in [document-server-package#24](https://github.com/Euro-Office/document-server-package/pull/24)

### Performance

* web-apps: help: replace GIFs with WebM/MP4 and recompress PNGs by juliusknorr in [web-apps#352](https://github.com/Euro-Office/web-apps/pull/352)
* sdkjs: word: ⚡ check for table cell content before IsUseInDocument in section updates by moodyjmz in [sdkjs#123](https://github.com/Euro-Office/sdkjs/pull/123)
* sdkjs: cell: index area listeners to speed up the circular-reference check by MonaAghili in [sdkjs#119](https://github.com/Euro-Office/sdkjs/pull/119)
* document-server-package: package: hardlink duplicate web-apps files in deb and rpm by juliusknorr in [document-server-package#20](https://github.com/Euro-Office/document-server-package/pull/20)

### Other changes

* DocumentServer: ci: pass third-party cache credentials to the core build by juliusknorr in [DocumentServer#447](https://github.com/Euro-Office/DocumentServer/pull/447)
* DocumentServer: ci: reuse the registry build cache across commits by juliusknorr in [DocumentServer#446](https://github.com/Euro-Office/DocumentServer/pull/446)
* DocumentServer: ci: auto-approve and auto-merge non-major renovate updates by juliusknorr in [DocumentServer#454](https://github.com/Euro-Office/DocumentServer/pull/454)
* DocumentServer: chore(deps): update actions/download-artifact action to v8.0.2 by renovate[bot] in [DocumentServer#445](https://github.com/Euro-Office/DocumentServer/pull/445)
* DocumentServer: chore(deps): update actions/setup-node action to v6.5.0 by renovate[bot] in [DocumentServer#298](https://github.com/Euro-Office/DocumentServer/pull/298)
* DocumentServer: chore: update submodules to latest main branch by rikled in [DocumentServer#455](https://github.com/Euro-Office/DocumentServer/pull/455)
* DocumentServer: chore(deps): update docker/setup-buildx-action action to v4.4.1 by renovate[bot] in [DocumentServer#372](https://github.com/Euro-Office/DocumentServer/pull/372)
* DocumentServer: chore(deps): update zizmorcore/zizmor-action action to v0.7.1 by renovate[bot] in [DocumentServer#354](https://github.com/Euro-Office/DocumentServer/pull/354)
* DocumentServer: chore(deps): update actions/upload-artifact action to v7.0.2 by renovate[bot] in [DocumentServer#456](https://github.com/Euro-Office/DocumentServer/pull/456)
* DocumentServer: chore(deps): update dependency @playwright/test to v1.64.1 by renovate[bot] in [DocumentServer#340](https://github.com/Euro-Office/DocumentServer/pull/340)
* DocumentServer: chore(deps): update dependency @types/node to v22.20.5 by renovate[bot] in [DocumentServer#164](https://github.com/Euro-Office/DocumentServer/pull/164)
* DocumentServer: chore(deps): update dependency typescript to v7 by renovate[bot] in [DocumentServer#459](https://github.com/Euro-Office/DocumentServer/pull/459)
* DocumentServer: chore(deps): update actions/setup-node action to v7 by renovate[bot] in [DocumentServer#379](https://github.com/Euro-Office/DocumentServer/pull/379)
* DocumentServer: chore(deps): update zizmorcore/zizmor-action action to v0.8.0 by renovate[bot] in [DocumentServer#471](https://github.com/Euro-Office/DocumentServer/pull/471)
* DocumentServer: chore(deps): update actions/setup-node action to v7 by renovate[bot] in [DocumentServer#472](https://github.com/Euro-Office/DocumentServer/pull/472)
* DocumentServer: chore(deps): update docker/login-action action to v4.7.0 by renovate[bot] in [DocumentServer#457](https://github.com/Euro-Office/DocumentServer/pull/457)
* DocumentServer: chore(deps): update dependency node to v26 by renovate[bot] in [DocumentServer#477](https://github.com/Euro-Office/DocumentServer/pull/477)
* DocumentServer: ci(dev-images): reuse the main build cache and report cache hits by meisam-ui in [DocumentServer#463](https://github.com/Euro-Office/DocumentServer/pull/463)
* DocumentServer: chore(deps): update docker/bake-action action to v7.5.0 by renovate[bot] in [DocumentServer#460](https://github.com/Euro-Office/DocumentServer/pull/460)
* DocumentServer: ci: build vX.Y.Z-N tags as stable patch builds by juliusknorr in [DocumentServer#478](https://github.com/Euro-Office/DocumentServer/pull/478)
* DocumentServer: ci(update-submodules): authenticate the clones of private submodules by rikled in [DocumentServer#487](https://github.com/Euro-Office/DocumentServer/pull/487)
* DocumentServer: chore(deps): update dependency typescript-eslint to v8.72.1 by renovate[bot] in [DocumentServer#488](https://github.com/Euro-Office/DocumentServer/pull/488)
* DocumentServer: chore: update submodules to latest main branch by rikled in [DocumentServer#464](https://github.com/Euro-Office/DocumentServer/pull/464)
* DocumentServer: chore(deps): update dependency @types/node to v26.6.6 by renovate[bot] in [DocumentServer#495](https://github.com/Euro-Office/DocumentServer/pull/495)
* DocumentServer: build(docker): make BuildKit cache root configurable by nvanlaerebeke in [DocumentServer#403](https://github.com/Euro-Office/DocumentServer/pull/403)
* DocumentServer: build(docker): make BuildKit cache root configurable by meisam-ui in [DocumentServer#499](https://github.com/Euro-Office/DocumentServer/pull/499)
* DocumentServer: chore(deps): update dependency eslint to v10.14.0 by renovate[bot] in [DocumentServer#501](https://github.com/Euro-Office/DocumentServer/pull/501)
* DocumentServer: ci: split build and release, build only the e2e image on pull requests by juliusknorr in [DocumentServer#452](https://github.com/Euro-Office/DocumentServer/pull/452)
* DocumentServer: chore: update submodules to latest main branch by rikled in [DocumentServer#493](https://github.com/Euro-Office/DocumentServer/pull/493)
* DocumentServer: chore(release): v9.3.8-rc.1 by eo-robot in [DocumentServer#508](https://github.com/Euro-Office/DocumentServer/pull/508)
* server: ci: switch S3 storage tests to pgsty/minio by juliusknorr in [server#63](https://github.com/Euro-Office/server/pull/63)
* server: build: bump Node to 24 LTS by juliusknorr in [server#62](https://github.com/Euro-Office/server/pull/62)
* web-apps: i18n(fr): add the 40 missing French strings across all editors by SamsGuamejy in [web-apps#334](https://github.com/Euro-Office/web-apps/pull/334)
* web-apps: chore(deps): update github/codeql-action action to v4.39.1 by renovate[bot] in [web-apps#355](https://github.com/Euro-Office/web-apps/pull/355)
* web-apps: chore(deps): update actions/setup-python action to v7.1.0 by renovate[bot] in [web-apps#356](https://github.com/Euro-Office/web-apps/pull/356)
* web-apps: chore(deps): update dependency webpack to v5.112.1 by renovate[bot] in [web-apps#358](https://github.com/Euro-Office/web-apps/pull/358)
* web-apps: chore(deps): update dependency webpack to v5.112.2 by renovate[bot] in [web-apps#359](https://github.com/Euro-Office/web-apps/pull/359)
* web-apps: refactor(common): remove unused Switcher.setThumbPosition by juliusknorr in [web-apps#349](https://github.com/Euro-Office/web-apps/pull/349)
* web-apps: chore(deps): update dependency webpack-cli to v7.3.0 by renovate[bot] in [web-apps#373](https://github.com/Euro-Office/web-apps/pull/373)
* web-apps: chore(deps): update dependency webpack-cli to v7.3.1 by renovate[bot] in [web-apps#374](https://github.com/Euro-Office/web-apps/pull/374)
* sdkjs: build: sdkjs for the mobile editors' engine by rikled in [sdkjs#121](https://github.com/Euro-Office/sdkjs/pull/121)
* sdkjs: ci: auto-approve and auto-merge non-major renovate updates by juliusknorr in [sdkjs#118](https://github.com/Euro-Office/sdkjs/pull/118)
* sdkjs: chore(deps): pin dependencies by renovate[bot] in [sdkjs#129](https://github.com/Euro-Office/sdkjs/pull/129)
* sdkjs: chore(deps): update actions/upload-artifact action to v7 by renovate[bot] in [sdkjs#102](https://github.com/Euro-Office/sdkjs/pull/102)
* core: ci: mount third-party cache credentials in the core stage by juliusknorr in [core#177](https://github.com/Euro-Office/core/pull/177)
* core: fix(deps): bump brotli to v1.2.1 by juliusknorr in [core#184](https://github.com/Euro-Office/core/pull/184)
* core: test(odf): verify the TestEnv conversion produces a valid package by robintel in [core#167](https://github.com/Euro-Office/core/pull/167)
* core: test(rtf): add unit suite for the RTF lexer by robintel in [core#174](https://github.com/Euro-Office/core/pull/174)
* core: ci: cancel superseded pull request builds by juliusknorr in [core#195](https://github.com/Euro-Office/core/pull/195)
* core: ci: pull core-base from docker-ci, build it only when missing by juliusknorr in [core#201](https://github.com/Euro-Office/core/pull/201)
* core: ci: run macOS jobs on macos-15 by juliusknorr in [core#200](https://github.com/Euro-Office/core/pull/200)
* document-server-integration: fix(deps): build the nodejs example with Node 26 by juliusknorr in [document-server-integration#20](https://github.com/Euro-Office/document-server-integration/pull/20)

### Compare to v9.3.7-1

* DocumentServer: <https://github.com/Euro-Office/DocumentServer/compare/6ba1e1318785...8478a02af143>
* server: <https://github.com/Euro-Office/server/compare/a924935680de...2e7a2a131061>
* web-apps: <https://github.com/Euro-Office/web-apps/compare/ce0ba4954581...f8d4506c130d>
* sdkjs: <https://github.com/Euro-Office/sdkjs/compare/40d9b7780f11...a1b8cac5d1bc>
* core: <https://github.com/Euro-Office/core/compare/afb3f233704b...749cc177d520>
* document-server-integration: <https://github.com/Euro-Office/document-server-integration/compare/d88f09562d0f...aedcb528d5f7>
* document-server-package: <https://github.com/Euro-Office/document-server-package/compare/c695b1b421ee...7be57e6f967d>

## v9.3.8-rc.1

### Features

* DocumentServer: e2e: add eslint, prettier and make.sh tooling for frontend tests by bhumigopaniStarto in [DocumentServer#462](https://github.com/Euro-Office/DocumentServer/pull/462)
* DocumentServer: docker: ship DB schema in cluster-utils image under /scripts/schema by meisam-ui in [DocumentServer#484](https://github.com/Euro-Office/DocumentServer/pull/484)
* server: logger: report errors to Sentry when SENTRY_DSN is set by juliusknorr in [server#49](https://github.com/Euro-Office/server/pull/49)
* server: logger: tag errors with integrator referenceData by juliusknorr in [server#59](https://github.com/Euro-Office/server/pull/59)
* web-apps: documenteditor: show selection counts in the word count popup by martivilella in [web-apps#289](https://github.com/Euro-Office/web-apps/pull/289)
* sdkjs: word: add selection statistics API by martivilella in [sdkjs#98](https://github.com/Euro-Office/sdkjs/pull/98)
* core: Android build by rikled in [core#182](https://github.com/Euro-Office/core/pull/182)
* core: Move the third-party remote cache to S3 (eo-build-assets) by rikled in [core#178](https://github.com/Euro-Office/core/pull/178)
* document-server-package: nginx: add a Content-Security-Policy to the editor documents by chrip in [document-server-package#16](https://github.com/Euro-Office/document-server-package/pull/16)

### Bug fixes

* DocumentServer: docker: bind-mount packages instead of copying them by karlivory in [DocumentServer#451](https://github.com/Euro-Office/DocumentServer/pull/451)
* DocumentServer: docker: refresh OS packages on every daily build by juliusknorr in [DocumentServer#475](https://github.com/Euro-Office/DocumentServer/pull/475)
* DocumentServer: docker: add clang/llvm/lld and unzip to the develop image by robintel in [DocumentServer#443](https://github.com/Euro-Office/DocumentServer/pull/443)
* DocumentServer: normalize boolean input in entrypoint scripts by rikled in [DocumentServer#391](https://github.com/Euro-Office/DocumentServer/pull/391)
* DocumentServer: orchestrated: drop the chmod on FileConverter/bin in the font init by chrip in [DocumentServer#502](https://github.com/Euro-Office/DocumentServer/pull/502)
* server: server: clean up runtime config watcher on shutdown by nvanlaerebeke in [server#52](https://github.com/Euro-Office/server/pull/52)
* server: credit Google for the Material Symbols icons by juliusknorr in [server#67](https://github.com/Euro-Office/server/pull/67)
* server: branding: point installation instructions link at Euro-Office docs by NotAFlightRisk in [server#70](https://github.com/Euro-Office/server/pull/70)
* web-apps: l10n: a quality review of the Danish translation across all editors by bargib in [web-apps#329](https://github.com/Euro-Office/web-apps/pull/329)
* web-apps: mobile: don't crash in uk/pl locales due to undefined license warning translation by nykula in [web-apps#185](https://github.com/Euro-Office/web-apps/pull/185)
* web-apps: de: show the icons in the wrapping style and page number pickers by bargib in [web-apps#320](https://github.com/Euro-Office/web-apps/pull/320)
* web-apps: tips: drop the "Learn more" links to the ONLYOFFICE blog by bargib in [web-apps#354](https://github.com/Euro-Office/web-apps/pull/354)
* web-apps: l10n: fix typo in Danish track changes menu by bargib in [web-apps#361](https://github.com/Euro-Office/web-apps/pull/361)
* web-apps: Adding missing suggest_url to config.json by Aiiaiiio in [web-apps#365](https://github.com/Euro-Office/web-apps/pull/365)
* web-apps: header: use header icon colour for symbols on light themes by rikled in [web-apps#366](https://github.com/Euro-Office/web-apps/pull/366)
* sdkjs: use the standard wheel event in all editors (restores PDF scrolling in Chromium) by chrip in [sdkjs#110](https://github.com/Euro-Office/sdkjs/pull/110)
* sdkjs: word: skip unused built-in table styles equal to the defaults on save by delmarguillen in [sdkjs#112](https://github.com/Euro-Office/sdkjs/pull/112)
* core: Build amd64 desktop on Rocky Linux 9 (fixes Euro-Office/DesktopEditors#122) by rikled in [core#165](https://github.com/Euro-Office/core/pull/165)
* core: make zlib a 3rdparty dep by Aiiaiiio in [core#183](https://github.com/Euro-Office/core/pull/183)
* core: boost: name the MSVC toolset for bootstrap on Visual Studio 2026 by rikled in [core#185](https://github.com/Euro-Office/core/pull/185)
* core: minizip: disable libbsd for the WASM build by rikled in [core#188](https://github.com/Euro-Office/core/pull/188)
* core: Fixing minizip-ng build for macOS by Aiiaiiio in [core#192](https://github.com/Euro-Office/core/pull/192)
* core: libxml2 update by Aiiaiiio in [core#193](https://github.com/Euro-Office/core/pull/193)
* core: test: pass narrow UTF-8 paths to X2T_Convert in OOXML/test by robintel in [core#166](https://github.com/Euro-Office/core/pull/166)
* core: csv: drop empty row added for UTF-8 files ending with a line break by robintel in [core#170](https://github.com/Euro-Office/core/pull/170)
* core: xlsx: preserve pivot cache records on XLSB to XLSX conversion by robintel in [core#169](https://github.com/Euro-Office/core/pull/169)
* core: vsdx: Fix detection extension for empty vsdx by coffeemakr in [core#197](https://github.com/Euro-Office/core/pull/197)
* document-server-integration: credit Google for the Material Symbols icons by juliusknorr in [document-server-integration#19](https://github.com/Euro-Office/document-server-integration/pull/19)
* document-server-integration: docker: normalize JWT_ENABLED in example entrypoint by rikled in [document-server-integration#21](https://github.com/Euro-Office/document-server-integration/pull/21)
* document-server-package: rpm: make msttcore-fonts-installer optional by juliusknorr in [document-server-package#19](https://github.com/Euro-Office/document-server-package/pull/19)
* document-server-package: package: declare AGPL, CC BY-SA and third-party licences per file class by juliusknorr in [document-server-package#21](https://github.com/Euro-Office/document-server-package/pull/21)

### Performance

* web-apps: help: replace GIFs with WebM/MP4 and recompress PNGs by juliusknorr in [web-apps#352](https://github.com/Euro-Office/web-apps/pull/352)
* sdkjs: word: ⚡ check for table cell content before IsUseInDocument in section updates by moodyjmz in [sdkjs#123](https://github.com/Euro-Office/sdkjs/pull/123)
* sdkjs: cell: index area listeners to speed up the circular-reference check by MonaAghili in [sdkjs#119](https://github.com/Euro-Office/sdkjs/pull/119)
* document-server-package: package: hardlink duplicate web-apps files in deb and rpm by juliusknorr in [document-server-package#20](https://github.com/Euro-Office/document-server-package/pull/20)

### Other changes

* DocumentServer: ci: pass third-party cache credentials to the core build by juliusknorr in [DocumentServer#447](https://github.com/Euro-Office/DocumentServer/pull/447)
* DocumentServer: ci: reuse the registry build cache across commits by juliusknorr in [DocumentServer#446](https://github.com/Euro-Office/DocumentServer/pull/446)
* DocumentServer: ci: auto-approve and auto-merge non-major renovate updates by juliusknorr in [DocumentServer#454](https://github.com/Euro-Office/DocumentServer/pull/454)
* DocumentServer: chore(deps): update actions/download-artifact action to v8.0.2 by renovate[bot] in [DocumentServer#445](https://github.com/Euro-Office/DocumentServer/pull/445)
* DocumentServer: chore(deps): update actions/setup-node action to v6.5.0 by renovate[bot] in [DocumentServer#298](https://github.com/Euro-Office/DocumentServer/pull/298)
* DocumentServer: chore: update submodules to latest main branch by rikled in [DocumentServer#455](https://github.com/Euro-Office/DocumentServer/pull/455)
* DocumentServer: chore(deps): update docker/setup-buildx-action action to v4.4.1 by renovate[bot] in [DocumentServer#372](https://github.com/Euro-Office/DocumentServer/pull/372)
* DocumentServer: chore(deps): update zizmorcore/zizmor-action action to v0.7.1 by renovate[bot] in [DocumentServer#354](https://github.com/Euro-Office/DocumentServer/pull/354)
* DocumentServer: chore(deps): update actions/upload-artifact action to v7.0.2 by renovate[bot] in [DocumentServer#456](https://github.com/Euro-Office/DocumentServer/pull/456)
* DocumentServer: chore(deps): update dependency @playwright/test to v1.64.1 by renovate[bot] in [DocumentServer#340](https://github.com/Euro-Office/DocumentServer/pull/340)
* DocumentServer: chore(deps): update dependency @types/node to v22.20.5 by renovate[bot] in [DocumentServer#164](https://github.com/Euro-Office/DocumentServer/pull/164)
* DocumentServer: chore(deps): update dependency typescript to v7 by renovate[bot] in [DocumentServer#459](https://github.com/Euro-Office/DocumentServer/pull/459)
* DocumentServer: chore(deps): update actions/setup-node action to v7 by renovate[bot] in [DocumentServer#379](https://github.com/Euro-Office/DocumentServer/pull/379)
* DocumentServer: chore(deps): update zizmorcore/zizmor-action action to v0.8.0 by renovate[bot] in [DocumentServer#471](https://github.com/Euro-Office/DocumentServer/pull/471)
* DocumentServer: chore(deps): update actions/setup-node action to v7 by renovate[bot] in [DocumentServer#472](https://github.com/Euro-Office/DocumentServer/pull/472)
* DocumentServer: chore(deps): update docker/login-action action to v4.7.0 by renovate[bot] in [DocumentServer#457](https://github.com/Euro-Office/DocumentServer/pull/457)
* DocumentServer: chore(deps): update dependency node to v26 by renovate[bot] in [DocumentServer#477](https://github.com/Euro-Office/DocumentServer/pull/477)
* DocumentServer: ci(dev-images): reuse the main build cache and report cache hits by meisam-ui in [DocumentServer#463](https://github.com/Euro-Office/DocumentServer/pull/463)
* DocumentServer: chore(deps): update docker/bake-action action to v7.5.0 by renovate[bot] in [DocumentServer#460](https://github.com/Euro-Office/DocumentServer/pull/460)
* DocumentServer: ci: build vX.Y.Z-N tags as stable patch builds by juliusknorr in [DocumentServer#478](https://github.com/Euro-Office/DocumentServer/pull/478)
* DocumentServer: ci(update-submodules): authenticate the clones of private submodules by rikled in [DocumentServer#487](https://github.com/Euro-Office/DocumentServer/pull/487)
* DocumentServer: chore(deps): update dependency typescript-eslint to v8.72.1 by renovate[bot] in [DocumentServer#488](https://github.com/Euro-Office/DocumentServer/pull/488)
* DocumentServer: chore: update submodules to latest main branch by rikled in [DocumentServer#464](https://github.com/Euro-Office/DocumentServer/pull/464)
* DocumentServer: chore(deps): update dependency @types/node to v26.6.6 by renovate[bot] in [DocumentServer#495](https://github.com/Euro-Office/DocumentServer/pull/495)
* DocumentServer: build(docker): make BuildKit cache root configurable by nvanlaerebeke in [DocumentServer#403](https://github.com/Euro-Office/DocumentServer/pull/403)
* DocumentServer: build(docker): make BuildKit cache root configurable by meisam-ui in [DocumentServer#499](https://github.com/Euro-Office/DocumentServer/pull/499)
* DocumentServer: chore(deps): update dependency eslint to v10.14.0 by renovate[bot] in [DocumentServer#501](https://github.com/Euro-Office/DocumentServer/pull/501)
* DocumentServer: ci: split build and release, build only the e2e image on pull requests by juliusknorr in [DocumentServer#452](https://github.com/Euro-Office/DocumentServer/pull/452)
* DocumentServer: chore: update submodules to latest main branch by rikled in [DocumentServer#493](https://github.com/Euro-Office/DocumentServer/pull/493)
* server: ci: switch S3 storage tests to pgsty/minio by juliusknorr in [server#63](https://github.com/Euro-Office/server/pull/63)
* server: build: bump Node to 24 LTS by juliusknorr in [server#62](https://github.com/Euro-Office/server/pull/62)
* web-apps: i18n(fr): add the 40 missing French strings across all editors by SamsGuamejy in [web-apps#334](https://github.com/Euro-Office/web-apps/pull/334)
* web-apps: chore(deps): update github/codeql-action action to v4.39.1 by renovate[bot] in [web-apps#355](https://github.com/Euro-Office/web-apps/pull/355)
* web-apps: chore(deps): update actions/setup-python action to v7.1.0 by renovate[bot] in [web-apps#356](https://github.com/Euro-Office/web-apps/pull/356)
* web-apps: chore(deps): update dependency webpack to v5.112.1 by renovate[bot] in [web-apps#358](https://github.com/Euro-Office/web-apps/pull/358)
* web-apps: chore(deps): update dependency webpack to v5.112.2 by renovate[bot] in [web-apps#359](https://github.com/Euro-Office/web-apps/pull/359)
* web-apps: refactor(common): remove unused Switcher.setThumbPosition by juliusknorr in [web-apps#349](https://github.com/Euro-Office/web-apps/pull/349)
* web-apps: chore(deps): update dependency webpack-cli to v7.3.0 by renovate[bot] in [web-apps#373](https://github.com/Euro-Office/web-apps/pull/373)
* web-apps: chore(deps): update dependency webpack-cli to v7.3.1 by renovate[bot] in [web-apps#374](https://github.com/Euro-Office/web-apps/pull/374)
* sdkjs: build: sdkjs for the mobile editors' engine by rikled in [sdkjs#121](https://github.com/Euro-Office/sdkjs/pull/121)
* sdkjs: ci: auto-approve and auto-merge non-major renovate updates by juliusknorr in [sdkjs#118](https://github.com/Euro-Office/sdkjs/pull/118)
* sdkjs: chore(deps): pin dependencies by renovate[bot] in [sdkjs#129](https://github.com/Euro-Office/sdkjs/pull/129)
* sdkjs: chore(deps): update actions/upload-artifact action to v7 by renovate[bot] in [sdkjs#102](https://github.com/Euro-Office/sdkjs/pull/102)
* core: ci: mount third-party cache credentials in the core stage by juliusknorr in [core#177](https://github.com/Euro-Office/core/pull/177)
* core: fix(deps): bump brotli to v1.2.1 by juliusknorr in [core#184](https://github.com/Euro-Office/core/pull/184)
* core: test(odf): verify the TestEnv conversion produces a valid package by robintel in [core#167](https://github.com/Euro-Office/core/pull/167)
* core: test(rtf): add unit suite for the RTF lexer by robintel in [core#174](https://github.com/Euro-Office/core/pull/174)
* core: ci: cancel superseded pull request builds by juliusknorr in [core#195](https://github.com/Euro-Office/core/pull/195)
* core: ci: pull core-base from docker-ci, build it only when missing by juliusknorr in [core#201](https://github.com/Euro-Office/core/pull/201)
* core: ci: run macOS jobs on macos-15 by juliusknorr in [core#200](https://github.com/Euro-Office/core/pull/200)
* document-server-integration: fix(deps): build the nodejs example with Node 26 by juliusknorr in [document-server-integration#20](https://github.com/Euro-Office/document-server-integration/pull/20)

### Compare to v9.3.7-1

* DocumentServer: <https://github.com/Euro-Office/DocumentServer/compare/6ba1e1318785...4b107f80ec6e>
* server: <https://github.com/Euro-Office/server/compare/a924935680de...2e7a2a131061>
* web-apps: <https://github.com/Euro-Office/web-apps/compare/ce0ba4954581...f8d4506c130d>
* sdkjs: <https://github.com/Euro-Office/sdkjs/compare/40d9b7780f11...a1b8cac5d1bc>
* core: <https://github.com/Euro-Office/core/compare/afb3f233704b...5da2abf0c607>
* document-server-integration: <https://github.com/Euro-Office/document-server-integration/compare/d88f09562d0f...aedcb528d5f7>
* document-server-package: <https://github.com/Euro-Office/document-server-package/compare/c695b1b421ee...fbd85f29e591>

## v9.3.7-1

### Bug fixes

* DocumentServer: docker: refresh OS packages on every daily build by juliusknorr in [DocumentServer#480](https://github.com/Euro-Office/DocumentServer/pull/480)

### Other changes

* DocumentServer: ci: build vX.Y.Z-N tags as stable patch builds by juliusknorr in [DocumentServer#479](https://github.com/Euro-Office/DocumentServer/pull/479)
* core: fix(deps): bump brotli to v1.2.1 by juliusknorr in [core#189](https://github.com/Euro-Office/core/pull/189)

### Compare to v9.3.7

* DocumentServer: <https://github.com/Euro-Office/DocumentServer/compare/e8d67f92c8a8...41a1285ce046>
* core: <https://github.com/Euro-Office/core/compare/a4a1ba1e9c8e...afb3f233704b>

## v9.3.7

### Other changes

* server: build: bump Node to 24 LTS (stable-9.3.7) by juliusknorr in [server#66](https://github.com/Euro-Office/server/pull/66)

### Compare to v9.3.6

* server: <https://github.com/Euro-Office/server/compare/044184a530ef...a924935680de>

## v9.3.6

### Features

* DocumentServer: develop: raise upload limits to 500 MB in dev setups by juliusknorr in [DocumentServer#420](https://github.com/Euro-Office/DocumentServer/pull/420)
* DocumentServer: add nextcloud release workflow, put nextcloud office ssh push into separate step by rikled in [DocumentServer#421](https://github.com/Euro-Office/DocumentServer/pull/421)
* DocumentServer: ci: add dev branch image pipeline by meisam-ui in [DocumentServer#405](https://github.com/Euro-Office/DocumentServer/pull/405)
* web-apps: about: show build commits and Euro-Office legal notice by juliusknorr in [web-apps#332](https://github.com/Euro-Office/web-apps/pull/332)

### Bug fixes

* DocumentServer: Command for starting example server shown in web view by rikled in [DocumentServer#294](https://github.com/Euro-Office/DocumentServer/pull/294)
* DocumentServer: docker: sync example app JWT config with document server by rikled in [DocumentServer#397](https://github.com/Euro-Office/DocumentServer/pull/397)
* DocumentServer: docker: stop postgres before committing the standalone image layer by belst in [DocumentServer#427](https://github.com/Euro-Office/DocumentServer/pull/427)
* web-apps: Fixing support and help URLs by Aiiaiiio in [web-apps#335](https://github.com/Euro-Office/web-apps/pull/335)
* web-apps: common: draw svgicon button icons again by bargib in [web-apps#321](https://github.com/Euro-Office/web-apps/pull/321)
* web-apps: collapse empty icon svgs inflating language menus (#165) by moodyjmz in [web-apps#167](https://github.com/Euro-Office/web-apps/pull/167)
* web-apps: de-mobile: keep documents editable on mobile with forceView=false by jpxd in [web-apps#336](https://github.com/Euro-Office/web-apps/pull/336)
* web-apps: l10n: the diagram viewer in Danish by bargib in [web-apps#328](https://github.com/Euro-Office/web-apps/pull/328)
* web-apps: theme: hide the accent strip during the slideshow by bargib in [web-apps#346](https://github.com/Euro-Office/web-apps/pull/346)
* core: linux: stop libgraphics and PdfFile from exporting bundled third-party symbols by rikled in [core#164](https://github.com/Euro-Office/core/pull/164)
* core: odf: avoid crash on custom shape with empty formula by juliusknorr in [core#161](https://github.com/Euro-Office/core/pull/161)

### Other changes

* DocumentServer: chore: version bump to 9.3.5 by DmySyz in [DocumentServer#412](https://github.com/Euro-Office/DocumentServer/pull/412)
* DocumentServer: Update README.md by ervee in [DocumentServer#418](https://github.com/Euro-Office/DocumentServer/pull/418)
* DocumentServer: docs(AGENTS.md): Add note about copyright and licenses by juliusknorr in [DocumentServer#380](https://github.com/Euro-Office/DocumentServer/pull/380)
* DocumentServer: build: pass build commits to web-apps for the About dialog by juliusknorr in [DocumentServer#419](https://github.com/Euro-Office/DocumentServer/pull/419)
* DocumentServer: ci: sync workflows from organization templates by eo-robot in [DocumentServer#423](https://github.com/Euro-Office/DocumentServer/pull/423)
* DocumentServer: docs: add install section by juliusknorr in [DocumentServer#426](https://github.com/Euro-Office/DocumentServer/pull/426)
* DocumentServer: chore(deps): update docker/bake-action action to v7 by renovate[bot] in [DocumentServer#194](https://github.com/Euro-Office/DocumentServer/pull/194)
* DocumentServer: ci: keep :latest for stable tags, add test build outputs by juliusknorr in [DocumentServer#431](https://github.com/Euro-Office/DocumentServer/pull/431)
* DocumentServer: ci: drop vX.Y.Z+N rebuild tags by juliusknorr in [DocumentServer#406](https://github.com/Euro-Office/DocumentServer/pull/406)
* DocumentServer: ci: share the clone cache between hosted and self-hosted runners by juliusknorr in [DocumentServer#435](https://github.com/Euro-Office/DocumentServer/pull/435)
* DocumentServer: refactor(e2e): move playwright tests into e2e/frontend by bhumigopaniStarto in [DocumentServer#429](https://github.com/Euro-Office/DocumentServer/pull/429)
* DocumentServer: chore(release): v9.3.6-rc.1 by eo-robot in [DocumentServer#448](https://github.com/Euro-Office/DocumentServer/pull/448)
* server: ci: sync workflows from organization templates by eo-robot in [server#55](https://github.com/Euro-Office/server/pull/55)
* server: ci: sync workflows from organization templates by eo-robot in [server#56](https://github.com/Euro-Office/server/pull/56)
* web-apps: chore(deps): update dependency python to 3.15 by renovate[bot] in [web-apps#326](https://github.com/Euro-Office/web-apps/pull/326)
* web-apps: ci: sync workflows from organization templates by eo-robot in [web-apps#337](https://github.com/Euro-Office/web-apps/pull/337)
* web-apps: ci: sync workflows from organization templates by eo-robot in [web-apps#338](https://github.com/Euro-Office/web-apps/pull/338)
* web-apps: chore(deps): update github/codeql-action action to v4.39.0 by renovate[bot] in [web-apps#341](https://github.com/Euro-Office/web-apps/pull/341)
* web-apps: chore(deps): update dependency webpack to v5.112.0 by renovate[bot] in [web-apps#342](https://github.com/Euro-Office/web-apps/pull/342)
* web-apps: chore(l10n): update translations by hosted-weblate[bot] in [web-apps#318](https://github.com/Euro-Office/web-apps/pull/318)
* web-apps: chore(l10n): update translations by hosted-weblate[bot] in [web-apps#344](https://github.com/Euro-Office/web-apps/pull/344)
* web-apps: test(i18n): add generic locale parity validation by Dragonk in [web-apps#198](https://github.com/Euro-Office/web-apps/pull/198)
* web-apps: chore(pl): complete Polish desktop locale coverage by Dragonk in [web-apps#200](https://github.com/Euro-Office/web-apps/pull/200)
* web-apps: chore(pl): complete Polish mobile locale coverage by Dragonk in [web-apps#199](https://github.com/Euro-Office/web-apps/pull/199)
* sdkjs: ci: sync workflows from organization templates by eo-robot in [sdkjs#113](https://github.com/Euro-Office/sdkjs/pull/113)
* sdkjs: chore(deps): update dependency terser to v5.51.2 by renovate[bot] in [sdkjs#73](https://github.com/Euro-Office/sdkjs/pull/73)
* sdkjs: chore(deps): update actions/checkout action to v7 by renovate[bot] in [sdkjs#100](https://github.com/Euro-Office/sdkjs/pull/100)
* sdkjs: chore(deps): update dependency python to 3.15 by renovate[bot] in [sdkjs#111](https://github.com/Euro-Office/sdkjs/pull/111)
* core-fonts: ci: sync workflows from organization templates by eo-robot in [core-fonts#8](https://github.com/Euro-Office/core-fonts/pull/8)
* core: ci: sync workflows from organization templates by eo-robot in [core#163](https://github.com/Euro-Office/core/pull/163)
* core: ci(codeql): scan this repository instead of upstream by juliusknorr in [core#162](https://github.com/Euro-Office/core/pull/162)
* document-server-integration: ci: sync workflows from organization templates by eo-robot in [document-server-integration#17](https://github.com/Euro-Office/document-server-integration/pull/17)
* document-server-integration: ci: sync workflows from organization templates by eo-robot in [document-server-integration#18](https://github.com/Euro-Office/document-server-integration/pull/18)
* dictionaries: i18n(da): update the Danish spelling dictionary to Stavekontrolden 2.9.101 by bargib in [dictionaries#9](https://github.com/Euro-Office/dictionaries/pull/9)
* dictionaries: ci: sync workflows from organization templates by eo-robot in [dictionaries#11](https://github.com/Euro-Office/dictionaries/pull/11)
* document-templates: ci: sync workflows from organization templates by eo-robot in [document-templates#9](https://github.com/Euro-Office/document-templates/pull/9)
* document-server-package: ci: sync workflows from organization templates by eo-robot in [document-server-package#18](https://github.com/Euro-Office/document-server-package/pull/18)
* sdkjs-forms: ci: sync workflows from organization templates by eo-robot in [sdkjs-forms#7](https://github.com/Euro-Office/sdkjs-forms/pull/7)
* document-formats: ci: sync workflows from organization templates by eo-robot in [document-formats#8](https://github.com/Euro-Office/document-formats/pull/8)

### Compare to v9.3.5

* DocumentServer: <https://github.com/Euro-Office/DocumentServer/compare/14a424804f52...7294d4650da6>
* server: <https://github.com/Euro-Office/server/compare/56bc9d4ae5ff...044184a530ef>
* web-apps: <https://github.com/Euro-Office/web-apps/compare/d8fabf59cbc6...ce0ba4954581>
* sdkjs: <https://github.com/Euro-Office/sdkjs/compare/0cde84e8dbfb...40d9b7780f11>
* core-fonts: <https://github.com/Euro-Office/core-fonts/compare/2de90688e07e...9cd64d6eedc7>
* core: <https://github.com/Euro-Office/core/compare/5a33ce6c4a63...a4a1ba1e9c8e>
* document-server-integration: <https://github.com/Euro-Office/document-server-integration/compare/f7cd03c026f6...d88f09562d0f>
* dictionaries: <https://github.com/Euro-Office/dictionaries/compare/011baa088d60...0020f5ed5174>
* document-templates: <https://github.com/Euro-Office/document-templates/compare/6fc434d77916...40cc88d509ba>
* document-server-package: <https://github.com/Euro-Office/document-server-package/compare/84907ab05ebc...c695b1b421ee>
* sdkjs-forms: <https://github.com/Euro-Office/sdkjs-forms/compare/e7859d1d421f...5c2f5a010dae>
* document-formats: <https://github.com/Euro-Office/document-formats/compare/46995828084d...f6cef0b2977a>

## v9.3.6-rc.1

### Features

* DocumentServer: develop: raise upload limits to 500 MB in dev setups by juliusknorr in [DocumentServer#420](https://github.com/Euro-Office/DocumentServer/pull/420)
* DocumentServer: add nextcloud release workflow, put nextcloud office ssh push into separate step by rikled in [DocumentServer#421](https://github.com/Euro-Office/DocumentServer/pull/421)
* web-apps: about: show build commits and Euro-Office legal notice by juliusknorr in [web-apps#332](https://github.com/Euro-Office/web-apps/pull/332)

### Bug fixes

* DocumentServer: Command for starting example server shown in web view by rikled in [DocumentServer#294](https://github.com/Euro-Office/DocumentServer/pull/294)
* DocumentServer: docker: sync example app JWT config with document server by rikled in [DocumentServer#397](https://github.com/Euro-Office/DocumentServer/pull/397)
* DocumentServer: docker: stop postgres before committing the standalone image layer by belst in [DocumentServer#427](https://github.com/Euro-Office/DocumentServer/pull/427)
* web-apps: Fixing support and help URLs by Aiiaiiio in [web-apps#335](https://github.com/Euro-Office/web-apps/pull/335)
* web-apps: common: draw svgicon button icons again by bargib in [web-apps#321](https://github.com/Euro-Office/web-apps/pull/321)
* web-apps: collapse empty icon svgs inflating language menus (#165) by moodyjmz in [web-apps#167](https://github.com/Euro-Office/web-apps/pull/167)
* web-apps: de-mobile: keep documents editable on mobile with forceView=false by jpxd in [web-apps#336](https://github.com/Euro-Office/web-apps/pull/336)
* web-apps: l10n: the diagram viewer in Danish by bargib in [web-apps#328](https://github.com/Euro-Office/web-apps/pull/328)
* web-apps: theme: hide the accent strip during the slideshow by bargib in [web-apps#346](https://github.com/Euro-Office/web-apps/pull/346)
* core: linux: stop libgraphics and PdfFile from exporting bundled third-party symbols by rikled in [core#164](https://github.com/Euro-Office/core/pull/164)
* core: odf: avoid crash on custom shape with empty formula by juliusknorr in [core#161](https://github.com/Euro-Office/core/pull/161)

### Other changes

* DocumentServer: chore: version bump to 9.3.5 by DmySyz in [DocumentServer#412](https://github.com/Euro-Office/DocumentServer/pull/412)
* DocumentServer: Update README.md by ervee in [DocumentServer#418](https://github.com/Euro-Office/DocumentServer/pull/418)
* DocumentServer: docs(AGENTS.md): Add note about copyright and licenses by juliusknorr in [DocumentServer#380](https://github.com/Euro-Office/DocumentServer/pull/380)
* DocumentServer: build: pass build commits to web-apps for the About dialog by juliusknorr in [DocumentServer#419](https://github.com/Euro-Office/DocumentServer/pull/419)
* DocumentServer: ci: sync workflows from organization templates by eo-robot in [DocumentServer#423](https://github.com/Euro-Office/DocumentServer/pull/423)
* DocumentServer: docs: add install section by juliusknorr in [DocumentServer#426](https://github.com/Euro-Office/DocumentServer/pull/426)
* DocumentServer: chore(deps): update docker/bake-action action to v7 by renovate[bot] in [DocumentServer#194](https://github.com/Euro-Office/DocumentServer/pull/194)
* DocumentServer: ci: keep :latest for stable tags, add test build outputs by juliusknorr in [DocumentServer#431](https://github.com/Euro-Office/DocumentServer/pull/431)
* DocumentServer: ci: drop vX.Y.Z+N rebuild tags by juliusknorr in [DocumentServer#406](https://github.com/Euro-Office/DocumentServer/pull/406)
* DocumentServer: ci: share the clone cache between hosted and self-hosted runners by juliusknorr in [DocumentServer#435](https://github.com/Euro-Office/DocumentServer/pull/435)
* server: ci: sync workflows from organization templates by eo-robot in [server#55](https://github.com/Euro-Office/server/pull/55)
* server: ci: sync workflows from organization templates by eo-robot in [server#56](https://github.com/Euro-Office/server/pull/56)
* web-apps: chore(deps): update dependency python to 3.15 by renovate[bot] in [web-apps#326](https://github.com/Euro-Office/web-apps/pull/326)
* web-apps: ci: sync workflows from organization templates by eo-robot in [web-apps#337](https://github.com/Euro-Office/web-apps/pull/337)
* web-apps: ci: sync workflows from organization templates by eo-robot in [web-apps#338](https://github.com/Euro-Office/web-apps/pull/338)
* web-apps: chore(deps): update github/codeql-action action to v4.39.0 by renovate[bot] in [web-apps#341](https://github.com/Euro-Office/web-apps/pull/341)
* web-apps: chore(deps): update dependency webpack to v5.112.0 by renovate[bot] in [web-apps#342](https://github.com/Euro-Office/web-apps/pull/342)
* web-apps: chore(l10n): update translations by hosted-weblate[bot] in [web-apps#318](https://github.com/Euro-Office/web-apps/pull/318)
* web-apps: chore(l10n): update translations by hosted-weblate[bot] in [web-apps#344](https://github.com/Euro-Office/web-apps/pull/344)
* web-apps: test(i18n): add generic locale parity validation by Dragonk in [web-apps#198](https://github.com/Euro-Office/web-apps/pull/198)
* web-apps: chore(pl): complete Polish desktop locale coverage by Dragonk in [web-apps#200](https://github.com/Euro-Office/web-apps/pull/200)
* web-apps: chore(pl): complete Polish mobile locale coverage by Dragonk in [web-apps#199](https://github.com/Euro-Office/web-apps/pull/199)
* sdkjs: ci: sync workflows from organization templates by eo-robot in [sdkjs#113](https://github.com/Euro-Office/sdkjs/pull/113)
* sdkjs: chore(deps): update dependency terser to v5.51.2 by renovate[bot] in [sdkjs#73](https://github.com/Euro-Office/sdkjs/pull/73)
* sdkjs: chore(deps): update actions/checkout action to v7 by renovate[bot] in [sdkjs#100](https://github.com/Euro-Office/sdkjs/pull/100)
* sdkjs: chore(deps): update dependency python to 3.15 by renovate[bot] in [sdkjs#111](https://github.com/Euro-Office/sdkjs/pull/111)
* core-fonts: ci: sync workflows from organization templates by eo-robot in [core-fonts#8](https://github.com/Euro-Office/core-fonts/pull/8)
* core: ci: sync workflows from organization templates by eo-robot in [core#163](https://github.com/Euro-Office/core/pull/163)
* core: ci(codeql): scan this repository instead of upstream by juliusknorr in [core#162](https://github.com/Euro-Office/core/pull/162)
* document-server-integration: ci: sync workflows from organization templates by eo-robot in [document-server-integration#17](https://github.com/Euro-Office/document-server-integration/pull/17)
* document-server-integration: ci: sync workflows from organization templates by eo-robot in [document-server-integration#18](https://github.com/Euro-Office/document-server-integration/pull/18)
* dictionaries: i18n(da): update the Danish spelling dictionary to Stavekontrolden 2.9.101 by bargib in [dictionaries#9](https://github.com/Euro-Office/dictionaries/pull/9)
* dictionaries: ci: sync workflows from organization templates by eo-robot in [dictionaries#11](https://github.com/Euro-Office/dictionaries/pull/11)
* document-templates: ci: sync workflows from organization templates by eo-robot in [document-templates#9](https://github.com/Euro-Office/document-templates/pull/9)
* document-server-package: ci: sync workflows from organization templates by eo-robot in [document-server-package#18](https://github.com/Euro-Office/document-server-package/pull/18)
* sdkjs-forms: ci: sync workflows from organization templates by eo-robot in [sdkjs-forms#7](https://github.com/Euro-Office/sdkjs-forms/pull/7)
* document-formats: ci: sync workflows from organization templates by eo-robot in [document-formats#8](https://github.com/Euro-Office/document-formats/pull/8)

### Compare to v9.3.5

* DocumentServer: <https://github.com/Euro-Office/DocumentServer/compare/14a424804f52...8eb356ea8074>
* server: <https://github.com/Euro-Office/server/compare/56bc9d4ae5ff...044184a530ef>
* web-apps: <https://github.com/Euro-Office/web-apps/compare/d8fabf59cbc6...ce0ba4954581>
* sdkjs: <https://github.com/Euro-Office/sdkjs/compare/0cde84e8dbfb...40d9b7780f11>
* core-fonts: <https://github.com/Euro-Office/core-fonts/compare/2de90688e07e...9cd64d6eedc7>
* core: <https://github.com/Euro-Office/core/compare/5a33ce6c4a63...a4a1ba1e9c8e>
* document-server-integration: <https://github.com/Euro-Office/document-server-integration/compare/f7cd03c026f6...d88f09562d0f>
* dictionaries: <https://github.com/Euro-Office/dictionaries/compare/011baa088d60...0020f5ed5174>
* document-templates: <https://github.com/Euro-Office/document-templates/compare/6fc434d77916...40cc88d509ba>
* document-server-package: <https://github.com/Euro-Office/document-server-package/compare/84907ab05ebc...c695b1b421ee>
* sdkjs-forms: <https://github.com/Euro-Office/sdkjs-forms/compare/e7859d1d421f...5c2f5a010dae>
* document-formats: <https://github.com/Euro-Office/document-formats/compare/46995828084d...f6cef0b2977a>
