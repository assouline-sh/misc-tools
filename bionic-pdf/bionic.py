#!/usr/bin/env python3
"""Convert a PDF into a bionic-reading PDF.

Reads the input PDF's text, bolds the first ~half of each word
(more letters for longer words), and writes a new PDF. The original
visual layout is not preserved — text is reflowed onto letter-size pages.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import fitz  # PyMuPDF
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import PageBreak, Paragraph, SimpleDocTemplate, Spacer

WORD_RE = re.compile(r"[A-Za-z][A-Za-z']*")
TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z']*|[^A-Za-z]+", re.DOTALL)


def bold_prefix_len(word: str) -> int:
    n = len(word)
    if n <= 1:
        return 1
    if n <= 3:
        return 1
    if n == 4:
        return 2
    if n <= 6:
        return 3
    return (n + 1) // 2


def escape_xml(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def bionic_markup(text: str) -> str:
    out: list[str] = []
    for tok in TOKEN_RE.findall(text):
        if WORD_RE.fullmatch(tok):
            n = bold_prefix_len(tok)
            out.append(f"<b>{escape_xml(tok[:n])}</b>{escape_xml(tok[n:])}")
        else:
            esc = escape_xml(tok).replace("\n", "<br/>")
            out.append(esc)
    return "".join(out)


def extract_pages(pdf_path: Path) -> list[str]:
    doc = fitz.open(pdf_path)
    try:
        return [page.get_text("text") for page in doc]
    finally:
        doc.close()


def build_pdf(pages: list[str], out_path: Path) -> None:
    doc = SimpleDocTemplate(
        str(out_path),
        pagesize=letter,
        leftMargin=0.75 * inch,
        rightMargin=0.75 * inch,
        topMargin=0.75 * inch,
        bottomMargin=0.75 * inch,
        title=out_path.stem,
    )
    style = ParagraphStyle(
        name="bionic",
        fontName="Helvetica",
        fontSize=11,
        leading=15,
        alignment=TA_LEFT,
    )
    story: list = []
    for i, text in enumerate(pages):
        paragraphs = re.split(r"\n\s*\n", text.strip())
        for para in paragraphs:
            if not para.strip():
                continue
            story.append(Paragraph(bionic_markup(para), style))
            story.append(Spacer(1, 6))
        if i < len(pages) - 1:
            story.append(PageBreak())
    doc.build(story)


def main() -> int:
    p = argparse.ArgumentParser(description="Convert a PDF into a bionic-reading PDF.")
    p.add_argument("input", type=Path, help="Input PDF file")
    p.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Output PDF (default: <input>.bionic.pdf next to the input)",
    )
    args = p.parse_args()

    if not args.input.exists():
        print(f"Input not found: {args.input}", file=sys.stderr)
        return 1

    out = args.output or args.input.with_suffix(".bionic.pdf")
    pages = extract_pages(args.input)
    if not pages:
        print("No pages extracted from input.", file=sys.stderr)
        return 1
    build_pdf(pages, out)
    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
