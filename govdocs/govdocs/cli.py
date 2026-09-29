"""Command line: python -m govdocs <command> ..."""

import argparse
import hashlib
import logging
import os
import sys
from datetime import date, timedelta

import requests

from . import __version__
from .http import Client, RobotsDisallowed
from .sources import SOURCES
from .sources.base import Options
from .store import Store, safe_filename

log = logging.getLogger("govdocs")


def user_agent(contact):
    ua = f"govdocs/{__version__} (public-records research"
    return ua + (f"; contact: {contact})" if contact else ")")


def make_client(args):
    contact = args.contact or os.environ.get("GOVDOCS_CONTACT")
    if not contact:
        log.warning("No contact set. Pass --contact or set GOVDOCS_CONTACT so "
                    "site operators can reach you instead of blocking you.")
    return Client(user_agent(contact), min_interval=args.delay)


def parse_date(s):
    return date.fromisoformat(s)


def cmd_sources(args):
    for name, cls in SOURCES.items():
        key = f"  [key: {cls.needs_key}]" if cls.needs_key else ""
        print(f"{name:16} {cls.jurisdiction:8} {cls.description}{key}")


def cmd_collect(args):
    names = list(SOURCES) if args.sources == ["all"] else args.sources
    unknown = [n for n in names if n not in SOURCES]
    if unknown:
        sys.exit(f"unknown source(s): {', '.join(unknown)}. See: python -m govdocs sources")
    until = args.until or date.today()
    since = args.since or (until - timedelta(days=7))
    if since > until:
        sys.exit("--since is after --until")
    opts = Options(since=since, until=until, query=args.query, limit=args.limit,
                   collections=_split(args.collections), courts=_split(args.courts),
                   seeds_file=args.seeds, max_pages=args.max_pages,
                   max_depth=args.max_depth, resume=args.resume)
    client = make_client(args)
    store = Store(args.db)
    failed = []
    try:
        for name in names:
            src = SOURCES[name](store) if name == "nh-crawl" else SOURCES[name]()
            new = total = 0
            log.info("%s: %s to %s", name, since, until)
            try:
                for doc in src.iter_documents(client, opts):
                    total += 1
                    new += store.upsert(doc)
                    if total % 200 == 0:
                        store.commit()
                        log.info("%s: %d seen, %d new", name, total, new)
            except requests.RequestException as exc:
                log.error("%s stopped early: %s", name, exc)
                failed.append(name)
            store.commit()
            print(f"{name}: {total} documents seen, {new} new")
    finally:
        store.close()
    if failed:
        sys.exit(f"incomplete: {', '.join(failed)} (re-run to continue; rows already saved are kept)")


def cmd_download(args):
    client = make_client(args)
    store = Store(args.db)
    max_bytes = args.max_mb * 1024 * 1024
    done = 0
    try:
        for row in store.rows(args.source, pending_download=True):
            if args.limit and done >= args.limit:
                break
            src = SOURCES[row["source"]]()
            try:
                url = src.resolve_download(client, row)
            except requests.RequestException as exc:
                log.warning("%s/%s: could not resolve link: %s", row["source"], row["doc_id"], exc)
                continue
            if not url:
                log.info("%s/%s: no downloadable file", row["source"], row["doc_id"])
                continue
            rel = safe_filename(row["source"], row["doc_id"], url)
            path = os.path.join(args.out, rel)
            try:
                digest = fetch_file(client, url, path, max_bytes,
                                    check_robots=row["source"] == "nh-crawl")
            except (requests.RequestException, RobotsDisallowed, ValueError) as exc:
                log.warning("%s: %s", url, exc)
                continue
            store.set_download(row["source"], row["doc_id"], url, path, digest)
            store.commit()
            done += 1
            print(f"saved {path}")
    finally:
        store.close()
    print(f"{done} files downloaded")


