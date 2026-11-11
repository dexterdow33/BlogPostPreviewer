"""Court opinions via the CourtListener REST API v4 (Free Law Project).

Not a government site itself, but it republishes court opinions,
including the New Hampshire Supreme Court's. A free token is required.
"""

from urllib.parse import urlencode

from ..models import Document
from .base import Source, env_key

API = "https://www.courtlistener.com/api/rest/v4/clusters/"
SITE = "https://www.courtlistener.com"
DEFAULT_COURTS = ["nh", "nhd", "nhb", "ca1", "scotus"]
STATE_COURTS = {"nh"}


class CourtListener(Source):
    name = "courtlistener"
    jurisdiction = "mixed"
    description = ("Court opinions: NH Supreme Court (nh), D.N.H. (nhd), "
                   "Bankr. D.N.H. (nhb), First Circuit (ca1), SCOTUS")
    needs_key = "COURTLISTENER_TOKEN"

    @property
    def headers(self):
        token = env_key("COURTLISTENER_TOKEN")
        return {"Authorization": f"Token {token}"} if token else {}

    def iter_documents(self, client, opts):
        n = 0
        for court in opts.courts or DEFAULT_COURTS:
            url = API + "?" + urlencode({
                "docket__court": court,
                "date_filed__gte": opts.since.isoformat(),
                "date_filed__lte": opts.until.isoformat(),
                "order_by": "date_filed",
            })
            while url:
                data = client.get_json(url, headers=self.headers)
                for c in data.get("results") or []:
                    yield self._doc(c, court)
                    n += 1
                    if opts.limit and n >= opts.limit:
                        return
                url = data.get("next")

    def _doc(self, c, court):
        return Document(
            source=self.name,
            doc_id=str(c["id"]),
            title=c.get("case_name") or c.get("case_name_full") or "",
            url=SITE + c["absolute_url"] if c.get("absolute_url") else "",
            jurisdiction="nh" if court in STATE_COURTS else "federal",
            doc_type=c.get("precedential_status"),
            agency=court,
            published=c.get("date_filed"),
            extra={"sub_opinions": c.get("sub_opinions") or []},
        )

    def resolve_download(self, client, row):
        if row["download_url"]:
            return row["download_url"]
        import json
        subs = json.loads(row["extra"] or "{}").get("sub_opinions") or []
        if not subs:
            return None
        op = client.get_json(subs[0], headers=self.headers)
        # Prefer the court's own copy (primary source) over the mirror.
        if op.get("download_url"):
            return op["download_url"]
        if op.get("local_path"):
            return "https://storage.courtlistener.com/" + op["local_path"]
        return None
