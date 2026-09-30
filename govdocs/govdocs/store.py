"""SQLite index of collected documents. Re-running a source is safe:
rows are keyed on (source, doc_id) and updated in place."""

import csv
import hashlib
import json
import os
import re
import sqlite3
from datetime import datetime, timezone
from urllib.parse import urlsplit

SCHEMA = """
CREATE TABLE IF NOT EXISTS documents (
    source        TEXT NOT NULL,
    doc_id        TEXT NOT NULL,
    title         TEXT,
    url           TEXT,
    download_url  TEXT,
    jurisdiction  TEXT,
    doc_type      TEXT,
    agency        TEXT,
    published     TEXT,
    extra         TEXT,
    first_seen    TEXT NOT NULL,
    last_seen     TEXT NOT NULL,
    local_path    TEXT,
    sha256        TEXT,
    PRIMARY KEY (source, doc_id)
);
CREATE INDEX IF NOT EXISTS idx_docs_published ON documents(published);
CREATE TABLE IF NOT EXISTS archive (
    source        TEXT NOT NULL,
    doc_id        TEXT NOT NULL,
    series_slug   TEXT NOT NULL,
    series_label  TEXT NOT NULL,
    file_path     TEXT,
    sha256        TEXT,
    wp_media_id   INTEGER,
    wp_url        TEXT,
    archived_at   TEXT,
    PRIMARY KEY (source, doc_id)
);
CREATE TABLE IF NOT EXISTS crawl_seen (
    url        TEXT PRIMARY KEY,
    fetched_at TEXT NOT NULL
);
"""

COLUMNS = ["source", "doc_id", "title", "url", "download_url", "jurisdiction",
           "doc_type", "agency", "published", "extra", "first_seen",
           "last_seen", "local_path", "sha256"]


def _now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class Store:
    def __init__(self, path):
        self.path = path
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)

    def close(self):
        self.db.commit()
        self.db.close()

    def upsert(self, doc):
        """Insert or refresh a Document. Returns True if it was new.
        `extra` is merged with what is stored, so a later, less specific
        sighting (e.g. a broad crawl) does not erase earlier keys."""
        now = _now()
        cur = self.db.execute(
            "SELECT extra FROM documents WHERE source=? AND doc_id=?",
            (doc.source, doc.doc_id))
        prev = cur.fetchone()
        is_new = prev is None
        extra = {**json.loads(prev["extra"] or "{}"), **doc.extra} if prev else doc.extra
        self.db.execute(
            """INSERT INTO documents (source, doc_id, title, url, download_url,
                   jurisdiction, doc_type, agency, published, extra,
                   first_seen, last_seen)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
               ON CONFLICT(source, doc_id) DO UPDATE SET
                   title=excluded.title, url=excluded.url,
                   download_url=COALESCE(excluded.download_url, documents.download_url),
                   jurisdiction=excluded.jurisdiction, doc_type=excluded.doc_type,
                   agency=excluded.agency, published=excluded.published,
                   extra=excluded.extra, last_seen=excluded.last_seen""",
            (doc.source, doc.doc_id, doc.title, doc.url, doc.download_url,
             doc.jurisdiction, doc.doc_type, doc.agency, doc.published,
             json.dumps(extra, sort_keys=True), now, now))
        return is_new

    def commit(self):
        self.db.commit()

    # -- crawl bookkeeping -------------------------------------------------
    def seen(self, url):
        return self.db.execute("SELECT 1 FROM crawl_seen WHERE url=?",
                               (url,)).fetchone() is not None

    def mark_seen(self, url):
        self.db.execute("INSERT OR REPLACE INTO crawl_seen VALUES (?, ?)",
                        (url, _now()))

    # -- queries ------------------------------------------------------------
    def rows(self, source=None, pending_download=False):
        sql = "SELECT * FROM documents"
        clauses, args = [], []
        if source:
            clauses.append("source=?")
            args.append(source)
        if pending_download:
            clauses.append("local_path IS NULL")
        if clauses:
            sql += " WHERE " + " AND ".join(clauses)
        sql += " ORDER BY published, source, doc_id"
        return self.db.execute(sql, args).fetchall()

    def get(self, source, doc_id):
        return self.db.execute("SELECT * FROM documents WHERE source=? AND doc_id=?",
                               (source, doc_id)).fetchone()

    def stats(self):
        return self.db.execute(
            """SELECT source, jurisdiction, COUNT(*) AS n,
                      SUM(local_path IS NOT NULL) AS downloaded,
                      MIN(published) AS earliest, MAX(published) AS latest
               FROM documents GROUP BY source, jurisdiction
               ORDER BY jurisdiction, source""").fetchall()

    def set_download(self, source, doc_id, download_url, local_path, sha256):
        self.db.execute(
            """UPDATE documents SET download_url=?, local_path=?, sha256=?
               WHERE source=? AND doc_id=?""",
            (download_url, local_path, sha256, source, doc_id))

    # -- archive bookkeeping ------------------------------------------------
    def archived(self, source, doc_id):
        return self.db.execute(
            "SELECT * FROM archive WHERE source=? AND doc_id=?",
            (source, doc_id)).fetchone()

    def mark_archived(self, source, doc_id, slug, label, file_path, sha256,
                      media_id, url):
        self.db.execute(
            """INSERT OR REPLACE INTO archive VALUES (?,?,?,?,?,?,?,?,?)""",
            (source, doc_id, slug, label, file_path, sha256, media_id, url, _now()))

    def export_csv(self, fh, source=None):
        w = csv.writer(fh)
        w.writerow(COLUMNS)
        for r in self.rows(source):
            w.writerow([r[c] for c in COLUMNS])

    def export_jsonl(self, fh, source=None):
        for r in self.rows(source):
            d = {c: r[c] for c in COLUMNS}
            d["extra"] = json.loads(d["extra"] or "{}")
            fh.write(json.dumps(d) + "\n")


def safe_filename(source, doc_id, url):
    """Deterministic, filesystem-safe local path for a downloaded file."""
    ext = os.path.splitext(urlsplit(url).path)[1].lower()
    if not re.fullmatch(r"\.[a-z0-9]{1,5}", ext or ""):
        ext = ""
    stem = re.sub(r"[^A-Za-z0-9._-]+", "_", doc_id).strip("._")[:120]
    if not stem or stem != doc_id:
        # Disambiguate IDs that were altered by sanitising.
        stem = (stem or "doc") + "_" + hashlib.sha1(doc_id.encode()).hexdigest()[:10]
    return os.path.join(source, stem + ext)
