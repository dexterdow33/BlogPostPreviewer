"""Regulations.gov API v4 documents. Needs an api.data.gov key.

One query returns at most 20 pages of 250 (5,000 records), so we query
one posted-date day at a time and warn if a day hits the cap.
"""

import logging
from datetime import timedelta

from ..models import Document
from .base import Source, env_key, days

log = logging.getLogger(__name__)

API = "https://api.regulations.gov/v4/documents"
MAX_PAGES = 20


class RegulationsGov(Source):
    name = "regulationsgov"
    jurisdiction = "federal"
    description = "Regulations.gov rulemaking and docket documents (not public comments)"
    needs_key = "REGULATIONS_GOV_API_KEY or DATA_GOV_API_KEY"

    @property
    def headers(self):
        return {"X-Api-Key": env_key("REGULATIONS_GOV_API_KEY", "DATA_GOV_API_KEY",
                                     default="DEMO_KEY")}

    def iter_documents(self, client, opts):
        n = 0
        for day in days(opts.since, opts.until):
            for page in range(1, MAX_PAGES + 1):
                params = {
                    "filter[postedDate][ge]": day.isoformat(),
                    "filter[postedDate][le]": day.isoformat(),
                    "page[size]": 250,
                    "page[number]": page,
                    "sort": "postedDate",
                }
                if opts.query:
                    params["filter[searchTerm]"] = opts.query
                data = client.get_json(API, params=params, headers=self.headers)
                for item in data.get("data") or []:
                    yield self._doc(item)
                    n += 1
                    if opts.limit and n >= opts.limit:
                        return
                meta = data.get("meta") or {}
                if meta.get("lastPage", True) or not data.get("data"):
                    break
            else:
                log.warning("%s: hit the 5,000-record cap; narrow with --query", day)

    def _doc(self, item):
        a = item.get("attributes") or {}
        doc_id = item["id"]
        return Document(
            source=self.name,
            doc_id=doc_id,
            title=a.get("title") or "",
            url=f"https://www.regulations.gov/document/{doc_id}",
            jurisdiction=self.jurisdiction,
            doc_type=a.get("documentType"),
            agency=a.get("agencyId"),
            published=(a.get("postedDate") or "")[:10] or None,
            extra={k: a.get(k) for k in ("docketId", "frDocNum", "subtype",
                                         "commentEndDate") if a.get(k)},
        )

    def resolve_download(self, client, row):
        if row["download_url"]:
            return row["download_url"]
        data = client.get_json(f"{API}/{row['doc_id']}",
                               params={"include": "attachments"}, headers=self.headers)
        formats = list((data.get("data") or {}).get("attributes", {}).get("fileFormats") or [])
        for inc in data.get("included") or []:
            formats += (inc.get("attributes") or {}).get("fileFormats") or []
        formats.sort(key=lambda f: f.get("format") != "pdf")
        return formats[0]["fileUrl"] if formats else None
