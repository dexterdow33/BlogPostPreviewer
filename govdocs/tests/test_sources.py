import io
import json
import os
import sqlite3
import tempfile
import unittest
from datetime import date
from urllib.parse import urlsplit, parse_qs

import requests

from govdocs.http import Client
from govdocs.models import Document
from govdocs.sources.base import Options, months
from govdocs.sources.congress import Congress, ordinal, public_url
from govdocs.sources.courtlistener import CourtListener
from govdocs.sources.crawler import Crawler, normalize, host_allowed
from govdocs.sources.federal_register import FederalRegister
from govdocs.sources.govinfo import GovInfo
from govdocs.sources.regulations_gov import RegulationsGov
from govdocs.store import Store, safe_filename


class FakeResponse:
    def __init__(self, url, status=200, body=b"", headers=None):
        self.url = url
        self.status_code = status
        self.content = body if isinstance(body, bytes) else body.encode()
        self.headers = headers or {}

    @property
    def text(self):
        return self.content.decode("utf-8", "replace")

    def json(self):
        return json.loads(self.content)

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.HTTPError(f"{self.status_code} {self.url}")

    def iter_content(self, n):
        for i in range(0, len(self.content), n):
            yield self.content[i:i + n]

    def close(self):
        pass


class FakeSession:
    """Routes requests to a handler(url, params) -> FakeResponse."""

    def __init__(self, handler):
        self.handler = handler
        self.headers = {}
        self.calls = []

    def get(self, url, params=None, headers=None, timeout=None, stream=False):
        self.calls.append((url, params, headers))
        return self.handler(url, params or {})


def client_for(handler):
    return Client("test-agent", min_interval=0, session=FakeSession(handler),
                  sleep=lambda s: None)


def js(url, obj, status=200):
    return FakeResponse(url, status, json.dumps(obj), {"Content-Type": "application/json"})


OPTS = dict(since=date(2026, 9, 1), until=date(2026, 9, 2))


class FederalRegisterTest(unittest.TestCase):
    def test_pages_and_days(self):
        def handler(url, params):
            if "page=2" in url:
                return js(url, {"count": 2, "results": [
                    {"document_number": "2026-00002", "title": "B", "type": "Notice",
                     "html_url": "h2", "pdf_url": "p2", "publication_date": "2026-09-01",
                     "agencies": [{"name": "EPA"}]}]})
            day = params["conditions[publication_date][gte]"]
            self.assertEqual(day, params["conditions[publication_date][lte]"])
            if day == "2026-09-01":
                return js(url, {"count": 2, "next_page_url": url + "?page=2", "results": [
                    {"document_number": "2026-00001", "title": "A", "type": "Rule",
                     "html_url": "h1", "pdf_url": "p1", "publication_date": day,
                     "agencies": [{"name": "EPA"}, {"name": "DOT"}]}]})
            return js(url, {"count": 0, "results": []})

        docs = list(FederalRegister().iter_documents(client_for(handler), Options(**OPTS)))
        self.assertEqual([d.doc_id for d in docs], ["2026-00001", "2026-00002"])
        self.assertEqual(docs[0].agency, "EPA; DOT")
        self.assertEqual(docs[0].download_url, "p1")

    def test_limit(self):
        def handler(url, params):
            return js(url, {"count": 3, "results": [
                {"document_number": str(i), "title": "t"} for i in range(3)]})
        docs = list(FederalRegister().iter_documents(client_for(handler), Options(limit=2, **OPTS)))
        self.assertEqual(len(docs), 2)


class GovInfoTest(unittest.TestCase):
    def test_published_paging_and_key(self):
        seen = []

        def handler(url, params):
            seen.append(url)
            q = parse_qs(urlsplit(url).query)
            self.assertEqual(q["api_key"], ["DEMO_KEY"])
            if q["offsetMark"] == ["*"]:
                return js(url, {"packages": [{"packageId": "BILLS-119hr1ih", "title": "HR 1",
                                              "dateIssued": "2026-09-01", "docClass": "hr",
                                              "packageLink": "https://api.govinfo.gov/packages/BILLS-119hr1ih/summary"}],
                                "nextPage": "https://api.govinfo.gov/published/2026-09-01/2026-09-02?offsetMark=AoE%2Bx&pageSize=1000&collection=BILLS"})
            self.assertEqual(q["offsetMark"], ["AoE+x"])
            return js(url, {"packages": [], "nextPage": None})

        os.environ.pop("GOVINFO_API_KEY", None)
        os.environ.pop("DATA_GOV_API_KEY", None)
        docs = list(GovInfo().iter_documents(client_for(handler), Options(collections=["BILLS"], **OPTS)))
        self.assertEqual(docs[0].url, "https://www.govinfo.gov/app/details/BILLS-119hr1ih")
        self.assertIn("/published/2026-09-01/2026-09-02?", seen[0])

    def test_resolve_download(self):
        def handler(url, params):
            return js(url, {"download": {"pdfLink": "https://api.govinfo.gov/packages/X/pdf"}})
        row = {"download_url": None, "extra": json.dumps({"packageLink": "https://api.govinfo.gov/packages/X/summary"})}
        url = GovInfo().resolve_download(client_for(handler), row)
        self.assertTrue(url.startswith("https://api.govinfo.gov/packages/X/pdf?api_key="))

    def test_months(self):
        self.assertEqual(list(months(date(2026, 1, 15), date(2026, 3, 2))),
                         [(date(2026, 1, 15), date(2026, 1, 31)),
                          (date(2026, 2, 1), date(2026, 2, 28)),
                          (date(2026, 3, 1), date(2026, 3, 2))])


