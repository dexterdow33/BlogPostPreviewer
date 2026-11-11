"""Federal Register (federalregister.gov API v1). No key required.

The API pages through at most 2,000 results per query, so we query one
publication day at a time; a single day's issue is well under that.
"""

import logging

from ..models import Document
from .base import Source, days

log = logging.getLogger(__name__)

API = "https://www.federalregister.gov/api/v1/documents.json"
FIELDS = ["document_number", "title", "type", "abstract", "html_url",
          "pdf_url", "publication_date", "agencies", "citation",
          "docket_ids", "regulation_id_numbers"]


class FederalRegister(Source):
    name = "federalregister"
    jurisdiction = "federal"
    description = "Federal Register rules, proposed rules, notices, presidential documents"

    def iter_documents(self, client, opts):
        n = 0
        for day in days(opts.since, opts.until):
            params = {
                "per_page": 1000,
                "order": "oldest",
                "fields[]": FIELDS,
                "conditions[publication_date][gte]": day.isoformat(),
                "conditions[publication_date][lte]": day.isoformat(),
            }
            if opts.query:
                params["conditions[term]"] = opts.query
            url = API
            while url:
                data = client.get_json(url, params=params)
                if data.get("count", 0) > 2000:
                    log.warning("%s: %s results exceed the API's 2,000 paging cap; "
                                "some will be missed", day, data["count"])
                for r in data.get("results") or []:
                    yield self._doc(r)
                    n += 1
                    if opts.limit and n >= opts.limit:
                        return
                url = data.get("next_page_url")
                params = None   # next_page_url already carries the query

    def _doc(self, r):
        agencies = [a.get("name") for a in r.get("agencies") or [] if a.get("name")]
        return Document(
            source=self.name,
            doc_id=r["document_number"],
            title=r.get("title") or "",
            url=r.get("html_url") or "",
            download_url=r.get("pdf_url"),
            jurisdiction=self.jurisdiction,
            doc_type=r.get("type"),
            agency="; ".join(agencies) or None,
            published=r.get("publication_date"),
            extra={k: r.get(k) for k in ("abstract", "citation", "docket_ids",
                                         "regulation_id_numbers") if r.get(k)},
        )
