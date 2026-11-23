#!/usr/bin/env python3
"""기획안 파일(xlsx, pptx, docx, pdf)을 텍스트로 추출한다.

사용법:
    python3 .claude/scripts/extract_spec.py <파일> [-o <출력 파일>]

xlsx, pptx, docx는 표준 라이브러리만 쓴다.
pdf는 pypdf가 있으면 pypdf를, 없으면 pdftotext 명령을 쓴다. 둘 다 없으면 종료 코드 2.
이미지 안의 글자는 추출하지 않는다. 화면 설계가 이미지뿐이면 그 사실을 보고해야 한다.
"""

import argparse
import posixpath
import re
import shutil
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
A = "{http://schemas.openxmlformats.org/drawingml/2006/main}"
S = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
REL = "{http://schemas.openxmlformats.org/package/2006/relationships}"


def natural_key(name):
    return [int(part) if part.isdigit() else part for part in re.split(r"(\d+)", name)]


def read_xml(archive, name):
    return ET.fromstring(archive.read(name))


def relationships(archive, part):
    """part(예: xl/workbook.xml)의 관계 파일을 읽어 {rId: 대상 경로}를 돌려준다."""
    folder, filename = posixpath.split(part)
    rels_name = posixpath.join(folder, "_rels", filename + ".rels")
    if rels_name not in archive.namelist():
        return {}
    result = {}
    for rel in read_xml(archive, rels_name).iter(REL + "Relationship"):
        target = rel.get("Target", "")
        if rel.get("TargetMode") == "External":
            continue
        if target.startswith("/"):
            resolved = target.lstrip("/")
        else:
            resolved = posixpath.normpath(posixpath.join(folder, target))
        result[rel.get("Id")] = resolved
    return result


# ---------- docx ----------

def docx_paragraph(paragraph):
    parts = []
    for node in paragraph.iter():
        if node.tag == W + "t":
            parts.append(node.text or "")
        elif node.tag == W + "tab":
            parts.append("\t")
        elif node.tag in (W + "br", W + "cr"):
            parts.append("\n")
    return "".join(parts)


def docx_table(table):
    rows = []
    for row in table.findall(W + "tr"):
        cells = []
        for cell in row.findall(W + "tc"):
            text = " ".join(
                t for t in (docx_paragraph(p).strip() for p in cell.iter(W + "p")) if t
            )
            cells.append(text)
        rows.append(" | ".join(cells))
    return rows


def extract_docx(path):
    lines = []
    with zipfile.ZipFile(path) as archive:
        body = read_xml(archive, "word/document.xml").find(W + "body")
        if body is None:
            return ""
        for child in body:
            if child.tag == W + "p":
                text = docx_paragraph(child)
                if text.strip():
                    lines.append(text)
            elif child.tag == W + "tbl":
                lines.append("[표]")
                lines.extend(docx_table(child))
                lines.append("[/표]")
    return "\n".join(lines)


# ---------- pptx ----------

def drawing_paragraphs(root):
    result = []
    for paragraph in root.iter(A + "p"):
        text = "".join(node.text or "" for node in paragraph.iter(A + "t"))
        if text.strip():
            result.append(text)
    return result


def extract_pptx(path):
    lines = []
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        slides = sorted(
            (n for n in names if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)),
            key=natural_key,
        )
        for index, slide in enumerate(slides, start=1):
            lines.append(f"=== 슬라이드 {index} ===")
            lines.extend(drawing_paragraphs(read_xml(archive, slide)))
            for target in relationships(archive, slide).values():
                if "notesSlides/" in target and target in names:
                    notes = drawing_paragraphs(read_xml(archive, target))
                    notes = [n for n in notes if not n.strip().isdigit()]
                    if notes:
                        lines.append("[발표자 노트]")
                        lines.extend(notes)
            lines.append("")
    return "\n".join(lines)


# ---------- xlsx ----------

def shared_strings(archive):
    name = "xl/sharedStrings.xml"
    if name not in archive.namelist():
        return []
    result = []
    for item in read_xml(archive, name).findall(S + "si"):
        # 윗주(rPh)는 본문이 아니므로 뺀다.
        parts = []
        for node in item.iter(S + "t"):
            parts.append(node.text or "")
        phonetic = "".join(
            node.text or "" for ph in item.findall(S + "rPh") for node in ph.iter(S + "t")
        )
        text = "".join(parts)
        if phonetic and text.endswith(phonetic):
            text = text[: -len(phonetic)]
        result.append(text)
    return result


