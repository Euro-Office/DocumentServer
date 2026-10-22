# Changelog

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
