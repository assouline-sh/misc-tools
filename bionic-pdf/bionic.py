#!/usr/bin/env python3
"""Convert a PDF into a bionic-reading PDF.

Bolds the first half-ish of every word in a PDF to help with
speed reading. Works in-place on the original layout so you
keep all your images, formatting, etc.
"""
from __future__ import annotations

import argparse
import ctypes
import os
import re
import subprocess
import sys
from pathlib import Path

# pymupdf ships native extensions that link against libstdc++, but on
# NixOS it's buried in /nix/store and the linker can't find it. so we
# hunt it down, set LD_LIBRARY_PATH, and re-exec before anything else
# loads. the env var guard prevents an infinite loop.
def _needs_libstdcpp_fix() -> bool:
    try:
        ctypes.CDLL("libstdc++.so.6")
        return False
    except OSError:
        return True

if "_BIONIC_REEXEC" not in os.environ and _needs_libstdcpp_fix():
    _hits = subprocess.run(
        ["find", "/nix/store", "-maxdepth", "2", "-name", "libstdc++.so.6", "-type", "f"],
        capture_output=True, text=True, timeout=5,
    ).stdout.strip().splitlines()
    if _hits:
        _lib_dir = str(Path(_hits[0]).parent)
        os.environ["LD_LIBRARY_PATH"] = _lib_dir + ":" + os.environ.get("LD_LIBRARY_PATH", "")
        os.environ["_BIONIC_REEXEC"] = "1"
        os.execv(sys.executable, [sys.executable] + sys.argv)

import pymupdf  # PyMuPDF

WORD_RE = re.compile(r"[A-Za-z][A-Za-z']+")
# splits text into words vs everything else (punctuation, spaces, etc)
TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z']+|[^A-Za-z]+|[A-Za-z]", re.DOTALL)


def bold_prefix_len(word: str) -> int:
    """How many chars to bold. Longer words get proportionally more."""
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


def process_page(page: pymupdf.Page) -> None:
    text_dict = page.get_text("dict", flags=pymupdf.TEXT_PRESERVE_WHITESPACE)

    # grab everything we need from every text span first, because we're
    # about to nuke all the text off the page with redactions
    spans_info: list[dict] = []
    for block in text_dict["blocks"]:
        if block["type"] != 0:  # 0 = text, 1 = image
            continue
        for line in block["lines"]:
            for span in line["spans"]:
                text = span["text"]
                if not text.strip():
                    continue
                spans_info.append({
                    "bbox": pymupdf.Rect(span["bbox"]),
                    "text": text,
                    "size": span["size"],
                    "color": span["color"],
                    "origin": span["origin"],
                    "flags": span["flags"],
                })

    if not spans_info:
        return

    # wipe the original text but leave images/backgrounds alone
    for sp in spans_info:
        page.add_redact_annot(sp["bbox"])
    page.apply_redactions(images=pymupdf.PDF_REDACT_IMAGE_NONE)

    # now put it all back, but with bold prefixes on each word.
    # each span gets its own TextWriter so we can set color per-span
    normal_font = pymupdf.Font("helv")
    bold_font = pymupdf.Font("hebo")

    for sp in spans_info:
        text = sp["text"]
        fontsize = sp["size"]

        # color comes as a single int (0xRRGGBB), need to unpack it
        color_int = sp["color"]
        color = (
            (color_int >> 16 & 0xFF) / 255.0,
            (color_int >> 8 & 0xFF) / 255.0,
            (color_int & 0xFF) / 255.0,
        )
        origin = pymupdf.Point(sp["origin"])
        is_bold = bool(sp["flags"] & (1 << 4))  # bit 4 in span flags = bold

        tw = pymupdf.TextWriter(page.rect)
        x, y = origin.x, origin.y

        if is_bold or not WORD_RE.search(text):
            # already bold or just punctuation/numbers — put it back as-is
            font = bold_font if is_bold else normal_font
            tw.append(pymupdf.Point(x, y), text, font=font, fontsize=fontsize)
        else:
            # walk through each token, bolding the prefix of actual words
            for match in TOKEN_RE.finditer(text):
                token = match.group()
                if WORD_RE.fullmatch(token):
                    n = bold_prefix_len(token)
                    prefix, suffix = token[:n], token[n:]

                    # bold the first chunk
                    pos = tw.append(pymupdf.Point(x, y), prefix, font=bold_font, fontsize=fontsize)
                    x = pos[1].x  # append returns (rect, end_point)

                    # rest of the word in normal weight
                    if suffix:
                        pos = tw.append(pymupdf.Point(x, y), suffix, font=normal_font, fontsize=fontsize)
                        x = pos[1].x
                else:
                    # whitespace, punctuation, digits — just pass through
                    pos = tw.append(pymupdf.Point(x, y), token, font=normal_font, fontsize=fontsize)
                    x = pos[1].x

        tw.write_text(page, color=color)


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

    doc = pymupdf.open(args.input)
    for page_num, page in enumerate(doc):
        process_page(page)
        print(f"  Processed page {page_num + 1}/{len(doc)}", file=sys.stderr)
    doc.save(str(out), garbage=4, deflate=True)
    doc.close()
    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
