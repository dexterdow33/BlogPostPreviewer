from dataclasses import dataclass, field, asdict
from typing import Optional


@dataclass
class Document:
    """One government document, as reported by its source.

    Only fields the source actually returned are filled in. Nothing is
    inferred or guessed; missing values stay None.
    """

    source: str                      # e.g. "federalregister", "nh-crawl"
    doc_id: str                      # stable ID within the source
    title: str
    url: str                         # human-readable landing page
    jurisdiction: str                # "federal" or "nh"
    download_url: Optional[str] = None   # direct file link, if known
    doc_type: Optional[str] = None
    agency: Optional[str] = None
    published: Optional[str] = None      # ISO date as given by the source
    extra: dict = field(default_factory=dict)

    def to_dict(self):
        return asdict(self)
