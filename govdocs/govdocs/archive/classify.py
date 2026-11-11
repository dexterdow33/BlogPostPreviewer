"""Decide which archive series a harvested document belongs to."""

import json
import os
import re
from urllib.parse import urlsplit

DEFAULT_RULES = os.path.join(os.path.dirname(__file__), "rules.json")
JURIS = {"nh": "NH", "federal": "US"}
MATCH_KEYS = ("source", "doc_id", "title", "url", "agency", "doc_type", "host")


def slugify(text):
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s[:48].rstrip("-") or "other"


def load_rules(path=None):
    with open(path or DEFAULT_RULES) as fh:
        rules = json.load(fh)["rules"]
    for r in rules:
        r["_re"] = {k: re.compile(v, re.I) for k, v in r["match"].items()
                    if k in MATCH_KEYS}
    return rules


def _fields(row):
    extra = json.loads(row["extra"] or "{}")
    url = row["url"] or ""
    return extra, {
        "source": row["source"] or "",
        "doc_id": row["doc_id"] or "",
        "title": row["title"] or "",
        "url": url,
        "agency": row["agency"] or "",
        "doc_type": row["doc_type"] or "",
        "host": extra.get("host") or urlsplit(url).hostname or "",
    }


def classify(row, rules):
    """Return {slug, label, juris, agency} for a stored document row."""
    extra, f = _fields(row)
    juris = JURIS.get(row["jurisdiction"], "US")
    for r in rules:
        if all(rx.search(f[k]) for k, rx in r["_re"].items()):
            return {"slug": r["series"]["slug"], "label": r["series"]["label"],
                    "juris": r.get("juris", juris),
                    "agency": r.get("agency") or f["agency"]}
    seeded = extra.get("archive_series")
    if seeded:
        return {"slug": seeded["slug"], "label": seeded["label"],
                "juris": juris, "agency": f["agency"]}
    # Fallback: a new series per agency, or per website for broad sweeps.
    if extra.get("classify_by_host") or (f["source"] == "nh-crawl" and not f["agency"]):
        label = f"Documents from {f['host']}"
        return {"slug": slugify(f["host"]), "label": label, "juris": juris, "agency": ""}
    label = f["agency"] or f["source"]
    return {"slug": slugify(label), "label": label, "juris": juris, "agency": f["agency"]}
