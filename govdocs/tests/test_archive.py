import json
import os
import re
import tempfile
import unittest
from datetime import date

from govdocs.archive import publish as pub
from govdocs.archive.capture import capture, html_to_text
from govdocs.archive.classify import classify, load_rules, slugify
from govdocs.models import Document
from govdocs.sources.base import Options
from govdocs.sources.crawler import Crawler
from govdocs.store import Store

from test_sources import FakeResponse, client_for

RULES = load_rules()


def row(**kw):
    base = dict(source="nh-crawl", doc_id="u", title="T", url="https://x.nh.gov/a.pdf",
                agency="", doc_type="pdf", jurisdiction="nh", extra="{}",
                published=None, download_url="https://x.nh.gov/a.pdf", local_path=None)
    base.update(kw)
    if isinstance(base["extra"], dict):
        base["extra"] = json.dumps(base["extra"])
    return base


class ClassifyTest(unittest.TestCase):
    def test_seed_series(self):
        c = classify(row(agency="NH Revised Statutes Annotated (RSA)", doc_type="html",
                         extra={"archive_series": {"slug": "rsa", "label": "RSA"}}), RULES)
        self.assertEqual((c["slug"], c["juris"]), ("rsa", "NH"))

    def test_rule_beats_seed(self):
        c = classify(row(title="Executive Order 2026-03", agency="Office of the Governor",
                         url="https://www.governor.nh.gov/sites/eo.pdf",
                         extra={"host": "www.governor.nh.gov",
                                "archive_series": {"slug": "governor-press", "label": "x"}}), RULES)
        self.assertEqual(c["slug"], "governor-executive-orders")

    def test_api_sources(self):
        self.assertEqual(classify(row(source="federalregister", jurisdiction="federal"), RULES)["slug"],
                         "federal-register")
        self.assertEqual(classify(row(source="govinfo", doc_id="BILLS-119hr1ih",
                                      jurisdiction="federal"), RULES)["slug"], "congress-bills")
        nh = classify(row(source="courtlistener", agency="nh"), RULES)
        self.assertEqual((nh["slug"], nh["juris"]), ("nh-supreme-court", "NH"))
        self.assertEqual(classify(row(source="courtlistener", agency="nhd",
                                      jurisdiction="federal"), RULES)["juris"], "US")

    def test_fallbacks_create_new_series(self):
        c = classify(row(agency="NH Secretary of State"), RULES)
        self.assertEqual((c["slug"], c["label"]), ("nh-secretary-of-state", "NH Secretary of State"))
        c = classify(row(agency="sweep", extra={"host": "www.dhhs.nh.gov",
                                                 "classify_by_host": True}), RULES)
        self.assertEqual((c["slug"], c["label"]), ("www-dhhs-nh-gov", "Documents from www.dhhs.nh.gov"))
        self.assertEqual(slugify("  Weird / Name!! "), "weird-name")


class TagTest(unittest.TestCase):
    PAGE_PARSE = re.compile(r"\s+(?=\w+=)")   # the archive page's own token split

    def test_tag_round_trips_through_page_grammar(self):
        c = {"slug": "governor-press", "label": "Governor's [press] releases", "juris": "NH",
             "agency": "Office of the Governor"}
        tag = pub.archive_tag(c, "https://www.governor.nh.gov/news/x?page=2", "2026-09-01T00:00")
        inner = re.match(r"\[archive(.*)\]$", tag).group(1).strip()
        toks = dict(t.split("=", 1) for t in self.PAGE_PARSE.split(inner))
        self.assertEqual(toks["tier"], "governor-press")
        self.assertEqual(toks["series"], "Governor's press releases")
        self.assertEqual(toks["agency"], "Office of the Governor")
        self.assertEqual(toks["date"], "2026-09-01")
        self.assertEqual(toks["src"], "https://www.governor.nh.gov/news/x?page=2")

    def test_values_cannot_inject_keys(self):
        c = {"slug": "s", "label": "a tier=records b", "juris": "US", "agency": ""}
        inner = pub.archive_tag(c, "https://x", None)[len("[archive "):-1]
        keys = [t.split("=", 1)[0] for t in self.PAGE_PARSE.split(inner)]
        self.assertEqual(keys.count("tier"), 1)

    def test_public_url_strips_keys(self):
        self.assertEqual(pub.public_url("https://api.govinfo.gov/p/X/pdf?api_key=SECRET&a=1"),
                         "https://api.govinfo.gov/p/X/pdf?a=1")


