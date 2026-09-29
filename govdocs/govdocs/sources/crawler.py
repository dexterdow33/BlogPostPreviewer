"""Generic polite crawler for government sites without a documents API
(New Hampshire state sites, mainly).

For each seed it reads robots.txt, walks any sitemaps it lists (or
/sitemap.xml), then does a bounded breadth-first crawl of HTML pages on
the allowed domains. It records links to document files (PDF, Word,
Excel, etc.); it does not download them unless you run `download`.
"""

import gzip
import json
import logging
import os
import re
import xml.etree.ElementTree as ET
from collections import deque
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit, urlunsplit, unquote

import requests

from ..http import RobotsDisallowed
from ..models import Document
from .base import Source

log = logging.getLogger(__name__)

DOC_EXTENSIONS = {".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
                  ".rtf", ".txt", ".csv", ".odt", ".ods", ".zip"}
SKIP_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".svg", ".webp", ".ico",
                   ".css", ".js", ".mp3", ".mp4", ".mov", ".wav", ".woff",
                   ".woff2", ".ttf", ".xml", ".json", ".ics"}
DEFAULT_SEEDS = os.path.join(os.path.dirname(__file__), "..", "seeds", "nh.json")


class LinkParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.links = []          # (href, anchor text)
        self.title = ""
        self._href = None
        self._text = []
        self._in_title = False

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            href = dict(attrs).get("href")
            if href:
                self._href, self._text = href, []
        elif tag == "title":
            self._in_title = True

    def handle_endtag(self, tag):
        if tag == "a" and self._href is not None:
            self.links.append((self._href, " ".join("".join(self._text).split())))
            self._href = None
        elif tag == "title":
            self._in_title = False

    def handle_data(self, data):
        if self._href is not None:
            self._text.append(data)
        if self._in_title:
            self.title += data


def normalize(url):
    """Drop fragments and default ports; keep the query (many CMSs need it)."""
    p = urlsplit(url)
    if p.scheme not in ("http", "https"):
        return None
    netloc = p.netloc.lower()
    if netloc.endswith(":80") or netloc.endswith(":443"):
        netloc = netloc.rsplit(":", 1)[0]
    return urlunsplit((p.scheme.lower(), netloc, p.path or "/", p.query, ""))


def ext_of(url):
    return os.path.splitext(unquote(urlsplit(url).path))[1].lower()


def host_allowed(url, domains):
    host = urlsplit(url).hostname or ""
    return any(host == d or host.endswith("." + d) for d in domains)


def load_seeds(path):
    with open(path) as fh:
        data = json.load(fh)
    return data["seeds"]


class Crawler(Source):
    name = "nh-crawl"
    jurisdiction = "nh"
    description = ("Crawl NH state sites in seeds/nh.json (robots.txt obeyed) "
                   "and index linked PDF/Word/Excel files")

    def __init__(self, store=None):
        self.store = store

    def iter_documents(self, client, opts):
        seeds = load_seeds(opts.seeds_file or DEFAULT_SEEDS)
        n = 0
        for seed in seeds:
            for doc in self.crawl_seed(client, seed, opts):
                yield doc
                n += 1
                if opts.limit and n >= opts.limit:
                    return

    # ------------------------------------------------------------------
    def crawl_seed(self, client, seed, opts):
        domains = [d.lower() for d in seed["allowed_domains"]]
        agency = seed.get("name")
        found = set()
        queue = deque()
        queued = set()

        def enqueue(url, depth):
            url = normalize(url)
            if not url or url in queued or not host_allowed(url, domains):
                return
            queued.add(url)
            queue.append((url, depth))

        for start in seed["start_urls"]:
            enqueue(start, 0)
            if seed.get("use_sitemaps", True):
                for page_url, lastmod in self.sitemap_urls(client, start):
                    if ext_of(page_url) in DOC_EXTENSIONS:
                        doc = self._doc(page_url, None, agency, start, lastmod)
                        if doc and doc.doc_id not in found and host_allowed(page_url, domains):
                            found.add(doc.doc_id)
                            yield doc
                    else:
                        enqueue(page_url, 1)

        pages = 0
        while queue and pages < opts.max_pages:
            url, depth = queue.popleft()
            if opts.resume and self.store is not None and self.store.seen(url):
                continue
            try:
                resp = client.get(url, check_robots=True)
            except RobotsDisallowed:
                log.info("robots.txt disallows %s", url)
                continue
            except requests.RequestException as exc:
                log.warning("skip %s: %s", url, exc)
                continue
            pages += 1
            if self.store is not None:
                self.store.mark_seen(url)
            final = normalize(resp.url) or url
            if "html" not in resp.headers.get("Content-Type", ""):
                continue
            parser = LinkParser()
            try:
                parser.feed(resp.text)
            except Exception as exc:   # malformed HTML should not stop a crawl
                log.warning("parse error %s: %s", url, exc)
                continue
            for href, text in parser.links:
                target = normalize(urljoin(final, href.strip()))
                if not target or not host_allowed(target, domains):
                    continue
                ext = ext_of(target)
                if ext in DOC_EXTENSIONS:
                    if target not in found:
                        found.add(target)
                        doc = self._doc(target, text, agency, final, None)
                        if doc:
                            yield doc
                elif ext not in SKIP_EXTENSIONS and depth < opts.max_depth:
                    enqueue(target, depth + 1)
        log.info("%s: crawled %d pages, %d documents", agency, pages, len(found))

    # ------------------------------------------------------------------
    def sitemap_urls(self, client, start_url, max_sitemaps=50):
        """Yield (loc, lastmod) from robots.txt sitemaps or /sitemap.xml."""
        p = urlsplit(start_url)
        todo = list(client.sitemaps(start_url)) or [f"{p.scheme}://{p.netloc}/sitemap.xml"]
        done = set()
        while todo and len(done) < max_sitemaps:
            sm = todo.pop(0)
            if sm in done:
                continue
            done.add(sm)
            try:
                resp = client.get(sm, check_robots=True)
            except (RobotsDisallowed, requests.RequestException) as exc:
                log.info("sitemap %s unavailable: %s", sm, exc)
                continue
            body = resp.content
            if sm.endswith(".gz") or body[:2] == b"\x1f\x8b":
                try:
                    body = gzip.decompress(body)
                except OSError:
                    continue
            try:
                root = ET.fromstring(body)
            except ET.ParseError:
                continue
            tag = root.tag.split("}")[-1]
            for node in root:
                loc = lastmod = None
                for child in node:
                    name = child.tag.split("}")[-1]
                    if name == "loc":
                        loc = (child.text or "").strip()
                    elif name == "lastmod":
                        lastmod = (child.text or "").strip()[:10] or None
                if not loc:
                    continue
                if tag == "sitemapindex":
                    todo.append(loc)
                else:
                    yield loc, lastmod

    def _doc(self, url, text, agency, found_on, lastmod):
        url = normalize(url)
        if not url:
            return None
        filename = unquote(os.path.basename(urlsplit(url).path))
        title = text if text and not re.fullmatch(r"(?i)(download|pdf|here|click here|view)", text) else filename
        return Document(
            source=self.name,
            doc_id=url,
            title=title,
            url=url,
            download_url=url,
            jurisdiction=self.jurisdiction,
            doc_type=ext_of(url).lstrip(".") or None,
            agency=agency,
            published=lastmod,
            extra={"found_on": found_on, "host": urlsplit(url).hostname},
        )