class RegulationsGovTest(unittest.TestCase):
    def test_stops_on_last_page(self):
        def handler(url, params):
            page = params["page[number]"]
            return js(url, {"data": [{"id": f"EPA-X-{params['filter[postedDate][ge]']}-{page}",
                                      "attributes": {"title": "T", "documentType": "Rule",
                                                     "postedDate": "2026-09-01T04:00:00Z",
                                                     "agencyId": "EPA", "docketId": "EPA-X"}}],
                            "meta": {"lastPage": page == 2}})
        c = client_for(handler)
        docs = list(RegulationsGov().iter_documents(c, Options(**OPTS)))
        self.assertEqual(len(docs), 4)   # 2 days x 2 pages
        self.assertEqual(docs[0].published, "2026-09-01")
        self.assertIn("X-Api-Key", c.session.calls[0][2])

    def test_resolve_prefers_pdf(self):
        def handler(url, params):
            return js(url, {"data": {"attributes": {"fileFormats": [
                {"fileUrl": "a.htm", "format": "htm"}, {"fileUrl": "a.pdf", "format": "pdf"}]}}})
        row = {"download_url": None, "doc_id": "EPA-X-1"}
        self.assertEqual(RegulationsGov().resolve_download(client_for(handler), row), "a.pdf")


class CongressTest(unittest.TestCase):
    def test_ordinals_and_urls(self):
        self.assertEqual([ordinal(n) for n in (101, 111, 112, 113, 119, 121, 122, 123)],
                         ["101st", "111th", "112th", "113th", "119th", "121st", "122nd", "123rd"])
        self.assertEqual(public_url(119, "HR", 1),
                         "https://www.congress.gov/bill/119th-congress/house-bill/1")
        self.assertIsNone(public_url(119, "XX", 1))

    def test_paging(self):
        def handler(url, params):
            q = parse_qs(urlsplit(url).query)
            self.assertIn("api_key", q)
            if "offset" in q:
                return js(url, {"bills": [], "pagination": {}})
            self.assertEqual(q["sort"], ["updateDate asc"])
            self.assertEqual(q["fromDateTime"], ["2026-09-01T00:00:00Z"])
            return js(url, {"bills": [{"congress": 119, "type": "S", "number": "5", "title": "T",
                                       "originChamber": "Senate",
                                       "latestAction": {"actionDate": "2026-09-01", "text": "Read"}}],
                            "pagination": {"next": "https://api.congress.gov/v3/bill?offset=250&limit=250&format=json"}})
        docs = list(Congress().iter_documents(client_for(handler), Options(**OPTS)))
        self.assertEqual(docs[0].doc_id, "119-s-5")
        self.assertEqual(docs[0].url, "https://www.congress.gov/bill/119th-congress/senate-bill/5")


class CourtListenerTest(unittest.TestCase):
    def test_jurisdiction_and_download(self):
        def handler(url, params):
            if "/opinions/" in url:
                return js(url, {"download_url": "https://www.courts.nh.gov/x.pdf",
                                "local_path": "pdf/x.pdf"})
            court = parse_qs(urlsplit(url).query)["docket__court"][0]
            return js(url, {"results": [{"id": 1 if court == "nh" else 2, "case_name": "A v. B",
                                         "absolute_url": "/opinion/1/a-v-b/", "date_filed": "2026-09-01",
                                         "sub_opinions": ["https://www.courtlistener.com/api/rest/v4/opinions/9/"]}],
                            "next": None})
        c = client_for(handler)
        docs = list(CourtListener().iter_documents(c, Options(courts=["nh", "nhd"], **OPTS)))
        self.assertEqual([d.jurisdiction for d in docs], ["nh", "federal"])
        row = {"download_url": None, "extra": json.dumps(docs[0].extra)}
        self.assertEqual(CourtListener().resolve_download(c, row), "https://www.courts.nh.gov/x.pdf")