class CaptureTest(unittest.TestCase):
    HTML = """<html><head><title>Chapter 91-A ACCESS TO GOVERNMENTAL RECORDS</title>
      <script>var x=1;</script></head><body><nav>Home | Menu</nav>
      <main><h1>Governor Signs Bill</h1><p>CONCORD, NH &ndash; Today   the Governor
      signed&nbsp;HB 1.</p><p>Second paragraph.</p></main><footer>Contact</footer></body></html>"""

    def test_main_text_only(self):
        title, text = html_to_text(self.HTML.replace("Second paragraph.", "x " * 120))
        self.assertEqual(title, "Chapter 91-A ACCESS TO GOVERNMENTAL RECORDS")
        self.assertIn("CONCORD, NH – Today the Governor", text)
        self.assertNotIn("Menu", text)
        self.assertNotIn("var x", text)

    def test_capture_header(self):
        out = capture(self.HTML, "https://gc.nh.gov/rsa/html/vi/91-a/91-a-mrg.htm", "2026-09-30")
        self.assertTrue(out.startswith("Chapter 91-A ACCESS TO GOVERNMENTAL RECORDS\n"))
        self.assertIn("Source: https://gc.nh.gov/rsa/html/vi/91-a/91-a-mrg.htm", out)
        self.assertIn("Second paragraph.", out)   # short pages fall back to <body>


class DocPageCrawlTest(unittest.TestCase):
    SITE = {
        "https://gc.nh.gov/robots.txt": "",
        "https://gc.nh.gov/rsa/html/NHTOC.htm": '<a href="NHTOC-VI.htm">Title VI</a><a href="/about">x</a>',
        "https://gc.nh.gov/rsa/html/NHTOC-VI.htm": '<a href="VI/91-A/91-A-mrg.htm">Chapter 91-A</a>',
    }

    def handler(self, url, params):
        if url in self.SITE:
            return FakeResponse(url, 200, self.SITE[url], {"Content-Type": "text/html"})
        return FakeResponse(url, 404, "")

    def test_document_pages_and_follow(self):
        seed = {"name": "RSA", "start_urls": ["https://gc.nh.gov/rsa/html/NHTOC.htm"],
                "allowed_domains": ["gc.nh.gov"], "use_sitemaps": False,
                "follow_patterns": ["/rsa/html/"],
                "document_page_patterns": ["/rsa/html/[^/]+/[^/]+/[^/]+-mrg\\.htm$"],
                "archive_series": {"slug": "rsa", "label": "RSA"}}
        c = client_for(self.handler)
        opts = Options(since=date(2026, 1, 1), until=date(2026, 1, 1))
        docs = list(Crawler().crawl_seed(c, seed, opts))
        self.assertEqual([d.url for d in docs], ["https://gc.nh.gov/rsa/html/VI/91-A/91-A-mrg.htm"])
        self.assertEqual(docs[0].doc_type, "html")
        self.assertEqual(docs[0].extra["archive_series"]["slug"], "rsa")
        fetched = [u for u, _, _ in c.session.calls]
        self.assertNotIn("https://gc.nh.gov/about", fetched)          # outside follow_patterns
        self.assertNotIn("https://gc.nh.gov/rsa/html/VI/91-A/91-A-mrg.htm", fetched)  # recorded, not crawled


class FakeWP:
    def __init__(self):
        self.items, self.updates = {}, {}

    def find_by_checksum(self, sha):
        return [m for m in self.items.values() if sha in m["sha"]]

    def upload(self, path, filename):
        mid = 9000 + len(self.items)
        with open(path, "rb") as fh:
            import hashlib
            sha = hashlib.sha256(fh.read()).hexdigest()
        self.items[mid] = {"id": mid, "source_url": f"https://gsr/{filename}", "sha": sha}
        return self.items[mid]

    def update(self, mid, **fields):
        self.updates[mid] = fields


