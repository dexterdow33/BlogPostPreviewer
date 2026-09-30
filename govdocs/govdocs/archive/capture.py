"""Turn an HTML-only government document (an RSA chapter, a press release)
into a plain-text file the archive can host. The text is the page's own
words; nothing is summarized or rewritten."""

import re
from html.parser import HTMLParser

SKIP = {"script", "style", "noscript", "nav", "header", "footer", "aside",
        "form", "button", "svg", "iframe"}
BLOCK = {"p", "div", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6", "tr",
         "section", "article", "main", "blockquote", "pre", "table", "center"}


class _Text(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = {"main": [], "article": [], "body": []}
        self.skip = 0
        self.inside = {"main": 0, "article": 0, "body": 0}
        self.title = ""
        self._in_title = False

    def handle_starttag(self, tag, attrs):
        if tag in SKIP:
            self.skip += 1
        if tag in self.inside:
            self.inside[tag] += 1
        if tag == "title":
            self._in_title = True
        if tag in BLOCK:
            self._emit("\n")

    def handle_endtag(self, tag):
        if tag in SKIP and self.skip:
            self.skip -= 1
        if tag in self.inside and self.inside[tag]:
            self.inside[tag] -= 1
        if tag == "title":
            self._in_title = False
        if tag in BLOCK:
            self._emit("\n")

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        if not self.skip:
            self._emit(data)

    def _emit(self, s):
        for k, depth in self.inside.items():
            if depth:
                self.parts[k].append(s)


def html_to_text(html):
    """Return (page_title, text). Prefers <main>, then <article>, then <body>."""
    p = _Text()
    p.feed(html)
    for key in ("main", "article", "body"):
        text = "".join(p.parts[key])
        if len(text.strip()) > 200:
            break
    else:
        text = "".join(p.parts["body"]) or "".join(p.parts["main"])
    lines = [re.sub(r"[ \t ]+", " ", ln).strip() for ln in text.splitlines()]
    out, blank = [], False
    for ln in lines:
        if ln:
            out.append(ln)
            blank = False
        elif not blank and out:
            out.append("")
            blank = True
    return " ".join(p.title.split()), "\n".join(out).strip()


def capture(html, url, retrieved):
    """Plain-text capture with a provenance header."""
    title, body = html_to_text(html)
    header = [
        title or url,
        "",
        f"Source: {url}",
        f"Retrieved: {retrieved}",
        "Text capture of the web page as published by the source. "
        "Page navigation and scripts removed; wording unchanged.",
        "=" * 72,
        "",
    ]
    return "\n".join(header) + body + "\n"
