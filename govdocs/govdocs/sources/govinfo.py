"""GovInfo (GPO) API. Needs an api.data.gov key (DEMO_KEY works, slowly).

Uses the /published endpoint, which filters on the date a package was
issued. Download links come from each package's summary, fetched only
when you run `download`.
"""

from urllib.parse import urlsplit, urlencode, parse_qsl, urlunsplit

from ..models import Document
from .base import Source, env_key, months

API = "https://api.govinfo.gov"
DEFAULT_COLLECTIONS = ["BILLS", "PLAW", "CRPT", "CHRG", "CREC", "FR", "CFR",
                       "USCOURTS", "BUDGET", "CPD"]


def with_key(url, key):
    parts = urlsplit(url)
    if parts.netloc != "api.govinfo.gov":
        return url
    q = dict(parse_qsl(parts.query))
    q.setdefault("api_key", key)
    return urlunsplit(parts._replace(query=urlencode(q)))


class GovInfo(Source):
    name = "govinfo"
    jurisdiction = "federal"
    description = ("GPO GovInfo: bills, public laws, CFR, Congressional Record, "
                   "reports, hearings, federal court opinions, budget")
    needs_key = "GOVINFO_API_KEY or DATA_GOV_API_KEY"

    @property
    def key(self):
        return env_key("GOVINFO_API_KEY", "DATA_GOV_API_KEY", default="DEMO_KEY")

    def iter_documents(self, client, opts):
        collections = opts.collections or DEFAULT_COLLECTIONS
        n = 0
        for start, end in months(opts.since, opts.until):
            url = with_key(
                f"{API}/published/{start.isoformat()}/{end.isoformat()}?"
                + urlencode({"offsetMark": "*", "pageSize": 1000,
                             "collection": ",".join(collections)}), self.key)
            while url:
                data = client.get_json(url)
                for p in data.get("packages") or []:
                    yield self._doc(p)
                    n += 1
                    if opts.limit and n >= opts.limit:
                        return
                nxt = data.get("nextPage")
                url = with_key(nxt, self.key) if nxt else None

    def _doc(self, p):
        pid = p["packageId"]
        return Document(
            source=self.name,
            doc_id=pid,
            title=p.get("title") or "",
            url=f"https://www.govinfo.gov/app/details/{pid}",
            jurisdiction=self.jurisdiction,
            doc_type=p.get("docClass"),
            published=p.get("dateIssued"),
            extra={k: p.get(k) for k in ("packageLink", "lastModified",
                                         "congress", "docClass") if p.get(k)},
        )

    def resolve_download(self, client, row):
        if row["download_url"]:
            return row["download_url"]
        import json
        link = json.loads(row["extra"] or "{}").get("packageLink")
        if not link:
            return None
        summary = client.get_json(with_key(link, self.key))
        dl = summary.get("download") or {}
        for k in ("pdfLink", "txtLink", "xmlLink", "zipLink"):
            if dl.get(k):
                return with_key(dl[k], self.key)
        return None
