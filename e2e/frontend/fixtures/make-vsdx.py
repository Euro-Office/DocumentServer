#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only
"""Write minimal.vsdx: one page, one labelled rectangle. Run: python3 make-vsdx.py"""
import pathlib
import zipfile

NS = 'http://schemas.microsoft.com/office/visio/2012/main'
REL_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
PKG_REL_NS = 'http://schemas.openxmlformats.org/package/2006/relationships'
VISIO_REL = 'http://schemas.microsoft.com/visio/2010/relationships'
XML = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'


def rels(*entries):
    body = ''.join(f'<Relationship Id="{i}" Type="{t}" Target="{target}"/>' for i, t, target in entries)
    return f'{XML}<Relationships xmlns="{PKG_REL_NS}">{body}</Relationships>'


def cell(name, value):
    return f'<Cell N="{name}" V="{value}"/>'


def row(kind, ix, x, y):
    return f'<Row T="{kind}" IX="{ix}">{cell("X", x)}{cell("Y", y)}</Row>'


shape = (
    '<Shape ID="1" Type="Shape">'
    + ''.join(cell(n, v) for n, v in [('PinX', 4.25), ('PinY', 5.5), ('Width', 3), ('Height', 1.5),
                                      ('LocPinX', 1.5), ('LocPinY', 0.75)])
    + '<Section N="Geometry" IX="0">'
    + row('MoveTo', 1, 0, 0) + row('LineTo', 2, 3, 0) + row('LineTo', 3, 3, 1.5)
    + row('LineTo', 4, 0, 1.5) + row('LineTo', 5, 0, 0)
    + '</Section><Text>Euro-Office e2e</Text></Shape>'
)

parts = {
    '[Content_Types].xml': (
        f'{XML}<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/visio/document.xml" ContentType="application/vnd.ms-visio.drawing.main+xml"/>'
        '<Override PartName="/visio/windows.xml" ContentType="application/vnd.ms-visio.windows+xml"/>'
        '<Override PartName="/visio/pages/pages.xml" ContentType="application/vnd.ms-visio.pages+xml"/>'
        '<Override PartName="/visio/pages/page1.xml" ContentType="application/vnd.ms-visio.page+xml"/>'
        '</Types>'),
    '_rels/.rels': rels(('rId1', f'{VISIO_REL}/document', 'visio/document.xml')),
    'visio/document.xml': f'{XML}<VisioDocument xmlns="{NS}" xmlns:r="{REL_NS}"/>',
    'visio/_rels/document.xml.rels': rels(
        ('rId1', f'{VISIO_REL}/pages', 'pages/pages.xml'),
        ('rId2', f'{VISIO_REL}/windows', 'windows.xml')),
    # x2t segfaults on a package without windows.xml
    'visio/windows.xml': (
        f'{XML}<Windows xmlns="{NS}" ClientWidth="1000" ClientHeight="800">'
        '<Window ID="0" WindowType="Drawing" Page="0"/></Windows>'),
    'visio/pages/pages.xml': (
        f'{XML}<Pages xmlns="{NS}" xmlns:r="{REL_NS}"><Page ID="0" Name="Page-1">'
        f'<PageSheet>{cell("PageWidth", 8.5)}{cell("PageHeight", 11)}</PageSheet>'
        '<Rel r:id="rId1"/></Page></Pages>'),
    'visio/pages/_rels/pages.xml.rels': rels(('rId1', f'{VISIO_REL}/page', 'page1.xml')),
    'visio/pages/page1.xml': f'{XML}<PageContents xmlns="{NS}" xmlns:r="{REL_NS}"><Shapes>{shape}</Shapes></PageContents>',
}

out = pathlib.Path(__file__).with_name('minimal.vsdx')
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for name, data in parts.items():
        # Fixed timestamp keeps the output byte-identical across runs
        z.writestr(zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0)), data, zipfile.ZIP_DEFLATED)
print(out)
