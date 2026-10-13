#!/usr/bin/env python3
"""Read the GSR Drop Box forms off granitestatereport.com and write or check forms.json.

The iOS app sends to the same drop box the web pages use
(https://granitestatereport.com/wp-json/gsr-drop/v1/). The server keys each
submission by its form name and stores the `data-k` fields the page sends, so
the app has to send the same form names, field keys and option values as the
pages. This script reads them from the live pages so the app's copy is never
typed by hand.

  python3 ios/tools/forms_from_site.py --write   # rebuild forms.json from the live pages
  python3 ios/tools/forms_from_site.py --check   # exit 1 if the live pages and forms.json differ
  python3 ios/tools/forms_from_site.py --html-dir DIR --check   # use saved pages instead

No third-party dependencies.
"""
import argparse
import html
import json
import os
import re
import sys
import urllib.request
from html.parser import HTMLParser

SITE = "https://granitestatereport.com"
API = SITE + "/wp-json/gsr-drop/v1/"
# (app id, page slug, path). "tips" is the quick tip box on the Send a Tip hub page; the
# next three are the hub's "doors". The last three pages carry the same "tips" box as the
# hub, so the server files them as tips; the app tells them apart by id, and the two
# sighting pages label every note the way the site's own script does (see sight_config).
PAGES = [
    ("tips", "tips", "/tips/"),
    ("story", "share-your-story", "/share-your-story/"),
    ("inside", "inside-the-building", "/inside-the-building/"),
    ("nothing", "nothing-to-see-here", "/nothing-to-see-here/"),
    ("research", "research-files", "/research-files/"),
    ("wildlife", "wildlife", "/wildlife/"),
    ("unexplained", "unexplained", "/unexplained/"),
]
# The sections of each page a sender is asked to read or accept before pressing Send.
# The app shows them word for word above its Send button and links to the full page.
READ_FIRST = {
    "tips": ["What you are agreeing to"],
    "share-your-story": ["What helps"],
    "inside-the-building": ["Protect yourself first", "What the law says about you speaking up",
                            "What Granite State Report promises, and what it cannot", "What you are agreeing to"],
    "nothing-to-see-here": ["Read this before you send anything", "Send what you have a right to have"],
    "research-files": ["What fits here"],
    "wildlife": ["What to send", "What you are agreeing to", "Keep your distance", "How GSR checks it",
                 "Other places to report"],
    "unexplained": ["What to send", "Check it yourself first, if you like", "What you are agreeing to",
                    "Before you film", "How GSR checks it", "Other places to report"],
}
# Sections the app shows at the top of the screen, before anything else: who to call first.
TOP = {
    "wildlife": ["Animal hurt, someone in danger, or a crime?"],
}
# Inline tags whose text runs on into the words around them. Every other tag is a break.
INLINE = r"a|abbr|b|cite|code|em|i|mark|q|s|small|span|strong|sub|sup|u"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "GSRKit", "forms.json"))
# The same JSON, compiled into GSRKit as a string so the app and the share extension
# never depend on a resource bundle being copied into the right place.
SWIFT_OUT = os.path.normpath(os.path.join(HERE, "..", "GSRKit", "Sources", "GSRKit", "FormsJSON.generated.swift"))
UA = "GSR-iOS-forms-check/1.0 (+https://github.com/dexterdow33/BlogPostPreviewer)"


def text_of(fragment):
    """Visible text of an HTML fragment, entities decoded, whitespace collapsed."""
    t = re.sub(r"<[^>]+>", " ", fragment)
    return re.sub(r"\s+", " ", html.unescape(t)).strip()


