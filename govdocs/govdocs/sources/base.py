import os
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Optional


@dataclass
class Options:
    since: date
    until: date
    query: Optional[str] = None
    limit: Optional[int] = None          # stop after N documents (per source)
    collections: list = field(default_factory=list)   # govinfo
    courts: list = field(default_factory=list)        # courtlistener
    seeds_file: Optional[str] = None                  # crawler
    max_pages: int = 500                              # crawler, per seed
    max_depth: int = 3                                # crawler
    resume: bool = False                              # crawler: skip pages fetched on earlier runs


def env_key(*names, default=None):
    for n in names:
        v = os.environ.get(n)
        if v:
            return v
    return default


def days(since, until):
    d = since
    while d <= until:
        yield d
        d += timedelta(days=1)


def months(since, until):
    """Yield (start, end) windows, one per calendar month, clipped to range."""
    start = since
    while start <= until:
        nxt = (start.replace(day=1) + timedelta(days=32)).replace(day=1)
        end = min(nxt - timedelta(days=1), until)
        yield start, end
        start = nxt


class Source:
    name = ""
    jurisdiction = ""
    description = ""
    needs_key = None   # env var name(s), shown in `sources`

    def iter_documents(self, client, opts):
        raise NotImplementedError

    def resolve_download(self, client, row):
        """Return a direct file URL for a stored row, or None."""
        return row["download_url"]
