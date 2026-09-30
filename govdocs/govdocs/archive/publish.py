"""Plan and publish harvested documents into the Granite State Archive.

The archive page lists any media-library file whose caption carries an
[archive ...] tag, grouped by its series (tier=). A series the page has not
seen before is created on the page the first time a file names it."""

import hashlib
import json
import logging
import os
import re
from collections import Counter
from datetime import datetime, timezone
from urllib.parse import parse_qsl, unquote, urlencode, urlsplit, urlunsplit

import requests

from ..sources import SOURCES
from ..store import safe_filename
from .capture import capture
from .classify import classify

log = logging.getLogger(__name__)

# Types WordPress.com accepts in the media library by default. Others are
# listed in the plan as "skipped: file type".
UPLOADABLE = {"pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods",
              "txt", "csv", "html"}


METADATA_ONLY = {"congress"}   # these rows describe documents but carry no file


def candidates(store, source=None):
    """Rows that can become archive entries: they point at a file or page."""
    for row in store.rows(source):
        if row["source"] not in METADATA_ONLY:
            yield row


def plan(store, rules, source=None):
    """Return a list of dicts: one per candidate, with its series and status."""
    out = []
    for row in candidates(store, source):
        c = classify(row, rules)
        done = store.archived(row["source"], row["doc_id"])
        dtype = (row["doc_type"] or "").lower()
        status = "archived" if done else (
            "ready" if (dtype in UPLOADABLE or row["source"] != "nh-crawl") else "skipped: file type")
        out.append({"source": row["source"], "doc_id": row["doc_id"], "title": row["title"],
                    "series_slug": c["slug"], "series_label": c["label"],
                    "juris": c["juris"], "agency": c["agency"], "status": status,
                    "wp_media_id": done["wp_media_id"] if done else None})
    return out


def summarize(items):
    counts = Counter((i["series_slug"], i["series_label"], i["status"]) for i in items)
    series = {}
    for (slug, label, status), n in counts.items():
        series.setdefault((slug, label), Counter())[status] += n
    return series


def _clean(value):
    """Tag values must not contain brackets or look like another key=."""
    value = re.sub(r"[\[\]]", "", str(value or ""))
    value = re.sub(r"\s+", " ", value).strip()
    return re.sub(r"(\w+)=", r"\1:", value)


def archive_tag(c, source_url, published, rights="public"):
    parts = [f"juris={c['juris']}", f"tier={c['slug']}", f"series={_clean(c['label'])}"]
    if c.get("agency"):
        parts.append(f"agency={_clean(c['agency'])}")
    if published and re.fullmatch(r"\d{4}-\d{2}-\d{2}", published[:10]):
        parts.append(f"date={published[:10]}")
    if rights != "public":
        parts.append(f"rights={rights}")
    parts.append(f"src={source_url}")
    return "[archive " + " ".join(parts) + "]"


def _fetch(client, url, path, max_bytes, check_robots):
    from ..cli import fetch_file   # shared streaming download with size cap
    return fetch_file(client, url, path, max_bytes, check_robots=check_robots)


def _prepare_file(client, row, out_dir, max_bytes):
    """Return (path, filename, sha256, page_title, fetched_url), fetching if needed."""
    src = SOURCES[row["source"]]()
    if row["doc_type"] == "html":
        url = row["url"]
        resp = client.get(url, check_robots=True)
        retrieved = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        text = capture(resp.text, url, retrieved)
        base = os.path.splitext(unquote(os.path.basename(urlsplit(url).path)) or "page")[0]
        filename = re.sub(r"[^A-Za-z0-9._-]+", "-", base).strip("-")[:80] + ".txt"
        path = os.path.join(out_dir, row["source"], filename)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        data = text.encode("utf-8")
        with open(path, "wb") as fh:
            fh.write(data)
        return path, filename, hashlib.sha256(data).hexdigest(), text.split("\n", 1)[0], url
    if row["local_path"] and os.path.exists(row["local_path"]):
        path, url = row["local_path"], row["download_url"] or row["url"]
    else:
        url = src.resolve_download(client, row)
        if not url:
            raise ValueError("no downloadable file")
        path = os.path.join(out_dir, safe_filename(row["source"], row["doc_id"], url))
        _fetch(client, url, path, max_bytes, check_robots=row["source"] == "nh-crawl")
    with open(path, "rb") as fh:
        digest = hashlib.sha256(fh.read()).hexdigest()
    return path, os.path.basename(path), digest, None, url


def public_url(url):
    """Drop credentials (api_key etc.) from a URL before it is published."""
    parts = urlsplit(url)
    q = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True)
         if k.lower() not in {"api_key", "apikey", "key", "token", "access_token"}]
    return urlunsplit(parts._replace(query=urlencode(q)))


def _looks_like_filename(title):
    return not title or " " not in title.strip() or re.search(r"\.\w{2,4}$", title.strip())


def publish(store, client, wp, rules, source=None, series=None, limit=None,
            out_dir="files", max_bytes=200 * 1024 * 1024, dry_run=False):
    done = failed = 0
    wanted = set(series or [])
    for item in plan(store, rules, source):
        if item["status"] != "ready":
            continue
        if wanted and item["series_slug"] not in wanted:
            continue
        if limit and done >= limit:
            break
        row = store.get(item["source"], item["doc_id"])
        c = {"slug": item["series_slug"], "label": item["series_label"],
             "juris": item["juris"], "agency": item["agency"]}
        if dry_run:
            print(f"would publish [{c['slug']}] {row['title'][:90]}")
            done += 1
            continue
        try:
            path, filename, digest, page_title, fetched = _prepare_file(client, row, out_dir, max_bytes)
            fetched = public_url(fetched)
            host = urlsplit(fetched).hostname or "the source website"
            existing = wp.find_by_checksum(digest)
            title = row["title"]
            if page_title and _looks_like_filename(title):
                title = page_title
            if existing:
                media = existing[0]
                log.info("already in media library as %s: %s", media["id"], title)
            else:
                media = wp.upload(path, filename)
                retrieved = datetime.now(timezone.utc).strftime("%Y-%m-%d")
                wp.update(
                    media["id"],
                    title=title[:200],
                    caption=archive_tag(c, public_url(row["url"]), row["published"]) +
                    f" Retrieved from {host} on {retrieved}.",
                    description=f"Source: {public_url(row['url'])}\nFile: {fetched}\nRetrieved: {retrieved}\n"
                                f"Harvested by govdocs ({row['source']}).\nsha256:{digest}",
                    alt_text=title[:120])
            store.mark_archived(row["source"], row["doc_id"], c["slug"], c["label"],
                                path, digest, media["id"], media.get("source_url"))
            store.commit()
            done += 1
            print(f"archived GSR-{media['id']} [{c['slug']}] {title[:80]}")
        except (requests.RequestException, ValueError, OSError) as exc:
            failed += 1
            log.warning("%s: %s", row["doc_id"], exc)
        except Exception as exc:   # WordPressError and anything unexpected
            failed += 1
            log.error("%s: %s", row["doc_id"], exc)
            if "401" in str(exc) or "403" in str(exc):
                raise
    return done, failed


def write_plan_csv(items, path):
    import csv
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(items[0].keys()) if items else ["status"])
        w.writeheader()
        for i in items:
            w.writerow(i)
