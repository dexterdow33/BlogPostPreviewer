"""Congress.gov API v3 bill list. Needs an api.data.gov key.

Filters on the bill's updateDate (last action/change), not its
introduction date. Full bill text lives in GovInfo's BILLS collection.
"""

from urllib.parse import urlsplit, urlencode, parse_qsl, urlunsplit

from ..models import Document
from .base import Source, env_key

API = "https://api.congress.gov/v3/bill"

TYPE_SLUGS = {
    "HR": "house-bill", "S": "senate-bill",
    "HRES": "house-resolution", "SRES": "senate-resolution",
    "HJRES": "house-joint-resolution", "SJRES": "senate-joint-resolution",
    "HCONRES": "house-concurrent-resolution",
    "SCONRES": "senate-concurrent-resolution",
}


def ordinal(n):
    n = int(n)
    if 10 <= n % 100 <= 20:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
    return f"{n}{suffix}"


def public_url(congress, bill_type, number):
    slug = TYPE_SLUGS.get((bill_type or "").upper())
    if not slug:
        return None
    return f"https://www.congress.gov/bill/{ordinal(congress)}-congress/{slug}/{number}"


class Congress(Source):
    name = "congress"
    jurisdiction = "federal"
    description = "Congress.gov bills and resolutions (metadata and latest action)"
    needs_key = "CONGRESS_API_KEY or DATA_GOV_API_KEY"

    @property
    def key(self):
        return env_key("CONGRESS_API_KEY", "DATA_GOV_API_KEY", default="DEMO_KEY")

    def _keyed(self, url):
        parts = urlsplit(url)
        q = dict(parse_qsl(parts.query))
        q["api_key"] = self.key
        return urlunsplit(parts._replace(query=urlencode(q)))

    def iter_documents(self, client, opts):
        url = self._keyed(API + "?" + urlencode({
            "format": "json", "limit": 250, "sort": "updateDate+asc",
            "fromDateTime": f"{opts.since.isoformat()}T00:00:00Z",
            "toDateTime": f"{opts.until.isoformat()}T23:59:59Z",
        }, safe="+"))
        n = 0
        while url:
            data = client.get_json(url)
            for b in data.get("bills") or []:
                yield self._doc(b)
                n += 1
                if opts.limit and n >= opts.limit:
                    return
            nxt = (data.get("pagination") or {}).get("next")
            url = self._keyed(nxt) if nxt else None

    def _doc(self, b):
        doc_id = f"{b['congress']}-{b['type']}-{b['number']}".lower()
        latest = b.get("latestAction") or {}
        return Document(
            source=self.name,
            doc_id=doc_id,
            title=b.get("title") or "",
            url=public_url(b["congress"], b["type"], b["number"]) or b.get("url") or "",
            jurisdiction=self.jurisdiction,
            doc_type=b.get("type"),
            agency=b.get("originChamber"),
            published=latest.get("actionDate"),
            extra={"api_url": b.get("url"), "updateDate": b.get("updateDate"),
                   "latestAction": latest.get("text")},
        )