class BoxParser(HTMLParser):
    """Collects the one .gsrdb drop box on a page: its form name, labels, fields and button."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth = 0          # div depth inside the box; 0 = outside
        self.form = None
        self.fields = []
        self.labels = {}        # element id -> label text
        self.label_for = None
        self.label_text = []
        self.label_wraps = None  # a <label> that wraps a checkbox
        self.select = None
        self.option = None
        self.capture = None     # ("send"|"consent"|"main_label", [text])
        self.main_id = None
        self.send = None
        self.consent = None
        self.main_label = None
        self.in_hp = False
        self.in_noscript = False  # the box's <noscript> fallback line is not part of the form

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = (a.get("class") or "").split()
        if self.depth == 0:
            if tag == "div" and "gsrdb" in cls and a.get("data-form"):
                self.depth = 1
                self.form = a["data-form"]
            return
        if tag == "noscript":
            self.in_noscript = True
            return
        if tag == "div":
            self.depth += 1
            if "gsrdb-hp" in cls:
                self.in_hp = True
        if self.in_hp or self.in_noscript:
            return
        if tag == "label":
            self.label_for = a.get("for")
            self.label_text = []
            if "gsrdb-check" in cls:
                self.label_wraps = {"text": []}
        elif tag == "textarea" and "gsrdb-main" in cls:
            self.main_id = a.get("id")
        elif tag in ("input", "textarea") and a.get("data-k"):
            kind = "textarea" if tag == "textarea" else (a.get("type") or "text")
            field = {"key": a["data-k"], "kind": kind, "id": a.get("id")}
            if kind == "checkbox":
                field["default"] = False
                if self.label_wraps is not None:
                    self.label_wraps["field"] = field
            elif tag == "textarea" and a.get("rows"):
                field["rows"] = int(a["rows"])
            self.fields.append(field)
        elif tag == "select" and a.get("data-k"):
            self.select = {"key": a["data-k"], "kind": "select", "id": a.get("id"), "options": []}
            self.fields.append(self.select)
        elif tag == "option" and self.select is not None:
            self.option = {"value": a.get("value"), "selected": "selected" in a, "text": []}
        elif tag == "button" and "gsrdb-send" in cls:
            self.capture = ("send", [])
        elif tag == "p" and "gsrdb-consent" in cls:
            self.capture = ("consent", [])

    def handle_endtag(self, tag):
        if self.depth <= 0:
            return
        if tag == "noscript":
            self.in_noscript = False
            return
        if self.in_noscript:
            return
        if tag == "div":
            self.depth -= 1
            if self.in_hp:
                self.in_hp = False
            if self.depth == 0:
                self.depth = -1  # done; ignore the rest of the page
            return
        if self.in_hp:
            return
        if tag == "label":
            txt = re.sub(r"\s+", " ", "".join(self.label_text)).strip()
            if self.label_wraps is not None:
                f = self.label_wraps.get("field")
                if f is not None:
                    f["label"] = txt
                self.label_wraps = None
            elif self.label_for:
                self.labels[self.label_for] = txt
            self.label_for = None
            self.label_text = []
        elif tag == "option" and self.option is not None:
            label = re.sub(r"\s+", " ", "".join(self.option["text"])).strip()
            value = self.option["value"] if self.option["value"] is not None else label
            self.select["options"].append({"label": label, "value": value})
            if self.option["selected"]:
                self.select["default"] = value
            self.option = None
        elif tag == "select":
            if self.select is not None and "default" not in self.select:
                # A browser selects the first option when none is marked.
                self.select["default"] = self.select["options"][0]["value"] if self.select["options"] else ""
            self.select = None
        elif tag in ("button", "p") and self.capture:
            name, buf = self.capture
            if getattr(self, name) is None:  # first one wins
                setattr(self, name, re.sub(r"\s+", " ", "".join(buf)).strip())
            self.capture = None

    def handle_data(self, data):
        if self.depth <= 0 or self.in_hp or self.in_noscript:
            return
        if self.label_for is not None or self.label_wraps is not None:
            self.label_text.append(data)
        if self.option is not None:
            self.option["text"].append(data)
        if self.capture:
            self.capture[1].append(data)


def inline_text(fragment):
    """Visible text of a block: inline tags join their neighbors, so "RSA 275-E:2</a>," stays "RSA 275-E:2,"."""
    t = re.sub(r"</?(?:%s)\b[^>]*>" % INLINE, "", fragment)
    t = re.sub(r"<[^>]+>", " ", t)
    return re.sub(r"\s+", " ", html.unescape(t)).strip()


def links_of(fragment):
    """The block's links, as {text, url}, in order. Only web, phone and mail links; page anchors are dropped."""
    out = []
    for m in re.finditer(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', fragment, re.S):
        url = html.unescape(m.group(1))
        if url.startswith("/"):
            url = SITE + url
        if not re.match(r"(https?:|tel:|mailto:)", url):
            continue
        text = inline_text(m.group(2))
        if text:
            out.append({"text": text, "url": url})
    return out


def sections(page_html, headings):
    """Each named <h2> section as {heading, blocks:[{kind: p|li|box, text, links?}]}, up to the next
    <h2>, the drop box, or the end of the article."""
    out = []
    for want in headings:
        m = None
        for h2 in re.finditer(r"<h2[^>]*>(.*?)</h2>", page_html, re.S):
            if text_of(h2.group(1)) == want:
                m = h2
                break
        if not m:
            raise SystemExit(f"section not found: {want!r}")
        rest = page_html[m.end():]
        stop = min([i for i in (rest.find("<h2"), rest.find('<div class="gsrdb"'), rest.find("</article>")) if i >= 0]
                   or [len(rest)])
        body = rest[:stop]
        blocks = []
        # Paragraphs, list items, and the boxed callouts (div.gsr-statute-box), in page order.
        pat = r'<(p|li)\b[^>]*>(.*?)</\1>|<div class="[^"]*gsr-statute-box[^"]*"[^>]*>(.*?)</div>'
        for b in re.finditer(pat, body, re.S):
            kind, raw = (b.group(1), b.group(2)) if b.group(1) else ("box", b.group(3))
            t = inline_text(raw)
            # The app holds no browser storage; this line describes the website only.
            if t and not t.startswith("Files you drop on other pages of this site"):
                block = {"kind": kind, "text": t}
                links = links_of(raw)
                if links:
                    block["links"] = links
                blocks.append(block)
        out.append({"heading": want, "blocks": blocks})
    return out


def sight_config(page_html):
    """The site's sighting script (#gsr-sight-js): its page settings, the Send menu's entries for the
    sighting pages, and its own wording for the Quick details panel. None for pages without it."""
    m = re.search(r"window\.GSR_SIGHT\s*=\s*", page_html)
    if not m:
        return None
    conf, _ = json.JSONDecoder().raw_decode(page_html, m.end())
    script = page_html[m.end():page_html.find("</script>", m.end())]
    words = {}
    for name, cls in (("heading", "gsrq-h"), ("note", "gsrq-sub")):
        w = re.search(r"el\('p', '%s', '([^']*)'\)" % cls, script)
        if not w:
            raise SystemExit(f"sighting script: {cls} text not found")
        words[name] = w.group(1)
    if not re.search(r"lines\.push\('Sent from: ' \+ location\.pathname\)", script):
        raise SystemExit("sighting script: the note label changed; read #gsr-sight-js and update the app")
    return conf, words


def menu_entries(page_html):
    """The site's Send menu: page path -> {label, blurb}, from the Send Bar and the sighting script."""
    out = {}
    pop = page_html.find('id="gsr-sb-pop-upload"')
    if pop >= 0:
        end = page_html.find("</div>", pop)
        for a in re.finditer(r'<a href="([^"#]+)[^"]*">.*?<b>(.*?)</b><span>(.*?)</span></a>', page_html[pop:end], re.S):
            out[a.group(1).replace(SITE, "")] = {"label": text_of(a.group(2)), "blurb": text_of(a.group(3))}
    sight = sight_config(page_html)
    if sight:
        for e in sight[0].get("menu") or []:
            out[e["url"].split("#")[0].replace(SITE, "")] = {"label": e["b"], "blurb": e["s"]}
    return out


def page_meta(page_html):
    title = re.search(r'<h1[^>]*class="[^"]*gsr-title[^"]*"[^>]*>(.*?)</h1>', page_html, re.S)
    dek = re.search(r'<p[^>]*class="[^"]*gsr-dek[^"]*"[^>]*>(.*?)</p>', page_html, re.S)
    byline = re.search(r'<div[^>]*class="[^"]*gsr-byline[^"]*"[^>]*>(.*?)</div>', page_html, re.S)
    version = None
    if byline:
        m = re.search(r"Version\s+([0-9.]+)\s*·\s*([A-Z][a-z]+ \d{1,2}, \d{4})", text_of(byline.group(1)))
        if m:
            version = {"number": m.group(1), "date": m.group(2)}
    if not title:
        title = re.search(r"<title>(.*?)</title>", page_html, re.S)
    return {
        "title": text_of(title.group(1)).split(" – ")[0].split(" | ")[0] if title else None,
        "dek": text_of(dek.group(1)) if dek else None,
        "pageVersion": version,
    }


def parse_page(door, slug, path, page_html):
    p = BoxParser()
    p.feed(page_html)
    if not p.form:
        raise SystemExit(f"{slug}: no GSR Drop Box (.gsrdb[data-form]) on the page")
    fields = []
    for f in p.fields:
        out = {"key": f["key"], "kind": f["kind"], "label": f.get("label") or p.labels.get(f.get("id"), "")}
        if f["kind"] == "select":
            out["options"] = f["options"]
            out["default"] = f["default"]
        elif f["kind"] == "checkbox":
            out["default"] = False
        else:
            out["default"] = ""
            if f.get("rows"):
                out["rows"] = f["rows"]
        fields.append(out)
    meta = page_meta(page_html)
    entry = {
        "id": door,
        "form": p.form,
        "slug": slug,
        "pageURL": SITE + path,
        "title": meta["title"],
        "dek": meta["dek"],
        "pageVersion": meta["pageVersion"],
        "mainLabel": p.labels.get(p.main_id, ""),
        "sendLabel": p.send or "Send",
        "consent": p.consent,
        "topSections": sections(page_html, TOP.get(slug, [])),
        "readFirst": sections(page_html, READ_FIRST[slug]),
        "fields": fields,
    }
    # Pages whose "What to send" asks for the original file ("The original can carry the date,
    # the time, and the place"). The app starts their drafts with photo and video cleaning off.
    entry["asksForOriginals"] = any(b["text"].startswith("The original file")
                                    for sec in entry["readFirst"] for b in sec["blocks"])
    menu = menu_entries(page_html).get(path)
    if menu:
        entry["menu"] = menu
    sight = sight_config(page_html)
    page = sight[0].get("page") if sight else None
    if page:
        # What the site's script does to this page's box: new prompt and button words, the
        # tips box's own "where" field hidden (the panel asks "Where"), and a label plus the
        # quick details written at the top of the note on Send.
        if page.get("main"):
            entry["mainLabel"] = page["main"]
        if page.get("send"):
            entry["sendLabel"] = page["send"]
        entry["quick"] = {
            "heading": sight[1]["heading"],
            "note": sight[1]["note"],
            "tag": page["tag"],
            "chipsLabel": page.get("chipsLbl") or None,
            "chips": page.get("chips") or [],
            "fields": [{"key": f["k"], "label": f["label"], "placeholder": f.get("ph") or ""}
                       for f in page.get("fields") or []],
            "hiddenFields": [f["key"] for f in fields if f["key"] == "where"],
            "sentFrom": path,
        }
    return entry


def fetch(path):
    req = urllib.request.Request(SITE + path, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", "replace")


def build(html_dir=None):
    forms = []
    for door, slug, path in PAGES:
        if html_dir:
            with open(os.path.join(html_dir, slug + ".html"), encoding="utf-8") as fh:
                page = fh.read()
        else:
            page = fetch(path)
        forms.append(parse_page(door, slug, path, page))
    return {"api": API, "source": "Read from the live pages by ios/tools/forms_from_site.py", "forms": forms}


def comparable(doc):
    """What must match between the app and the site: everything the server or the reader sees."""
    return [
        {k: f.get(k) for k in ("id", "form", "pageURL", "mainLabel", "sendLabel", "consent", "topSections",
                               "readFirst", "fields", "quick", "menu", "asksForOriginals")}
        for f in doc["forms"]
    ]


def swift_source(json_text):
    if '"#' in json_text:
        raise SystemExit("forms.json contains the raw-string delimiter \"#; change the Swift delimiter")
    return (
        "// Generated by ios/tools/forms_from_site.py from ios/GSRKit/forms.json. Do not edit.\n"
        "// The GSR Drop Box forms as the live pages define them; see DropCatalog.\n\n"
        "let bundledFormsJSON = #\"\"\"\n" + json_text + "\"\"\"#\n"
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--write", action="store_true", help="rewrite forms.json from the pages")
    g.add_argument("--check", action="store_true", help="exit 1 if forms.json no longer matches the pages")
    ap.add_argument("--html-dir", help="read <slug>.html files from this folder instead of the site")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()

    if args.write:
        live = build(args.html_dir)
        text = json.dumps(live, indent=2, ensure_ascii=False) + "\n"
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text)
        wrote = [args.out]
        if os.path.abspath(args.out) == OUT:  # the Swift copy only ever mirrors the app's own forms.json
            with open(SWIFT_OUT, "w", encoding="utf-8") as fh:
                fh.write(swift_source(text))
            wrote.append(SWIFT_OUT)
        print(f"Wrote {' and '.join(wrote)}: " + ", ".join(f"{f['id']} ({len(f['fields'])} fields)" for f in live["forms"]))
        return 0
    with open(args.out, encoding="utf-8") as fh:
        raw = fh.read()
        saved = json.loads(raw)
    with open(SWIFT_OUT, encoding="utf-8") as fh:
        if os.path.abspath(args.out) == OUT and fh.read() != swift_source(raw):
            print(f"{SWIFT_OUT} is out of step with {args.out}. Run --write.")
            return 1
    live = build(args.html_dir)
    a, b = comparable(saved), comparable(live)
    if a == b:
        print("forms.json matches the live drop box pages.")
        return 0
    print("forms.json no longer matches the live pages. Run --write, review the diff, and ship an app update.")
    for x, y in zip(a, b):
        if x != y:
            print(f"--- app  {x['id']}\n{json.dumps(x, indent=1, ensure_ascii=False)}")
            print(f"+++ site {y['id']}\n{json.dumps(y, indent=1, ensure_ascii=False)}")
    if len(a) != len(b):
        print(f"Form count differs: app {len(a)}, site {len(b)}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
