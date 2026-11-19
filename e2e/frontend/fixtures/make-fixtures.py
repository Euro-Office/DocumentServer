#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only

"""Build the open-* specs' fixture documents.

Writes fixture.docx, fixture.xlsx and fixture.pptx next to this script: the
smallest valid OOXML package of each type that holds one known string, listed
in FIXTURE_TEXT below.

The packages are written from raw XML rather than saved out of the editor on
purpose. These files are the oracle the open-* specs compare the editor against,
so a fault in our own writer must not be able to bake itself into them.

Not `e2e/perf/gen-workbooks.ts`, which also writes xlsx from raw XML: that one
builds large workbooks to time the open path. The only overlap is the zip
container.

Run after changing any of the XML here, then re-run the open-* specs:

    python3 -I e2e/frontend/fixtures/make-fixtures.py

Keep the strings in step with FIXTURE_TEXT in e2e/frontend/tests/helpers.ts.
uploadFixtureFile checks that they match, so drift fails as "fixture out of
step" rather than as an editor content mismatch — but it cannot fix it for you.
"""

import zipfile
from pathlib import Path

FIXTURE_TEXT = {
    "docx": "Euro-Office e2e fixture paragraph",
    "xlsx": "Euro-Office e2e fixture cell",
    "pptx": "Euro-Office e2e fixture title",
}

# Shared by every package: the OPC root relationship pointing at the part that
# holds the content.
ROOT_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="{target}"/>
</Relationships>"""


def docx(text):
    """A one-paragraph word processing document."""
    return {
        "[Content_Types].xml": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>""",
        "_rels/.rels": ROOT_RELS.format(target="word/document.xml"),
        "word/document.xml": f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>
<w:p><w:r><w:t xml:space="preserve">{text}</w:t></w:r></w:p>
<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="709" w:footer="709" w:gutter="0"/></w:sectPr>
</w:body>
</w:document>""",
    }


def xlsx(text):
    """A single-sheet workbook with the string in A1.

    The value goes in sharedStrings rather than inline: that is the form the
    editor's own writer emits, so the fixture exercises the path a real
    uploaded workbook takes.
    """
    return {
        "[Content_Types].xml": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>""",
        "_rels/.rels": ROOT_RELS.format(target="xl/workbook.xml"),
        "xl/workbook.xml": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
</workbook>""",
        "xl/_rels/workbook.xml.rels": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>""",
        "xl/worksheets/sheet1.xml": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<dimension ref="A1"/>
<sheetData><row r="1"><c r="A1" t="s"><v>0</v></c></row></sheetData>
</worksheet>""",
        "xl/sharedStrings.xml": f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="1" uniqueCount="1">
<si><t xml:space="preserve">{text}</t></si>
</sst>""",
        "xl/styles.xml": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="1"><fill><patternFill patternType="none"/></fill></fills>
<borders count="1"><border/></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
</styleSheet>""",
    }


# The slide master and layout carry no content, but a presentation is not valid
# without them: the slide inherits its colour and font mapping through the
# layout from the master, and the master in turn needs a theme.
_SLIDE_NS = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'

_EMPTY_SP_TREE = """<p:spTree>
<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
</p:spTree>"""

_CLR_MAP = 'bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"'


def _theme():
    """A theme with the twelve colours, two font slots and one format scheme
    entry that a slide master is required to reference."""
    accents = "".join(
        f'<a:accent{i}><a:srgbClr val="4472C4"/></a:accent{i}>' for i in range(1, 7)
    )
    fonts = "".join(
        f'<a:{slot}><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:{slot}>'
        for slot in ("majorFont", "minorFont")
    )
    fill_style = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    line_style = f'<a:ln w="6350" cap="flat" cmpd="sng" algn="ctr">{fill_style}<a:prstDash val="solid"/></a:ln>'
    effect_style = "<a:effectStyle><a:effectLst/></a:effectStyle>"
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office">
<a:themeElements>
<a:clrScheme name="Office"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="44546A"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>{accents}<a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme>
<a:fontScheme name="Office">{fonts}</a:fontScheme>
<a:fmtScheme name="Office">
<a:fillStyleLst>{fill_style}{fill_style}{fill_style}</a:fillStyleLst>
<a:lnStyleLst>{line_style}{line_style}{line_style}</a:lnStyleLst>
<a:effectStyleLst>{effect_style}{effect_style}{effect_style}</a:effectStyleLst>
<a:bgFillStyleLst>{fill_style}{fill_style}{fill_style}</a:bgFillStyleLst>
</a:fmtScheme>
</a:themeElements>
</a:theme>"""


def pptx(text):
    """A one-slide deck whose only shape is a title holding the string."""
    return {
        "[Content_Types].xml": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
<Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
</Types>""",
        "_rels/.rels": ROOT_RELS.format(target="ppt/presentation.xml"),
        "ppt/presentation.xml": f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation {_SLIDE_NS}>
<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
<p:sldIdLst><p:sldId id="256" r:id="rId2"/></p:sldIdLst>
<p:sldSz cx="12192000" cy="6858000"/>
<p:notesSz cx="6858000" cy="9144000"/>
</p:presentation>""",
        "ppt/_rels/presentation.xml.rels": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
</Relationships>""",
        "ppt/slides/slide1.xml": f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld {_SLIDE_NS}>
<p:cSld><p:spTree>
<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
<p:sp>
<p:nvSpPr><p:cNvPr id="2" name="Title 1"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="ctrTitle"/></p:nvPr></p:nvSpPr>
<p:spPr><a:xfrm><a:off x="1524000" y="2514600"/><a:ext cx="9144000" cy="1828800"/></a:xfrm></p:spPr>
<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" dirty="0"/><a:t>{text}</a:t></a:r></a:p></p:txBody>
</p:sp>
</p:spTree></p:cSld>
<p:clrMapOvr><a:overrideClrMapping {_CLR_MAP}/></p:clrMapOvr>
</p:sld>""",
        "ppt/slides/_rels/slide1.xml.rels": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>""",
        "ppt/slideLayouts/slideLayout1.xml": f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout {_SLIDE_NS} type="title" preserve="1">
<p:cSld name="Title Slide">{_EMPTY_SP_TREE}</p:cSld>
<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sldLayout>""",
        "ppt/slideLayouts/_rels/slideLayout1.xml.rels": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>""",
        "ppt/slideMasters/slideMaster1.xml": f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster {_SLIDE_NS}>
<p:cSld>{_EMPTY_SP_TREE}</p:cSld>
<p:clrMap {_CLR_MAP}/>
<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
</p:sldMaster>""",
        "ppt/slideMasters/_rels/slideMaster1.xml.rels": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
</Relationships>""",
        "ppt/theme/theme1.xml": _theme(),
    }


BUILDERS = {"docx": docx, "xlsx": xlsx, "pptx": pptx}


def main():
    out_dir = Path(__file__).resolve().parent
    for ext, build in BUILDERS.items():
        parts = build(FIXTURE_TEXT[ext])
        path = out_dir / f"fixture.{ext}"
        # Fixed timestamps, and stored rather than deflated: rebuilding an
        # unchanged fixture then produces identical bytes whatever zlib is
        # installed, and the text stays greppable in the file itself, which is
        # what lets uploadFixtureFile check the fixture against FIXTURE_TEXT.
        # These packages are a few KB; the compression buys nothing.
        with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as package:
            for name, body in parts.items():
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_STORED
                info.external_attr = 0o644 << 16
                package.writestr(info, body)
        print(f"{path.name}: {path.stat().st_size} bytes, {len(parts)} parts")


if __name__ == "__main__":
    main()