class PublishTest(unittest.TestCase):
    def test_publish_html_and_pdf_then_idempotent(self):
        pages = {
            "https://gc.nh.gov/robots.txt": ("", "text/plain"),
            "https://gc.nh.gov/rsa/html/vi/91-a/91-a-mrg.htm":
                ("<title>Chapter 91-A ACCESS</title><body><p>" + "text " * 80 + "</p></body>", "text/html"),
            "https://www.sos.nh.gov/robots.txt": ("", "text/plain"),
            "https://www.sos.nh.gov/a.pdf": ("%PDF-1.4 fake", "application/pdf"),
            "https://api.govinfo.gov/packages/BILLS-1/summary?api_key=DEMO_KEY":
                (json.dumps({"download": {"pdfLink": "https://api.govinfo.gov/packages/BILLS-1/pdf"}}), "application/json"),
            "https://api.govinfo.gov/packages/BILLS-1/pdf?api_key=DEMO_KEY": ("%PDF bill", "application/pdf"),
        }

        def handler(url, params):
            body, ctype = pages.get(url, ("", "text/plain"))
            return FakeResponse(url, 200 if url in pages else 404, body, {"Content-Type": ctype})

        with tempfile.TemporaryDirectory() as d:
            s = Store(os.path.join(d, "t.sqlite"))
            s.upsert(Document("nh-crawl", "https://gc.nh.gov/rsa/html/vi/91-a/91-a-mrg.htm",
                              "91-a-mrg.htm", "https://gc.nh.gov/rsa/html/vi/91-a/91-a-mrg.htm", "nh",
                              download_url="https://gc.nh.gov/rsa/html/vi/91-a/91-a-mrg.htm",
                              doc_type="html", agency="RSA",
                              extra={"archive_series": {"slug": "rsa", "label": "RSA"}}))
            s.upsert(Document("nh-crawl", "https://www.sos.nh.gov/a.pdf", "Annual report",
                              "https://www.sos.nh.gov/a.pdf", "nh", download_url="https://www.sos.nh.gov/a.pdf",
                              doc_type="pdf", agency="NH Secretary of State"))
            s.upsert(Document("govinfo", "BILLS-1", "A bill", "https://www.govinfo.gov/app/details/BILLS-1",
                              "federal", extra={"packageLink": "https://api.govinfo.gov/packages/BILLS-1/summary"}))
            s.upsert(Document("congress", "119-hr-1", "HR 1", "https://www.congress.gov/x", "federal"))
            s.commit()
            os.environ.pop("GOVINFO_API_KEY", None)
            os.environ.pop("DATA_GOV_API_KEY", None)
            wp = FakeWP()
            client = client_for(handler)
            done, failed = pub.publish(s, client, wp, RULES, out_dir=d)
            self.assertEqual((done, failed), (3, 0))   # congress row has no file
            caps = {f["title"]: f["caption"] for f in wp.updates.values()}
            self.assertIn("Chapter 91-A ACCESS", caps)     # page title replaced the filename
            self.assertIn("tier=rsa", caps["Chapter 91-A ACCESS"])
            self.assertIn("tier=nh-secretary-of-state", caps["Annual report"])
            self.assertIn("tier=congress-bills", caps["A bill"])
            for f in wp.updates.values():
                self.assertNotIn("DEMO_KEY", f["caption"] + f["description"])
            # Second run publishes nothing new.
            self.assertEqual(pub.publish(s, client, wp, RULES, out_dir=d), (0, 0))
            summary = pub.summarize(pub.plan(s, RULES))
            self.assertEqual(summary[("rsa", "RSA")]["archived"], 1)
            s.close()

    def test_remote_duplicate_is_not_reuploaded(self):
        pages = {"https://www.sos.nh.gov/robots.txt": ("", "text/plain"),
                 "https://www.sos.nh.gov/a.pdf": ("%PDF same", "application/pdf")}

        def handler(url, params):
            body, ctype = pages.get(url, ("", "text/plain"))
            return FakeResponse(url, 200 if url in pages else 404, body, {"Content-Type": ctype})

        with tempfile.TemporaryDirectory() as d:
            wp = FakeWP()
            for n in (1, 2):   # two fresh local databases, same remote library
                s = Store(os.path.join(d, f"{n}.sqlite"))
                s.upsert(Document("nh-crawl", "https://www.sos.nh.gov/a.pdf", "R",
                                  "https://www.sos.nh.gov/a.pdf", "nh",
                                  download_url="https://www.sos.nh.gov/a.pdf", doc_type="pdf", agency="SOS"))
                pub.publish(s, client_for(handler), wp, RULES, out_dir=os.path.join(d, str(n)))
                s.close()
            self.assertEqual(len(wp.items), 1)


class StoreMergeTest(unittest.TestCase):
    def test_extra_is_merged(self):
        with tempfile.TemporaryDirectory() as d:
            s = Store(os.path.join(d, "t.sqlite"))
            s.upsert(Document("nh-crawl", "u", "T", "u", "nh", extra={"archive_series": {"slug": "g"}}))
            s.upsert(Document("nh-crawl", "u", "T", "u", "nh", extra={"found_on": "x"}))
            self.assertEqual(json.loads(s.get("nh-crawl", "u")["extra"]),
                             {"archive_series": {"slug": "g"}, "found_on": "x"})
            s.close()


if __name__ == "__main__":
    unittest.main()