def fetch_file(client, url, path, max_bytes, check_robots=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    resp = client.get(url, stream=True, check_robots=check_robots)
    length = resp.headers.get("Content-Length")
    if length and length.isdigit() and int(length) > max_bytes:
        resp.close()
        raise ValueError(f"file is {int(length)} bytes, over --max-mb")
    h = hashlib.sha256()
    size = 0
    tmp = path + ".part"
    with open(tmp, "wb") as fh:
        for chunk in resp.iter_content(1 << 16):
            size += len(chunk)
            if size > max_bytes:
                fh.close()
                os.remove(tmp)
                raise ValueError("file exceeded --max-mb while downloading")
            h.update(chunk)
            fh.write(chunk)
    os.replace(tmp, path)
    return h.hexdigest()


def cmd_stats(args):
    store = Store(args.db)
    rows = store.stats()
    store.close()
    if not rows:
        print("no documents yet")
        return
    print(f"{'source':16} {'juris':8} {'docs':>8} {'files':>7}  published range")
    for r in rows:
        print(f"{r['source']:16} {r['jurisdiction']:8} {r['n']:>8} {r['downloaded'] or 0:>7}  "
              f"{r['earliest'] or '?'} .. {r['latest'] or '?'}")


def cmd_export(args):
    store = Store(args.db)
    out = open(args.out, "w", newline="", encoding="utf-8") if args.out else sys.stdout
    try:
        if args.format == "csv":
            store.export_csv(out, args.source)
        else:
            store.export_jsonl(out, args.source)
    finally:
        store.close()
        if args.out:
            out.close()


def _split(value):
    return [v.strip() for v in value.split(",") if v.strip()] if value else []


def build_parser():
    p = argparse.ArgumentParser(prog="govdocs", description=__doc__)
    p.add_argument("--db", default="govdocs.sqlite", help="SQLite index (default: %(default)s)")
    p.add_argument("--contact", help="email or URL put in the User-Agent (or set GOVDOCS_CONTACT)")
    p.add_argument("--delay", type=float, default=1.0,
                   help="minimum seconds between requests to one host (default: %(default)s)")
    p.add_argument("-v", "--verbose", action="store_true")
    sub = p.add_subparsers(dest="command", required=True)

    sub.add_parser("sources", help="list available sources").set_defaults(func=cmd_sources)

    c = sub.add_parser("collect", help="index documents from one or more sources")
    c.add_argument("sources", nargs="+", help="source names, or 'all'")
    c.add_argument("--since", type=parse_date, help="YYYY-MM-DD (default: 7 days before --until)")
    c.add_argument("--until", type=parse_date, help="YYYY-MM-DD (default: today)")
    c.add_argument("--query", help="full-text filter (federalregister, regulationsgov)")
    c.add_argument("--limit", type=int, help="stop each source after N documents")
    c.add_argument("--collections", help="govinfo collection codes, comma-separated")
    c.add_argument("--courts", help="courtlistener court IDs, comma-separated")
    c.add_argument("--seeds", help="crawler seeds JSON (default: built-in NH list)")
    c.add_argument("--max-pages", type=int, default=500, help="crawler pages per seed")
    c.add_argument("--max-depth", type=int, default=3, help="crawler link depth")
    c.add_argument("--resume", action="store_true",
                   help="crawler: skip pages already fetched on an earlier run")
    c.set_defaults(func=cmd_collect)

    d = sub.add_parser("download", help="download files for indexed documents")
    d.add_argument("--source", help="only this source")
    d.add_argument("--out", default="files", help="download folder (default: %(default)s)")
    d.add_argument("--limit", type=int, help="stop after N files")
    d.add_argument("--max-mb", type=int, default=200, help="skip files larger than this")
    d.set_defaults(func=cmd_download)

    sub.add_parser("stats", help="counts per source").set_defaults(func=cmd_stats)

    e = sub.add_parser("export", help="write the index as CSV or JSON Lines")
    e.add_argument("--format", choices=["csv", "jsonl"], default="csv")
    e.add_argument("--source")
    e.add_argument("--out", help="output file (default: stdout)")
    e.set_defaults(func=cmd_export)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    args.func(args)