def column_index(reference):
    letters = "".join(ch for ch in reference if ch.isalpha())
    index = 0
    for ch in letters.upper():
        index = index * 26 + (ord(ch) - ord("A") + 1)
    return index - 1


def cell_text(cell, strings):
    kind = cell.get("t")
    if kind == "inlineStr":
        inline = cell.find(S + "is")
        return "".join(n.text or "" for n in inline.iter(S + "t")) if inline is not None else ""
    value = cell.find(S + "v")
    if value is None or value.text is None:
        return ""
    if kind == "s":
        try:
            return strings[int(value.text)]
        except (ValueError, IndexError):
            return ""
    if kind == "b":
        return "TRUE" if value.text == "1" else "FALSE"
    return value.text


def extract_xlsx(path):
    lines = []
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        strings = shared_strings(archive)
        rels = relationships(archive, "xl/workbook.xml")
        workbook = read_xml(archive, "xl/workbook.xml")
        for sheet in workbook.iter(S + "sheet"):
            target = rels.get(sheet.get(R + "id"))
            if not target or target not in names:
                continue
            lines.append(f"=== 시트: {sheet.get('name')} ===")
            for row in read_xml(archive, target).iter(S + "row"):
                values = []
                for position, cell in enumerate(row.findall(S + "c")):
                    reference = cell.get("r")
                    index = column_index(reference) if reference else position
                    while len(values) < index:
                        values.append("")
                    values.append(cell_text(cell, strings).replace("\n", " ⏎ "))
                while values and not values[-1]:
                    values.pop()
                if values:
                    lines.append("\t".join(values))
            lines.append("")
    return "\n".join(lines)


# ---------- pdf ----------

def extract_pdf(path):
    try:
        from pypdf import PdfReader
    except ImportError:
        PdfReader = None

    if PdfReader is not None:
        lines = []
        for index, page in enumerate(PdfReader(path).pages, start=1):
            lines.append(f"=== 페이지 {index} ===")
            lines.append(page.extract_text() or "")
            lines.append("")
        return "\n".join(lines)

    if shutil.which("pdftotext"):
        completed = subprocess.run(
            ["pdftotext", "-layout", "-enc", "UTF-8", path, "-"],
            capture_output=True,
            check=True,
        )
        return completed.stdout.decode("utf-8", errors="replace")

    raise RuntimeError(
        "pdf를 추출할 도구가 없다. 'pip install pypdf'로 pypdf를 설치하거나 "
        "pdftotext(poppler)를 설치한다."
    )


EXTRACTORS = {
    ".docx": extract_docx,
    ".pptx": extract_pptx,
    ".xlsx": extract_xlsx,
    ".xlsm": extract_xlsx,
    ".pdf": extract_pdf,
}


def main():
    parser = argparse.ArgumentParser(description="기획안 파일을 텍스트로 추출한다.")
    parser.add_argument("file", help="xlsx, pptx, docx, pdf 파일")
    parser.add_argument("-o", "--output", help="출력 파일. 없으면 표준 출력")
    args = parser.parse_args()

    match = re.search(r"\.[^.\\/]+$", args.file)
    extension = match.group(0).lower() if match else ""
    extractor = EXTRACTORS.get(extension)
    if extractor is None:
        print(
            f"지원하지 않는 형식이다: {extension or '(확장자 없음)'}. "
            f"지원 형식: {', '.join(sorted(EXTRACTORS))}",
            file=sys.stderr,
        )
        return 2

    try:
        text = extractor(args.file)
    except FileNotFoundError:
        print(f"파일을 찾을 수 없다: {args.file}", file=sys.stderr)
        return 2
    except (zipfile.BadZipFile, KeyError, ET.ParseError) as error:
        print(f"파일을 읽지 못했다(손상됐거나 형식이 다르다): {error}", file=sys.stderr)
        return 2
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 2

    if not text.strip():
        print(
            "경고: 추출된 텍스트가 없다. 내용이 이미지로만 들어 있을 수 있다.",
            file=sys.stderr,
        )

    if args.output:
        with open(args.output, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
            if not text.endswith("\n"):
                handle.write("\n")
        print(f"{args.output} 에 {len(text.splitlines())}줄을 썼다.", file=sys.stderr)
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stdout.write(text)
        if not text.endswith("\n"):
            sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
