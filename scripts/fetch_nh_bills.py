#!/usr/bin/env python3
"""
fetch_nh_bills.py - build the Granite State Report NH Bill Tracker dataset.

Source
------
The New Hampshire General Court publishes its bill-status database as
pipe-delimited text files at https://gc.nh.gov/dynamicdatadump/ . This script
downloads those files, records what it found (a "discovery report" so the
column mapping can be audited), and writes JSON that the static dashboard in
nh-bills/ reads.

Column positions below come from two places:
  * the Open States New Hampshire scraper (openstates-scrapers/scrapers/nh/bills.py),
    which has parsed these files for years; and
  * the discovery report this script writes on every run (data/raw/_discovery_report.md),
    which is the check that the positions still hold.

Politeness
----------
The General Court asks automated clients to stay off the site between 6 a.m. and
9 p.m. Eastern. The workflow that runs this script is scheduled inside the
off-hours window and each file is fetched once per run.

No third-party dependencies: standard library only.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://gc.nh.gov/dynamicdatadump/"
RSS_URL = "https://gc.nh.gov/rssFeeds/rssQueryResults.aspx?&sortoption=&txtsessionyear={session}"
USER_AGENT = "GSR-NH-Bill-Tracker/1.0 (+https://github.com/dexterdow33/BlogPostPreviewer)"

# Files the Open States scraper reads. Field counts are what it expects; the
# discovery step measures the real modal count and the parser uses that.
REQUIRED_FILES = {
    "LSRs.txt": "one row per legislative service request / bill",
    "LsrsOnly.txt": "LSR id -> bill-page document id",
    "Docket.txt": "docket actions (one row per action)",
    "LsrSponsors.txt": "sponsors, keyed by legislator employee id",
    "legislators.txt": "legislator roster",
    "RollCallSummary.txt": "roll-call tallies",
    "RollCallHistory.txt": "per-legislator roll-call votes",
}
# Names that may or may not exist; a 404 is logged, never fatal.
OPTIONAL_FILES = [
    "Committees.txt",
    "CommitteeMembers.txt",
    "Hearings.txt",
    "LegislationText.txt",
    "Amendments.txt",
]

# Bill-number prefixes -> type label.
TYPE_LABELS = {
    "HB": "House Bill",
    "SB": "Senate Bill",
    "HR": "House Resolution",
    "SR": "Senate Resolution",
    "HCR": "House Concurrent Resolution",
    "SCR": "Senate Concurrent Resolution",
    "HJR": "House Joint Resolution",
    "SJR": "Senate Joint Resolution",
    "CACR": "Constitutional Amendment Concurrent Resolution",
    "HCO": "House Concurrent Order",
    "SCO": "Senate Concurrent Order",
    "PET": "Petition",
    "SSHB": "Special Session House Bill",
    "SSSB": "Special Session Senate Bill",
}

# GSR beat keywords (assumption: the house-style skills were not available when
# this was written, so these are the editor's stated interests plus the obvious
# New Hampshire accountability beats). Edit freely.
BEATS = {
    "Right-to-Know / transparency": [
        r"\b91-a\b", r"right[- ]to[- ]know", r"public records?", r"transparen", r"open meeting",
        r"governmental records", r"disclosure",
    ],
    "Government accountability / ethics": [
        r"\bethics\b", r"conflict of interest", r"accountab", r"\baudit", r"ombuds", r"whistleblow",
        r"inspector general", r"lobby",
    ],
    "Courts / justice": [
        r"\bcourt", r"judicial", r"\bjudge", r"bail\b", r"sentenc", r"criminal", r"\bpolice\b",
        r"law enforcement", r"prosecut", r"new trial", r"parole", r"probation",
    ],
    "Education / school choice": [
        r"education freedom", r"\bschool", r"\bstudent", r"\bteacher", r"curricul", r"charter",
        r"tuition", r"\bpupil",
    ],
    "Taxes / spending / budget": [
        r"\btax", r"appropriat", r"\bbudget", r"\bfee\b", r"\bfees\b", r"revenue", r"\btoll",
        r"bond", r"surplus",
    ],
    "Housing / land use / local control": [
        r"housing", r"zoning", r"land use", r"tenant", r"landlord", r"eviction", r"short[- ]term rental",
        r"accessory dwelling", r"\bmunicipal", r"\btown\b", r"planning board",
    ],
    "Energy / utilities / environment": [
        r"\benergy\b", r"electric", r"utility", r"utilities", r"\bpfas\b", r"\bwater\b", r"landfill",
        r"solar", r"nuclear", r"net metering", r"eversource", r"\bratepayer",
    ],
    "Elections / voting": [
        r"\belection", r"\bvoter", r"\bvoting\b", r"\bballot", r"absentee", r"redistrict", r"campaign finance",
    ],
    "Guns / civil liberties": [
        r"firearm", r"\bgun\b", r"\bguns\b", r"second amendment", r"free speech", r"first amendment",
        r"religious", r"privacy",
    ],
    "Health / social services": [
        r"\bhealth", r"medicaid", r"\bhospital", r"mental", r"substance", r"opioid", r"abortion",
        r"reproductive", r"vaccine", r"\bchild", r"\bdcyf\b", r"foster",
    ],
    "Immigration / law and order": [
        r"immigra", r"\bice\b", r"sanctuary", r"citizenship", r"border",
    ],
    "Gender / bathroom / sports bills": [
        r"\bgender\b", r"biological sex", r"bathroom", r"locker room", r"\bsex\b", r"transgender",
    ],
    "Cannabis / alcohol / gaming": [
        r"cannabis", r"marijuana", r"\balcohol", r"liquor", r"\bgaming\b", r"charitable gaming",
        r"\bcasino", r"lottery", r"sports betting",
    ],
}


# --------------------------------------------------------------------------- #
# HTTP
# --------------------------------------------------------------------------- #
def fetch(url: str, timeout: int = 180, retries: int = 3, max_bytes: int | None = None) -> bytes | None:
    """GET with a cache-buster, retries, and a polite User-Agent. None on 404.
    max_bytes reads only a head sample (used to inspect unknown files cheaply)."""
    sep = "&" if "?" in url else "?"
    busted = f"{url}{sep}x={int(time.time())}"
    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(busted, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = resp.read(max_bytes) if max_bytes else resp.read()
                total = resp.headers.get("Content-Length") or "?"
                print(f"  GET {url} -> {resp.status} {len(data):,} bytes{' (sample of ' + str(total) + ')' if max_bytes else ''}", flush=True)
                return data
        except urllib.error.HTTPError as e:
            print(f"  GET {url} -> HTTP {e.code}", flush=True)
            if e.code == 404:
                return None
            last_err = e
        except Exception as e:  # noqa: BLE001
            print(f"  GET {url} -> error {e!r} (attempt {attempt}/{retries})", flush=True)
            last_err = e
        time.sleep(3 * attempt)
    print(f"  giving up on {url}: {last_err!r}", flush=True)
    return None


def decode(data: bytes) -> str:
    text = data.decode("utf-8-sig", errors="replace")
    return text.replace("﻿", "")


# --------------------------------------------------------------------------- #
# Pipe-delimited parsing with record re-joining
# --------------------------------------------------------------------------- #
def modal_field_count(lines: list[str]) -> int:
    counts = collections.Counter(len(l.split("|")) for l in lines if "|" in l)
    return counts.most_common(1)[0][0] if counts else 0


def split_records(text: str, expected: int | None = None) -> tuple[list[list[str]], dict]:
    """Split into records of `expected` fields, re-joining lines that wrapped
    (titles in LSRs.txt contain embedded newlines). Returns records and stats."""
    lines = [l for l in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    lines = [l for l in lines if l.strip() != ""]
    if expected is None:
        expected = modal_field_count(lines)
    records: list[list[str]] = []
    bad = 0
    joined = 0
    buf: list[str] | None = None
    for line in lines:
        parts = line.split("|")
        if buf is not None:
            # continuation: the wrapped line's first fragment belongs to the last field
            merged = buf[:-1] + [buf[-1] + "\n" + parts[0]] + parts[1:]
            if len(merged) == expected:
                records.append(merged)
                joined += 1
                buf = None
                continue
            if len(merged) < expected:
                buf = merged
                continue
            # overshoot: give up on the buffer
            bad += 1
            buf = None
        if len(parts) == expected:
            records.append(parts)
        elif len(parts) < expected:
            buf = parts
        else:
            # Too many fields: a title contained a pipe. Keep the row but flag it.
            records.append(parts)
            bad += 1
    if buf is not None:
        bad += 1
    stats = {"lines": len(lines), "records": len(records), "expected_fields": expected, "joined": joined, "irregular": bad}
    return records, stats


def field_histogram(lines: list[str]) -> list[tuple[int, int]]:
    c = collections.Counter(len(l.split("|")) for l in lines if l.strip())
    return c.most_common(5)


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
DATE_FORMATS = ["%m/%d/%Y %I:%M:%S %p", "%m/%d/%Y %H:%M:%S %p", "%m/%d/%Y %H:%M:%S", "%m/%d/%Y", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"]


def parse_ts(s: str) -> dt.datetime | None:
    s = (s or "").strip()
    for fmt in DATE_FORMATS:
        try:
            return dt.datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None


def norm_bill_id(raw: str) -> str:
    """'HB 2026-FN-A' / 'HB2026' -> 'HB2026'."""
    s = (raw or "").upper().strip()
    m = re.match(r"([A-Z]+)\s*0*(\d+)", s)
    return f"{m.group(1)}{m.group(2)}" if m else s.replace(" ", "")


def bill_label(bill_id: str) -> str:
    m = re.match(r"([A-Z]+)(\d+)", bill_id or "")
    return f"{m.group(1)} {m.group(2)}" if m else bill_id


def bill_prefix(bill_id: str) -> str:
    m = re.match(r"([A-Z]+)", bill_id or "")
    return m.group(1) if m else ""


def lsr_key(session: str, lsr: str) -> str:
    return f"{session}|{lsr.lstrip('0') or '0'}"


def normalize_action(text: str) -> str:
    """Collapse dates, vote counts and journal references so identical kinds of
    actions group together in the discovery report."""
    t = re.sub(r"\d{1,2}/\d{1,2}/\d{2,4}", "<date>", text)
    t = re.sub(r"\b\d+\s*-\s*\d+\b", "<n>-<n>", t)
    t = re.sub(r"\b(HJ|SJ)\s*\d+", r"\1 <n>", t)
    t = re.sub(r"\b(Chapter|Ch\.?)\s*\d+", r"\1 <n>", t)
    t = re.sub(r"#?\s*\d{4}-\d+[hs]\b", "<amend>", t)
    t = re.sub(r"\b\d+\b", "<n>", t)
    return re.sub(r"\s+", " ", t).strip()


# --------------------------------------------------------------------------- #
# Status classification from docket text
# --------------------------------------------------------------------------- #
# Order matters: first match wins on the LAST action; some rules look at history.
STATUS_RULES = [
    ("law", r"signed by (the )?governor|became law without|chapter \d+"),
    ("veto_overridden", r"veto overridden|override (vote )?(passed|adopted|succeeds)|overrid"),
    ("veto_sustained", r"veto sustained|override (vote )?fail|sustained"),
    ("vetoed", r"vetoed by (the )?governor|\bvetoed\b"),
    ("enrolled", r"enrolled"),
    ("conference", r"committee of conference"),
    ("interim_study", r"interim study"),
    ("retained", r"retained in committee"),
    ("rereferred", r"re-?referred"),
    ("tabled", r"laid on (the )?table|tabled"),
    ("killed", r"inexpedient to legislate|indefinitely postpone|\bkilled\b|not adopted|failed|motion.*(itl|inexpedient)"),
    ("passed_chamber", r"ought to pass|passed|adopted"),
    ("hearing", r"hearing"),
    ("in_committee", r"introduced|referred to"),
]

STATUS_LABELS = {
    "law": "Signed into law",
    "veto_overridden": "Vetoed; override passed",
    "veto_sustained": "Vetoed; veto sustained",
    "vetoed": "Vetoed by Governor",
    "enrolled": "Enrolled / awaiting Governor",
    "conference": "Committee of conference",
    "interim_study": "Interim study",
    "retained": "Retained in committee",
    "rereferred": "Re-referred to committee",
    "tabled": "Laid on table",
    "killed": "Killed",
    "passed_chamber": "Passed a chamber / in process",
    "hearing": "Hearing scheduled",
    "in_committee": "In committee",
    "unknown": "Status not classified",
}


def classify(actions: list[dict]) -> tuple[str, dict]:
    """Return (status_code, details) from the ordered action list."""
    details: dict = {}
    if not actions:
        return "unknown", details
    texts = [a["text"] for a in actions]
    joined = " || ".join(texts).lower()

    # Veto logic uses history, not just the last action.
    if re.search(r"vetoed by (the )?governor|\bvetoed\b", joined):
        details["vetoed"] = True
        veto_idx = max(i for i, t in enumerate(texts) if re.search(r"vetoed", t, re.I))
        after = " || ".join(texts[veto_idx + 1:]).lower()
        if re.search(r"overrid", after):
            return "veto_overridden", details
        if re.search(r"sustain|fail", after):
            return "veto_sustained", details
        return "vetoed", details

    for code, pat in STATUS_RULES:
        if re.search(pat, texts[-1], re.I):
            return code, details
    return "unknown", details


def extract_chapter(actions: list[dict]) -> dict:
    out: dict = {}
    for a in reversed(actions):
        m = re.search(r"chapter\s*(\d+)", a["text"], re.I)
        if m and "chapter" not in out:
            out["chapter"] = int(m.group(1))
        # "eff. 01/01/2027", "effective 60 days", "I. Sec 2 eff 7/1/26"
        for em in re.finditer(r"eff(?:ective)?\.?\s*(\d{1,2}/\d{1,2}/\d{2,4})", a["text"], re.I):
            d = em.group(1)
            for fmt in ("%m/%d/%Y", "%m/%d/%y"):
                try:
                    iso = dt.datetime.strptime(d, fmt).date().isoformat()
                    out.setdefault("effective_dates", [])
                    if iso not in out["effective_dates"]:
                        out["effective_dates"].append(iso)
                    break
                except ValueError:
                    continue
        if re.search(r"eff(?:ective)?\.?\s*(upon|on)\s*passage", a["text"], re.I):
            out["effective_on_passage"] = True
    return out


def extract_committee(actions: list[dict]) -> str | None:
    for a in actions:
        m = re.search(r"referred to (?:the )?(?:committee on )?([A-Z][A-Za-z ,&/'\-]+?)(?:;|\.|\s+HJ|\s+SJ|\s+\d|$)", a["text"])
        if m:
            return m.group(1).strip()
    return None


# --------------------------------------------------------------------------- #
# RSS feed of all bills for a session (fallback bill list when LSRs.txt is empty)
# --------------------------------------------------------------------------- #
def parse_rss_items(xml_text: str) -> list[dict]:
    """Return one dict per <item>, keys = lower-cased local tag names."""
    import xml.etree.ElementTree as ET
    items: list[dict] = []
    try:
        root = ET.fromstring(xml_text.encode("utf-8", errors="replace"))
    except ET.ParseError as e:
        print(f"  RSS parse error: {e}", flush=True)
        return items
    for item in root.iter("item"):
        d: dict = {}
        for child in item:
            tag = child.tag.split("}")[-1].lower()
            d[tag] = (child.text or "").strip()
        items.append(d)
    return items


def looks_like_roster(rows: list[list[str]]) -> bool:
    """A roster row starts with a numeric id and has a last/first name pair."""
    good = 0
    for r in rows[:50]:
        if len(r) >= 5 and r[0].strip().isdigit() and re.match(r"^[A-Za-z'\- .]+$", r[1].strip() or "x") and re.match(r"^[A-Za-z'\- .]+$", r[2].strip() or "x"):
            good += 1
    return good >= max(3, len(rows[:50]) // 2)


# --------------------------------------------------------------------------- #
# Main build
# --------------------------------------------------------------------------- #
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sessions", default="2025,2026,2027", help="comma-separated session years to emit")
    ap.add_argument("--out", default="data", help="output directory")
    ap.add_argument("--raw-limit-mb", type=float, default=6.0, help="commit raw files up to this size; larger ones get a head sample")
    args = ap.parse_args()

    out_dir = args.out
    raw_dir = os.path.join(out_dir, "raw")
    os.makedirs(raw_dir, exist_ok=True)
    os.makedirs(os.path.join(raw_dir, "samples"), exist_ok=True)
    wanted_sessions = [s.strip() for s in args.sessions.split(",") if s.strip()]
    now = dt.datetime.now(dt.timezone.utc)
    report: list[str] = [f"# NH dynamicdatadump discovery report\n\nGenerated {now.isoformat(timespec='seconds')}\n"]

    # Directory index (may be a listing, may be forbidden) --------------------
    print("Fetching directory index", flush=True)
    idx = fetch(BASE)
    index_links: list[str] = []
    if idx:
        html = decode(idx)
        index_links = sorted(set(re.findall(r'href="([^"]+\.(?:txt|csv|zip|pdf|xls|xlsx))"', html, re.I)))
        with open(os.path.join(raw_dir, "_directory_index.html"), "w", encoding="utf-8") as f:
            f.write(html)
        report.append("## Directory index\n\n" + ("\n".join(f"- {l}" for l in index_links) if index_links else "_no file links found in index HTML_") + "\n")
    else:
        report.append("## Directory index\n\n_index not retrievable_\n")

    # Download every file ------------------------------------------------------
    texts: dict[str, str] = {}
    for name in list(REQUIRED_FILES) + OPTIONAL_FILES:
        print(f"Fetching {name}", flush=True)
        data = fetch(BASE + name)
        if data is None:
            report.append(f"## {name}\n\n_not available (404 or unreachable)_\n")
            continue
        text = decode(data)
        texts[name] = text
        lines = [l for l in text.replace("\r\n", "\n").split("\n") if l.strip()]
        hist = field_histogram(lines)
        sha = hashlib.sha256(data).hexdigest()[:16]
        report.append(f"## {name}\n\n{REQUIRED_FILES.get(name, 'optional file')}\n\n"
                      f"- bytes: {len(data):,}; non-empty lines: {len(lines):,}; sha256: {sha}\n"
                      f"- field-count histogram (fields: rows): {', '.join(f'{k}: {v}' for k, v in hist)}\n\n"
                      "First rows (fields shown as `[i]=value`):\n\n")
        for l in lines[:3]:
            parts = l.split("|")
            report.append("```\n" + "\n".join(f"[{i}]={p[:160]}" for i, p in enumerate(parts)) + "\n```\n")
        # raw copy or head sample
        size_mb = len(data) / 1_000_000
        if size_mb <= args.raw_limit_mb:
            with open(os.path.join(raw_dir, name), "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
        else:
            with open(os.path.join(raw_dir, "samples", name.replace(".txt", ".head.txt")), "w", encoding="utf-8", newline="\n") as f:
                f.write("\n".join(lines[:400]) + "\n")
            report.append(f"_raw file {size_mb:.1f} MB exceeds the commit limit; 400-line head sample saved to data/raw/samples/_\n")

    # Sample every other text file the index lists, so the report shows what
    # else the General Court publishes (roster files in particular).
    known = {n.lower() for n in list(REQUIRED_FILES) + OPTIONAL_FILES}
    samples: dict[str, list[list[str]]] = {}
    for link in index_links:
        name = link.rsplit("/", 1)[-1]
        if name.lower() in known or not re.search(r"\.(txt|csv)$", name, re.I):
            continue
        url = link if link.startswith("http") else BASE + name
        print(f"Sampling {name}", flush=True)
        data = fetch(url, max_bytes=65536, retries=2)
        if not data:
            continue
        text = decode(data)
        lines = [l for l in text.replace("\r\n", "\n").split("\n") if l.strip()]
        rows = [l.split("|") for l in lines[:60]]
        samples[name] = rows
        hist = field_histogram(lines)
        report.append(f"## (index) {name}\n\n- sampled bytes: {len(data):,}; field-count histogram: {', '.join(f'{k}: {v}' for k, v in hist)}\n\n")
        for l in lines[:3]:
            report.append("```\n" + "\n".join(f"[{i}]={p[:160]}" for i, p in enumerate(l.split("|"))) + "\n```\n")
        with open(os.path.join(raw_dir, "samples", name.replace(".txt", ".sample.txt").replace(".csv", ".sample.csv")), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines[:200]) + "\n")

    # RSS feed per session: the bill list with titles, used when LSRs.txt is empty
    rss_items: dict[str, list[dict]] = {}
    for session in wanted_sessions:
        print(f"Fetching RSS bill list for {session}", flush=True)
        data = fetch(RSS_URL.format(session=session), retries=2)
        if not data:
            report.append(f"## RSS {session}\n\n_not available_\n")
            continue
        text = decode(data)
        with open(os.path.join(raw_dir, f"rss_{session}.xml"), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        items = parse_rss_items(text)
        rss_items[session] = items
        tags = collections.Counter(t for it in items for t in it)
        report.append(f"## RSS {session}\n\n- bytes: {len(data):,}; items: {len(items):,}\n- tags seen: {dict(tags)}\n\n")
        for it in items[:2]:
            report.append("```\n" + "\n".join(f"{k}={v[:200]}" for k, v in it.items()) + "\n```\n")

    missing = [n for n in REQUIRED_FILES if n not in texts]
    lsrs_ok = "LSRs.txt" in texts and len(texts["LSRs.txt"].strip()) >= 1024
    if not lsrs_ok:
        report.append("\n**LSRs.txt missing or effectively empty (a known intermittent condition of the dump). Bill list built from the RSS feed, LsrsOnly.txt and Docket.txt instead.**\n")
    if missing:
        report.append(f"\n**Warning: missing required files: {', '.join(missing)}**\n")

    # Parse LSRs ---------------------------------------------------------------
    lsr_records: list[list[str]] = []
    if lsrs_ok:
        lsr_records, st = split_records(texts["LSRs.txt"])
        report.append(f"\n## Parse: LSRs.txt\n\n{json.dumps(st)}\n")
        session_counts = collections.Counter(r[0].strip() for r in lsr_records)
        report.append("Session years present: " + ", ".join(f"{k}: {v}" for k, v in sorted(session_counts.items())) + "\n")

    bills: dict[str, dict] = {}       # key session|lsr
    by_bill_id: dict[str, str] = {}   # session|BILLID -> key
    raw_by_key: dict[str, list[str]] = {}
    for r in lsr_records:
        if len(r) < 11:
            continue
        session = r[0].strip()
        lsr = r[1].strip()
        title = r[2].strip()
        body = r[3].strip()
        expanded = r[9].strip()
        bid = norm_bill_id(r[10].strip() or expanded)
        if title.startswith("("):
            # "(New Title) ..." convention seen in the dump
            title = title.split(")", 1)[1].strip() if ")" in title else title
        key = lsr_key(session, lsr)
        bills[key] = {
            "session": session,
            "lsr": lsr.lstrip("0") or "0",
            "lsr_id": f"{session[-2:]}-{lsr.lstrip('0').zfill(4)}",
            "bill_id": bid,
            "bill_label": bill_label(bid) if bid else "",
            "bill_type": TYPE_LABELS.get(bill_prefix(bid), bill_prefix(bid) or "LSR (no bill number yet)"),
            "expanded_id": expanded,
            "title": title,
            "origin_body": body,
            "origin_chamber": {"H": "House", "S": "Senate"}.get(body, body),
            "type_num": r[4].strip(),
            "source_row": "LSRs.txt",
            "sponsors": [],
            "actions": [],
            "roll_calls": [],
        }
        raw_by_key[key] = [f.strip() for f in r]
        if bid:
            by_bill_id[f"{session}|{bid}"] = key

    # Show a few named bills' raw fields so unknown columns can be mapped.
    probe_ids = ["HB2026", "HB1422", "SB434", "HB1267", "HB1102", "HB1442", "SB268", "HB1", "HB2", "SB1"]
    if raw_by_key:
        report.append("\n### Raw LSRs.txt fields for reference bills (2026)\n")
        for pid in probe_ids:
            k = by_bill_id.get(f"2026|{pid}")
            if k and k in raw_by_key:
                b = bills[k]
                report.append(f"**{b['bill_label']}** (LSR {b['lsr_id']}) {b['title'][:120]}\n\n```\n" +
                              "\n".join(f"[{i}]={v[:200]}" for i, v in enumerate(raw_by_key[k])) + "\n```\n")

    def ensure_bill(session: str, lsr: str, bid: str, title: str, body: str, source: str) -> dict:
        key = lsr_key(session, lsr)
        b = bills.get(key)
        if b is None:
            bid = norm_bill_id(bid)
            b = {
                "session": session,
                "lsr": lsr.lstrip("0") or "0",
                "lsr_id": f"{session[-2:]}-{(lsr.lstrip('0') or '0').zfill(4)}",
                "bill_id": bid,
                "bill_label": bill_label(bid) if bid else "",
                "bill_type": TYPE_LABELS.get(bill_prefix(bid), bill_prefix(bid) or "LSR (no bill number yet)"),
                "expanded_id": "",
                "title": title.strip(),
                "origin_body": body,
                "origin_chamber": {"H": "House", "S": "Senate"}.get(body, body or ""),
                "type_num": "",
                "source_row": source,
                "sponsors": [],
                "actions": [],
                "roll_calls": [],
            }
            bills[key] = b
            if bid:
                by_bill_id[f"{session}|{bid}"] = key
        else:
            if not b["title"] and title:
                b["title"] = title.strip()
            if not b["bill_id"] and bid:
                b["bill_id"] = norm_bill_id(bid); b["bill_label"] = bill_label(b["bill_id"]); b["bill_type"] = TYPE_LABELS.get(bill_prefix(b["bill_id"]), b["bill_type"])
                by_bill_id[f"{session}|{b['bill_id']}"] = key
            if not b["origin_body"] and body:
                b["origin_body"] = body; b["origin_chamber"] = {"H": "House", "S": "Senate"}.get(body, body)
        return b

    # RSS-derived bills (billnumber / lsrnumber / lsrtitle per the Open States scraper)
    rss_added = collections.Counter()
    for session, items in rss_items.items():
        for it in items:
            bid = it.get("billnumber") or ""
            lsr = it.get("lsrnumber") or ""
            title = it.get("lsrtitle") or it.get("title") or ""
            if not lsr and not bid:
                continue
            body = bid[:1].upper() if bid[:1].upper() in ("H", "S") else ""
            before = len(bills)
            b = ensure_bill(session, lsr or "0", bid, title, body, "rss")
            b["rss"] = {k: v for k, v in it.items() if k not in ("billnumber", "lsrnumber", "lsrtitle")}
            if len(bills) > before:
                rss_added[session] += 1
    if rss_added:
        report.append(f"\nBills added from RSS: {dict(rss_added)}\n")

    # LsrsOnly: LSR -> document id -------------------------------------------
    doc_ids: dict[str, str] = {}
    lsronly_titles: dict[str, str] = {}
    if "LsrsOnly.txt" in texts:
        recs, st = split_records(texts["LsrsOnly.txt"])
        report.append(f"\n## Parse: LsrsOnly.txt\n\n{json.dumps(st)}\n")
        for r in recs:
            if len(r) < 3 or "-" not in r[0]:
                continue
            yy, num = r[0].strip().split("-", 1)
            num = re.sub(r"\D", "", num) or num
            session = ("20" + yy.strip()) if len(yy.strip()) == 2 else yy.strip()
            doc_ids[lsr_key(session, num)] = r[2].strip()
            # a long text field is almost certainly the title
            longest = max((f.strip() for f in r[1:]), key=len, default="")
            if len(longest) > 12 and not longest.isdigit():
                lsronly_titles[lsr_key(session, num)] = longest
    for key, b in bills.items():
        did = doc_ids.get(key)
        if did:
            b["doc_id"] = did
        if not b["title"] and key in lsronly_titles:
            b["title"] = lsronly_titles[key]

    # Docket-derived bills: any (session, LSR) with actions but no row yet
    if "Docket.txt" in texts:
        recs_d, _ = split_records(texts["Docket.txt"])
        first_seen: dict[str, list[str]] = {}
        for r in recs_d:
            if len(r) < 6:
                continue
            session, lsr = r[0].strip(), r[1].strip()
            if session not in wanted_sessions:
                continue
            key = lsr_key(session, lsr)
            if key not in first_seen:
                first_seen[key] = r
        added = 0
        for key, r in first_seen.items():
            if key in bills:
                continue
            session, lsr, _ts, bid, body = (x.strip() for x in r[:5])
            ensure_bill(session, lsr, bid, lsronly_titles.get(key, ""), body if body in ("H", "S") else "", "docket")
            if key in doc_ids:
                bills[key]["doc_id"] = doc_ids[key]
            added += 1
        report.append(f"\nBills added from Docket.txt alone: {added}\n")

    # Legislators --------------------------------------------------------------
    legislators: dict[str, dict] = {}
    roster_text = texts.get("legislators.txt", "")
    if len(roster_text.strip()) < 100:
        # legislators.txt is empty; look for a roster among the sampled index files
        for name, rows in samples.items():
            if looks_like_roster(rows):
                print(f"Using {name} as the legislator roster", flush=True)
                full = fetch(BASE + name)
                if full:
                    roster_text = decode(full)
                    report.append(f"\n**Roster source: {name} (legislators.txt was empty)**\n")
                    break
    if len(roster_text.strip()) >= 100:
        recs, st = split_records(roster_text)
        report.append(f"\n## Parse: legislator roster\n\n{json.dumps(st)}\n")
        for r in recs:
            if len(r) < 6:
                continue
            emp = r[0].strip()
            last, first, middle = r[1].strip(), r[2].strip(), r[3].strip() if len(r) > 3 else ""
            name = " ".join(p for p in [first, middle, last] if p)
            legislators[emp] = {
                "employee_id": emp,
                "name": name,
                "last": last,
                "first": first,
                "body": r[4].strip(),
                "seat": r[5].strip(),
                "extra": [f.strip() for f in r[6:]],
            }
        # distinct values of the trailing columns help identify party/district/county
        for i in range(4, max(len(r) for r in recs) if recs else 0):
            vals = collections.Counter(r[i].strip() for r in recs if len(r) > i)
            report.append(f"- legislators.txt column [{i}] distinct={len(vals)}: sample {dict(vals.most_common(6))}\n")

    # Sponsors -----------------------------------------------------------------
    if "LsrSponsors.txt" in texts:
        recs, st = split_records(texts["LsrSponsors.txt"])
        report.append(f"\n## Parse: LsrSponsors.txt\n\n{json.dumps(st)}\n")
        for r in recs:
            if len(r) < 5:
                continue
            session, lsr, seq, emp, primary = (x.strip() for x in r[:5])
            key = lsr_key(session, lsr)
            if key not in bills:
                continue
            leg = legislators.get(emp, {})
            bills[key]["sponsors"].append({
                "employee_id": emp,
                "name": leg.get("name") or f"employee {emp}",
                "body": leg.get("body", ""),
                "seat": leg.get("seat", ""),
                "primary": primary == "1",
                "seq": int(seq) if seq.isdigit() else 0,
            })
        for b in bills.values():
            b["sponsors"].sort(key=lambda s: (not s["primary"], s["seq"]))

    # Docket -------------------------------------------------------------------
    action_vocab: collections.Counter = collections.Counter()
    if "Docket.txt" in texts:
        recs, st = split_records(texts["Docket.txt"])
        report.append(f"\n## Parse: Docket.txt\n\n{json.dumps(st)}\n")
        for r in recs:
            if len(r) < 6:
                continue
            session, lsr, ts, bid, body, action = (x.strip() for x in r[:6])
            key = lsr_key(session, lsr)
            if key not in bills:
                continue
            when = parse_ts(ts)
            bills[key]["actions"].append({
                "date": when.date().isoformat() if when else ts,
                "ts": when.isoformat(timespec="minutes") if when else ts,
                "body": body,
                "chamber": {"H": "House", "S": "Senate", "G": "Governor"}.get(body, body),
                "text": action,
            })
            if session in wanted_sessions:
                action_vocab[normalize_action(action)] += 1
        for b in bills.values():
            b["actions"].sort(key=lambda a: a["ts"])
        report.append("\n### Most common docket action patterns (normalized)\n\n```\n" +
                      "\n".join(f"{n:6d}  {t[:140]}" for t, n in action_vocab.most_common(120)) + "\n```\n")

    # Roll calls ---------------------------------------------------------------
    roll_calls: dict[str, dict] = {}   # session|body|vote_num
    if "RollCallSummary.txt" in texts:
        recs, st = split_records(texts["RollCallSummary.txt"])
        report.append(f"\n## Parse: RollCallSummary.txt\n\n{json.dumps(st)}\n")
        for r in recs:
            if len(r) < 12:
                continue
            session, body, vnum, ts, bid = (x.strip() for x in r[:5])
            def toint(x: str) -> int:
                try:
                    return int(x.strip())
                except ValueError:
                    return 0
            yeas, nays, present, absent = (toint(x) for x in r[5:9])
            motion = r[11].strip() if len(r) > 11 else ""
            when = parse_ts(ts)
            rc = {
                "id": f"{session}|{body}|{vnum}",
                "session": session,
                "body": body,
                "chamber": {"H": "House", "S": "Senate"}.get(body, body),
                "vote_num": vnum,
                "date": when.date().isoformat() if when else ts,
                "bill_id": norm_bill_id(bid),
                "yeas": yeas,
                "nays": nays,
                "present": present,
                "absent": absent,
                "motion": motion or "[motion not recorded]",
                "extra": [x.strip() for x in r[9:11] + r[12:]],
            }
            roll_calls[rc["id"]] = rc
            key = by_bill_id.get(f"{session}|{rc['bill_id']}")
            if key:
                bills[key]["roll_calls"].append(rc)
        for b in bills.values():
            b["roll_calls"].sort(key=lambda v: (v["date"], v["vote_num"]))

    # Roll-call history: per-legislator aggregates only (file is large) -------
    vote_values: collections.Counter = collections.Counter()
    leg_stats: dict[str, dict] = collections.defaultdict(lambda: {"votes": 0, "yea": 0, "nay": 0, "other": 0})
    if "RollCallHistory.txt" in texts:
        n = 0
        for line in texts["RollCallHistory.txt"].split("\n"):
            if "|" not in line:
                continue
            parts = line.split("|")
            if len(parts) < 7:
                continue
            session, body, vnum, _x, emp, bid, vote = (p.strip() for p in parts[:7])
            if session not in wanted_sessions:
                continue
            n += 1
            vote_values[vote] += 1
            s = leg_stats[f"{session}|{emp}"]
            s["votes"] += 1
            if vote.lower().startswith("yea"):
                s["yea"] += 1
            elif vote.lower().startswith("nay"):
                s["nay"] += 1
            else:
                s["other"] += 1
                s.setdefault("other_values", collections.Counter())[vote] += 1
        report.append(f"\n## Parse: RollCallHistory.txt\n\nrows in wanted sessions: {n:,}\n\nDistinct vote values: {dict(vote_values)}\n")

    # Finalize bills ----------------------------------------------------------
    today = now.date()
    for b in bills.values():
        code, det = classify(b["actions"])
        b["status"] = code
        b["status_label"] = STATUS_LABELS.get(code, code)
        b.update(extract_chapter(b["actions"]))
        b["committee"] = extract_committee(b["actions"])
        b["last_action"] = b["actions"][-1]["text"] if b["actions"] else ""
        b["last_action_date"] = b["actions"][-1]["date"] if b["actions"] else ""
        b["first_action_date"] = b["actions"][0]["date"] if b["actions"] else ""
        b["n_actions"] = len(b["actions"])
        b["n_roll_calls"] = len(b["roll_calls"])
        b["prime_sponsor"] = next((s["name"] for s in b["sponsors"] if s["primary"]), (b["sponsors"][0]["name"] if b["sponsors"] else ""))
        b["beats"] = sorted({beat for beat, pats in BEATS.items() if any(re.search(p, b["title"], re.I) for p in pats)})
        b["closest_margin"] = min((abs(v["yeas"] - v["nays"]) for v in b["roll_calls"]), default=None)
        b["links"] = build_links(b)

    # Emit per-session JSON ----------------------------------------------------
    emitted = []
    for session in wanted_sessions:
        sb = [b for b in bills.values() if b["session"] == session]
        if not sb:
            continue
        sb.sort(key=lambda b: (bill_prefix(b["bill_id"]) or "ZZ", int(re.sub(r"\D", "", b["bill_id"]) or 0), b["lsr"]))
        status_counts = collections.Counter(b["status"] for b in sb)
        leads = story_leads(sb, today)
        payload = {
            "generated_at": now.isoformat(timespec="seconds"),
            "session": session,
            "source": {
                "name": "New Hampshire General Court bill status data dump",
                "url": BASE,
                "note": "Pipe-delimited files published by the General Court; parsed by scripts/fetch_nh_bills.py. Column mapping audited in data/raw/_discovery_report.md.",
            },
            "counts": {
                "bills": len(sb),
                "with_bill_number": sum(1 for b in sb if b["bill_id"]),
                "by_status": dict(status_counts),
                "by_chamber": dict(collections.Counter(b["origin_chamber"] for b in sb)),
                "roll_calls": sum(b["n_roll_calls"] for b in sb),
                "actions": sum(b["n_actions"] for b in sb),
            },
            "status_labels": STATUS_LABELS,
            "story_leads": leads,
            "bills": sb,
        }
        path = os.path.join(out_dir, f"nh_bills_{session}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
        emitted.append({"session": session, "file": os.path.basename(path), "bills": len(sb), "by_status": dict(status_counts)})
        report.append(f"\n## Emitted {path}: {len(sb)} bills; status counts {dict(status_counts)}\n")

    # Legislator aggregates -----------------------------------------------------
    leg_out = []
    for k, s in leg_stats.items():
        session, emp = k.split("|", 1)
        leg = legislators.get(emp, {})
        row = {"session": session, "employee_id": emp, "name": leg.get("name", f"employee {emp}"), "body": leg.get("body", ""), "seat": leg.get("seat", "")}
        row.update({kk: vv for kk, vv in s.items() if kk != "other_values"})
        if "other_values" in s:
            row["other_values"] = dict(s["other_values"])
        leg_out.append(row)
    with open(os.path.join(out_dir, "legislator_votes.json"), "w", encoding="utf-8") as f:
        json.dump({"generated_at": now.isoformat(timespec="seconds"), "legislators": leg_out}, f, ensure_ascii=False, separators=(",", ":"))

    with open(os.path.join(out_dir, "index.json"), "w", encoding="utf-8") as f:
        json.dump({"generated_at": now.isoformat(timespec="seconds"), "sessions": emitted, "source": BASE}, f, indent=2)

    write_report(raw_dir, report)
    print("\n" + "=" * 78 + "\nDISCOVERY REPORT\n" + "=" * 78)
    print("\n".join(report))
    print(json.dumps(emitted, indent=2))
    if not emitted:
        print("FATAL: no bills built for any wanted session", file=sys.stderr)
        return 2
    return 0


def build_links(b: dict) -> list[dict]:
    """Every link is a documented URL pattern; nothing here is fetched or guessed
    per bill. 'kind' lets the page group them."""
    s = b["session"]
    bid = b["bill_id"]
    label = b["bill_label"]
    q_label = urllib.parse.quote_plus(f'"{label}" New Hampshire')
    links: list[dict] = []
    if b.get("doc_id"):
        links.append({"kind": "official", "label": "Bill status page (gc.nh.gov)", "url": f"https://gc.nh.gov/bill_Status/billinfo.aspx?id={b['doc_id']}&inflect=2"})
        links.append({"kind": "official", "label": "Bill text PDF (current version)", "url": f"https://gc.nh.gov/bill_Status/pdf.aspx?id={b['doc_id']}&q=billVersion"})
        links.append({"kind": "official", "label": "Bill text HTML (legacy viewer)", "url": f"https://gc.nh.gov/bill_status/legacy/bs2016/billText.aspx?sy={s}&id={b['doc_id']}&txtFormat=html"})
    links.append({"kind": "official", "label": "Docket (legacy viewer)", "url": f"https://gc.nh.gov/bill_status/legacy/bs2016/bill_docket.aspx?lsr={b['lsr']}&sy={s}&sortoption=&txtsessionyear={s}"})
    links.append({"kind": "official", "label": "Bill status search (gc.nh.gov)", "url": "https://gc.nh.gov/bill_Status/advanced.aspx"})
    if bid:
        links.append({"kind": "trackers", "label": "LegiScan", "url": f"https://legiscan.com/NH/bill/{bid}/{s}"})
        links.append({"kind": "trackers", "label": "Plural (Open States)", "url": f"https://open.pluralpolicy.com/nh/bills/{s}/{bid}/"})
    links.append({"kind": "news", "label": "Google News search", "url": f"https://news.google.com/search?q={q_label}"})
    links.append({"kind": "news", "label": "Google web search", "url": f"https://www.google.com/search?q={q_label}"})
    links.append({"kind": "news", "label": "DuckDuckGo search", "url": f"https://duckduckgo.com/?q={q_label}"})
    links.append({"kind": "news", "label": "New Hampshire Bulletin search", "url": f"https://newhampshirebulletin.com/?s={urllib.parse.quote_plus(label)}"})
    links.append({"kind": "news", "label": "InDepthNH search", "url": f"https://indepthnh.org/?s={urllib.parse.quote_plus(label)}"})
    links.append({"kind": "news", "label": "NHPR search", "url": f"https://www.nhpr.org/search?q={urllib.parse.quote_plus(label)}"})
    links.append({"kind": "official", "label": "Governor's office newsroom (veto messages, signings)", "url": "https://www.governor.nh.gov/news-and-media"})
    if b.get("chapter"):
        links.append({"kind": "official", "label": f"Session laws index (Chapter {b['chapter']})", "url": f"https://gc.nh.gov/bill_status/legacy/bs2016/chapters.aspx?sy={s}"})
    return links


def story_leads(sb: list[dict], today: dt.date) -> dict:
    """Data-driven story hooks. Each lead lists the bills and the evidence used,
    so a reporter can check it against the docket before writing a word."""
    leads: dict = {}
    vetoed = [b for b in sb if b["status"] in ("vetoed", "veto_overridden", "veto_sustained")]
    leads["vetoes"] = {
        "title": "Every veto and what happened to it",
        "why": "Veto fights are the clearest record of where the governor and the legislature's majority split.",
        "bills": [{"bill": b["bill_label"], "title": b["title"], "outcome": b["status_label"], "last_action": b["last_action"], "date": b["last_action_date"], "beats": b["beats"]} for b in vetoed],
    }
    close = []
    for b in sb:
        for v in b["roll_calls"]:
            total = v["yeas"] + v["nays"]
            margin = abs(v["yeas"] - v["nays"])
            if total and (margin <= (3 if v["body"] == "S" else 12)):
                close.append({"bill": b["bill_label"], "title": b["title"], "chamber": v["chamber"], "date": v["date"], "motion": v["motion"], "yeas": v["yeas"], "nays": v["nays"], "margin": margin, "status": b["status_label"]})
    close.sort(key=lambda x: (x["margin"], x["date"]))
    leads["close_votes"] = {"title": "Bills decided by a handful of votes", "why": "A close roll call means a small number of legislators decided the outcome; that is a name-the-names story.", "votes": close[:60]}
    parked = [b for b in sb if b["status"] in ("interim_study", "retained", "rereferred", "tabled")]
    leads["parked"] = {"title": "Bills parked without a final vote", "why": "Interim study, retention, re-referral, and tabling end bills quietly. Who asked for the parking and why.", "bills": [{"bill": b["bill_label"], "title": b["title"], "how": b["status_label"], "date": b["last_action_date"], "committee": b["committee"], "beats": b["beats"]} for b in parked]}
    soon = []
    for b in sb:
        for d in b.get("effective_dates", []):
            try:
                dd = dt.date.fromisoformat(d)
            except ValueError:
                continue
            if today - dt.timedelta(days=30) <= dd <= today + dt.timedelta(days=150):
                soon.append({"bill": b["bill_label"], "title": b["title"], "chapter": b.get("chapter"), "effective": d, "beats": b["beats"]})
    soon.sort(key=lambda x: x["effective"])
    leads["effective_soon"] = {"title": "New laws taking effect in the next few months", "why": "Readers want to know what changes on the date it changes.", "bills": soon}
    contested = sorted([b for b in sb if b["n_roll_calls"]], key=lambda b: -b["n_roll_calls"])[:25]
    leads["most_roll_calls"] = {"title": "The most fought-over bills", "why": "Roll-call count is a proxy for how hard each side pushed.", "bills": [{"bill": b["bill_label"], "title": b["title"], "roll_calls": b["n_roll_calls"], "status": b["status_label"]} for b in contested]}
    cross = []
    for b in sb:
        txt = " || ".join(a["text"] for a in b["actions"]).lower()
        other = "S" if b["origin_body"] == "H" else "H"
        passed_origin = any(re.search(r"ought to pass|passed", a["text"], re.I) and a["body"] == b["origin_body"] for a in b["actions"])
        died_other = b["status"] in ("killed", "interim_study", "rereferred", "tabled") and b["actions"] and b["actions"][-1]["body"] == other
        if passed_origin and died_other:
            cross.append({"bill": b["bill_label"], "title": b["title"], "origin": b["origin_chamber"], "died_in": {"H": "House", "S": "Senate"}[other], "how": b["status_label"], "date": b["last_action_date"], "beats": b["beats"]})
    leads["died_in_other_chamber"] = {"title": "Passed one chamber, died in the other", "why": "House-Senate friction inside one party is an under-covered story.", "bills": cross}
    recent_cut = today - dt.timedelta(days=45)
    late = [b for b in sb if b["last_action_date"] and b["last_action_date"] >= recent_cut.isoformat()]
    late.sort(key=lambda b: b["last_action_date"], reverse=True)
    leads["recent_activity"] = {"title": "What moved in the last 45 days", "why": "Anything still moving after the session ended is news by definition.", "bills": [{"bill": b["bill_label"], "title": b["title"], "last_action": b["last_action"], "date": b["last_action_date"], "status": b["status_label"]} for b in late[:80]]}
    prime = collections.Counter(b["prime_sponsor"] for b in sb if b["prime_sponsor"])
    leads["top_prime_sponsors"] = {"title": "Who filed the most bills", "why": "Volume filers and their success rates.", "sponsors": [{"name": n, "bills": c, "laws": sum(1 for b in sb if b["prime_sponsor"] == n and b["status"] in ("law", "veto_overridden"))} for n, c in prime.most_common(25)]}
    beat_counts = collections.Counter(beat for b in sb for beat in b["beats"])
    leads["beats"] = {"title": "Bills by GSR beat", "why": "Keyword match on titles; a starting list, not a verdict.", "counts": dict(beat_counts.most_common())}
    return leads


def write_report(raw_dir: str, report: list[str]) -> None:
    with open(os.path.join(raw_dir, "_discovery_report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(report))


if __name__ == "__main__":
    sys.exit(main())