class CrawlerTest(unittest.TestCase):
    SITE = {
        "https://www.example.nh.gov/robots.txt": "User-agent: *\nDisallow: /private/\n",
        "https://www.example.nh.gov/": """<html><title>Home</title>
            <a href="/about">About</a> <a href="/private/x">secret</a>
            <a href="reports/annual-2025.pdf">Annual Report 2025</a>
            <a href="https://evil.example.com/a.pdf">offsite</a>
            <a href="/logo.png">logo</a> <a href="mailto:x@y">mail</a></html>""",
        "https://www.example.nh.gov/about": """<a href="/files/minutes.docx">Download</a>
            <a href="/#top">top</a>""",
    }

    def handler(self, url, params):
        if url in self.SITE:
            ctype = "text/plain" if url.endswith("robots.txt") else "text/html"
            return FakeResponse(url, 200, self.SITE[url], {"Content-Type": ctype})
        return FakeResponse(url, 404, "")

    def test_crawl(self):
        with tempfile.TemporaryDirectory() as d:
            seeds = os.path.join(d, "s.json")
            with open(seeds, "w") as fh:
                json.dump({"seeds": [{"name": "Example", "start_urls": ["https://www.example.nh.gov/"],
                                      "allowed_domains": ["example.nh.gov"]}]}, fh)
            c = client_for(self.handler)
            docs = list(Crawler().iter_documents(c, Options(seeds_file=seeds, **OPTS)))
            urls = sorted(d.url for d in docs)
            self.assertEqual(urls, ["https://www.example.nh.gov/files/minutes.docx",
                                    "https://www.example.nh.gov/reports/annual-2025.pdf"])
            titles = {d.url: d.title for d in docs}
            self.assertEqual(titles[urls[1]], "Annual Report 2025")
            self.assertEqual(titles[urls[0]], "minutes.docx")   # "Download" replaced by filename
            fetched = [u for u, _, _ in c.session.calls]
            self.assertNotIn("https://www.example.nh.gov/private/x", fetched)
            self.assertNotIn("https://www.example.nh.gov/logo.png", fetched)

    def test_sitemap(self):
        site = dict(self.SITE)
        site["https://www.example.nh.gov/robots.txt"] = "User-agent: *\nSitemap: https://www.example.nh.gov/sm.xml\n"
        site["https://www.example.nh.gov/sm.xml"] = """<?xml version="1.0"?>
            <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            <url><loc>https://www.example.nh.gov/doc/order.pdf</loc><lastmod>2026-08-01T10:00:00Z</lastmod></url>
            </urlset>"""
        self.SITE, old = site, self.SITE
        try:
            docs = list(Crawler().sitemap_urls(client_for(self.handler), "https://www.example.nh.gov/"))
        finally:
            self.SITE = old
        self.assertEqual(docs, [("https://www.example.nh.gov/doc/order.pdf", "2026-08-01")])

    def test_helpers(self):
        self.assertEqual(normalize("HTTPS://WWW.NH.GOV:443/a?b=1#frag"), "https://www.nh.gov/a?b=1")
        self.assertIsNone(normalize("javascript:void(0)"))
        self.assertTrue(host_allowed("https://gc.nh.gov/x", ["nh.gov"]))
        self.assertFalse(host_allowed("https://notnh.gov/x", ["nh.gov"]))


class StoreTest(unittest.TestCase):
    def test_upsert_and_export(self):
        with tempfile.TemporaryDirectory() as d:
            s = Store(os.path.join(d, "t.sqlite"))
            doc = Document("federalregister", "1", "T", "u", "federal", download_url="p")
            self.assertTrue(s.upsert(doc))
            doc.title = "T2"
            doc.download_url = None
            self.assertFalse(s.upsert(doc))
            row = s.rows()[0]
            self.assertEqual(row["title"], "T2")
            self.assertEqual(row["download_url"], "p")   # not wiped by a later None
            buf = io.StringIO()
            s.export_jsonl(buf)
            self.assertEqual(json.loads(buf.getvalue())["doc_id"], "1")
            s.close()

    def test_safe_filename(self):
        self.assertEqual(safe_filename("fr", "2026-00001", "https://x/y.PDF"), os.path.join("fr", "2026-00001.pdf"))
        p = safe_filename("nh-crawl", "https://a/b c.pdf", "https://a/b%20c.pdf")
        self.assertTrue(p.startswith(os.path.join("nh-crawl", "https_a_b_c.pdf_")))
        self.assertTrue(p.endswith(".pdf"))
        self.assertNotIn("..", safe_filename("x", "../../etc/passwd", "https://a/b"))


class RetryTest(unittest.TestCase):
    def test_retries_then_succeeds(self):
        calls = []

        def handler(url, params):
            calls.append(url)
            return js(url, {}, 503) if len(calls) < 3 else js(url, {"ok": True})
        self.assertEqual(client_for(handler).get_json("https://x.gov/a"), {"ok": True})
        self.assertEqual(len(calls), 3)

    def test_gives_up(self):
        c = client_for(lambda url, p: js(url, {}, 500))
        with self.assertRaises(requests.HTTPError):
            c.get("https://x.gov/a")


if __name__ == "__main__":
    unittest.main()
