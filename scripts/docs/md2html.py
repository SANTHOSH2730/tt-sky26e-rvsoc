#!/usr/bin/env python3
"""Convert a Markdown document to a print-ready HTML page (A4, page numbers),
for printing to PDF with a Chromium browser (see make_pdf.sh).

usage: md2html.py <in.md> <out.html> [title]
Needs markdown-it-py (installed in the TT tools venv)."""
import html
import os
import re
import sys

from markdown_it import MarkdownIt

CSS = """
@page { size: A4; margin: 18mm 17mm 20mm 17mm;
        @bottom-center { content: counter(page) " / " counter(pages); font: 9pt Georgia, serif; color: #555; } }
html { font: 10.5pt/1.42 Georgia, 'Times New Roman', serif; color: #111; }
body { max-width: 100%; margin: 0; }
h1 { font-size: 18pt; line-height: 1.25; margin: 0 0 8pt; }
h2 { font-size: 14pt; margin: 18pt 0 6pt; border-bottom: 1px solid #999; padding-bottom: 2pt; break-after: avoid; }
h3 { font-size: 11.5pt; margin: 12pt 0 4pt; break-after: avoid; }
p, li { text-align: justify; hyphens: auto; }
code { font: 8.6pt Consolas, 'DejaVu Sans Mono', monospace; background: #f3f3f3; padding: 0 2px; }
pre { background: #f6f6f6; border: 1px solid #ddd; padding: 6pt 8pt; overflow: hidden;
      white-space: pre-wrap; break-inside: avoid; }
pre code { background: none; padding: 0; font-size: 8.2pt; line-height: 1.3; }
table { border-collapse: collapse; width: 100%; margin: 6pt 0 10pt; font-size: 8.8pt; line-height: 1.3; }
th, td { border: 1px solid #aaa; padding: 2.5pt 4pt; vertical-align: top; text-align: left; }
th { background: #e9edf2; }
tr { break-inside: avoid; }
img { max-width: 100%; display: block; margin: 6pt auto 2pt; break-inside: avoid; }
blockquote { margin: 6pt 0; padding: 4pt 10pt; border-left: 3px solid #889; background: #f7f7fa; }
hr { border: none; border-top: 1px solid #ccc; margin: 12pt 0; }
em { color: #333; }
"""


def main():
    src, out = sys.argv[1], sys.argv[2]
    text = open(src, encoding="utf-8").read()
    title = sys.argv[3] if len(sys.argv) > 3 else (re.search(r"^# (.+)$", text, re.M) or [None, os.path.basename(src)])[1]
    md = MarkdownIt("commonmark", {"html": True, "typographer": False}).enable("table").enable("strikethrough")
    body = md.render(text)
    doc = (f"<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
           f"<title>{html.escape(title)}</title><style>{CSS}</style></head>\n<body>\n{body}\n</body></html>\n")
    open(out, "w", encoding="utf-8").write(doc)
    print("wrote", out)


if __name__ == "__main__":
    main()
