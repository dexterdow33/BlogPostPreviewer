#!/usr/bin/env python3
"""
fetch_nh_bills.py - build the Granite State Report NH Bill Tracker dataset.

Source
------
The New Hampshire General Court publishes its bill-status database as
pipe-delimited text files at https://gc.nh.gov/dynamicdatadump/ . This script
downloads them (or, with --offline, reads the copies in data/raw), writes a
discovery report so the column mapping can be audited on every run, and
builds the JSON the static dashboard in nh-bills/ reads.

Column map (verified against real rows on 2026-09-30; see docs/METHODOLOGY.md)
-----------------------------------------------------------------------------
LSRs.txt (39 fields, one row per LSR in the current session, carry-overs included)
  [0] session year   [1] LSR number   [2] title   [3] body of origin (H/S)
  [4] type number    [8] LSR id "YY-NNNN"   [9] expanded bill id "HB  0561"
  [10] bill id "HB561"   [11] session-law chapter number (zero padded, blank if none)
  [12] subject code (three letters)   [13] first House committee code   [14] second House committee code
  [15] House introduction date   [16] House status code   [19] last House floor action date
  [21] first Senate committee code   [22] second Senate committee code   [23] Senate introduction date
  [24] Senate status code   [25] last action date   [27] last Senate floor action date
  [29] general status code   [30] current / last committee code   [31] last hearing date-time   [32] hearing room
Docket.txt (7 fields): session | LSR | timestamp | bill id | body (H/S) | action text | update timestamp
  Carry-over bills are keyed by the CURRENT session year plus the bare LSR number.
LsrSponsors.txt (5): session | LSR | sequence | legislator id | prime flag (1/0)
LsrsOnly.txt (8): LSR id | legislator id | bill-page document id | session | "Prime"/"Sponsor" | bill id | sponsor body | title
legislators.txt (15): id | last | first | middle | body | legacy id | county code | district | party | address... | email
RollCallSummary.txt (15): session | body | vote no. | timestamp | bill id | yeas | nays | not voting | excused | | | motion | title | |
RollCallHistory.txt (8): session | body | vote no. | record id | legislator id | bill id | vote | date
Committees.txt (3): code | name | abbreviation

Politeness: the General Court asks automated clients to stay off the site
between 6 a.m. and 9 p.m. Eastern. The workflow runs this early morning Eastern
and fetches each file once. Standard library only.
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

REQUIRED_FILES = {
    "LSRs.txt": "one row per legislative service request / bill in the current session",
    "LsrsOnly.txt": "sponsor rows with bill-page document id and title",
    "Docket.txt": "docket actions (one row per action)",
    "LsrSponsors.txt": "sponsors in sequence, with prime flag",
    "legislators.txt": "legislator roster",
    "RollCallSummary.txt": "roll-call tallies",
    "RollCallHistory.txt": "per-legislator roll-call votes",
    "Committees.txt": "committee codes and names",
}
OPTIONAL_FILES: list[str] = []

TYPE_LABELS = {
    "HB": "House Bill", "SB": "Senate Bill", "HR": "House Resolution", "SR": "Senate Resolution",
    "HCR": "House Concurrent Resolution", "SCR": "Senate Concurrent Resolution",
    "HJR": "House Joint Resolution", "SJR": "Senate Joint Resolution",
    "CACR": "Constitutional Amendment Concurrent Resolution",
    "HCO": "House Concurrent Order", "SCO": "Senate Concurrent Order", "PET": "Petition",
    "SSHB": "Special Session House Bill", "SSSB": "Special Session Senate Bill",
}

# Subject codes from LSRs.txt column 12. The General Court does not publish a
# key in the dump; these labels are INFERRED from the titles filed under each
# code and are shown on the page with the raw code. Unlisted codes show as-is.
SUBJECT_LABELS = {
    "EDG": "Education (K-12)", "EDF": "Education (postsecondary)", "STG": "State government",
    "CCP": "Criminal code and procedure", "ELE": "Elections", "PMH": "Pharmacy, public and mental health",
    "ZAP": "Zoning and planning", "MOT": "Motor vehicles", "ENU": "Energy and utilities",
    "MUN": "Municipal government", "OCC": "Occupations and professions", "INS": "Insurance",
    "TAL": "Taxes (local and property)", "TAS": "Taxes (state)", "ENA": "Environment (permits, waste)",
    "ENC": "Environment (conservation, water)", "CHI": "Children and youth services", "PRP": "Property and housing",
    "AGR": "Agriculture", "BAI": "Appropriations and business", "MIL": "Military and veterans", "TRA": "Transportation",
    "EPR": "Employment and labor", "CTS": "Courts", "WMM": "Welfare and Medicaid", "ANI": "Animals",
    "CIV": "Civil law", "CAC": "Constitutional amendments", "DOM": "Domestic relations", "FNG": "Fish and game",
    "BAF": "Banking and finance", "MEM": "Memorials and namings", "RET": "Retirement system", "LAB": "Liquor and alcohol",
    "RTK": "Right-to-Know", "DIS": "Discrimination and civil rights", "POL": "Police", "COU": "Counties",
    "LEG": "Legislature", "GAM": "Gaming",
}
# legislators.txt column 6. INFERRED: codes 1-10 in alphabetical county order;
# seat counts per code match county populations.
COUNTY_CODES = {"1": "Belknap", "2": "Carroll", "3": "Cheshire", "4": "Coos", "5": "Grafton",
                "6": "Hillsborough", "7": "Merrimack", "8": "Rockingham", "9": "Strafford", "10": "Sullivan"}

# GSR beat keywords (assumption: the house-style skills were not available when
# this was written, so these are the editor's stated interests plus obvious New
# Hampshire accountability beats). Title keywords plus subject codes.
BEATS = {
    "Right-to-Know / transparency": {"codes": {"RTK"}, "words": [r"\b91-a\b", r"right[- ]to[- ]know", r"public records?", r"transparen", r"open meeting", r"governmental records", r"ombudsman"]},
    "Government accountability / ethics": {"codes": {"LEG"}, "words": [r"\bethics\b", r"conflict of interest", r"accountab", r"\baudit", r"whistleblow", r"inspector general", r"lobby", r"oversight"]},
    "Courts / policing / justice": {"codes": {"CCP", "POL", "CTS"}, "words": [r"\bcourt", r"judicial", r"\bjudge", r"\bbail\b", r"sentenc", r"criminal", r"\bpolice\b", r"law enforcement", r"prosecut", r"new trial", r"parole", r"body-worn"]},
    "Education / school choice": {"codes": {"EDG", "EDF"}, "words": [r"education freedom", r"\bschool", r"\bstudent", r"\bteacher", r"curricul", r"charter", r"tuition", r"\bpupil"]},
    "Taxes / spending / public money": {"codes": {"TAS", "TAL", "BAI", "RET"}, "words": [r"\btax", r"appropriat", r"\bbudget", r"\bfee\b", r"\bfees\b", r"revenue", r"\btoll", r"\bbond", r"surplus"]},
    "Housing / land use / local control": {"codes": {"ZAP", "PRP", "MUN", "COU"}, "words": [r"housing", r"zoning", r"land use", r"tenant", r"landlord", r"eviction", r"short[- ]term rental", r"accessory dwelling", r"\bmunicipal", r"planning board"]},
    "Energy / utilities / environment": {"codes": {"ENU", "ENA", "ENC"}, "words": [r"\benergy\b", r"electric", r"\butility", r"utilities", r"\bpfas\b", r"landfill", r"solar", r"nuclear", r"net metering", r"\bratepayer"]},
    "Elections / voting": {"codes": {"ELE"}, "words": [r"\belection", r"\bvoter", r"\bvoting\b", r"\bballot", r"absentee", r"redistrict", r"campaign finance"]},
    "Guns / civil liberties": {"codes": {"CIV", "DIS"}, "words": [r"firearm", r"\bgun\b", r"\bguns\b", r"second amendment", r"free speech", r"first amendment", r"religious", r"privacy"]},
    "Health / social services": {"codes": {"PMH", "WMM", "CHI"}, "words": [r"\bhealth", r"medicaid", r"\bhospital", r"mental", r"substance", r"opioid", r"abortion", r"reproductive", r"vaccine", r"\bdcyf\b", r"foster"]},
    "Immigration": {"codes": set(), "words": [r"immigra", r"\bice\b", r"sanctuary", r"citizenship", r"\bborder"]},
    "Gender / sex-based classification": {"codes": set(), "words": [r"\bgender\b", r"biological sex", r"bathroom", r"locker room", r"transgender"]},
    "Cannabis / alcohol / gaming": {"codes": {"GAM", "LAB"}, "words": [r"cannabis", r"marijuana", r"\balcohol", r"liquor", r"\bgaming\b", r"charitable gaming", r"\bcasino", r"lottery", r"sports betting"]},
}

STATUS_LABELS = {
    "law": "Signed into law / enacted",
    "veto_overridden": "Vetoed; override succeeded (law)",
    "veto_sustained": "Vetoed; veto sustained",
    "vetoed": "Vetoed; override pending or not taken up",
    "enrolled": "Enrolled / awaiting Governor",
    "conference": "Committee of conference",
    "conference_failed": "Conference refused, not filed, or not signed",
    "recommitted": "Recommitted to committee",
    "nonconcurred": "Died on nonconcurrence",
    "returned_to_house": "Returned to House (Senate Rule 3-21)",
    "died_on_table": "Died on table at session end",
    "interim_study": "Interim study",
    "retained": "Retained in committee",
    "rereferred": "Re-referred to committee",
    "tabled": "Laid on table",
    "killed": "Killed",
    "passed_chamber": "Passed a chamber / in process",
    "committee_report": "Committee report filed; floor action pending",
    "hearing": "Hearing scheduled",
    "in_committee": "In committee",
    "unknown": "No final action recorded",
}
GROUP_OF = {
    "law": "law", "veto_overridden": "law",
    "vetoed": "vetoed", "veto_sustained": "vetoed",
    "killed": "killed", "died_on_table": "killed", "conference_failed": "killed", "nonconcurred": "killed", "returned_to_house": "killed",
    "interim_study": "parked", "retained": "parked", "rereferred": "parked", "tabled": "parked",
}

# Docket lines that schedule or annotate rather than dispose of a bill.
SCHEDULING_RE = re.compile(r"^\s*(==[\w ]+==\s*)?(Executive Session|Full Committee Work Session|Subcommittee Work Session|Division \w+ Work Session|Work Session|Public Hearing|Continued Public Hearing|Hearing|Conference Committee Meeting)\b", re.I)
ANNOTATION_RE = re.compile(r"^\s*(Pending Motion|No Pending Motion|Minority Committee Report|Majority Committee Report|Committee Report|Special Order|Without Objection the Senate will take up|Rules suspension|Referral Waived|Reconsider\b|[A-Z]{2,4} \d+ was Removed from the Consent Calendar|Sen\. [A-Za-z'. -]+ Moved to (Print|Take)|Removed from (the )?Consent|Placed on (the )?Consent|Lay .* on the table failed)", re.I)
SCHED_DATE_RE = re.compile(r"(Executive Session|Full Committee Work Session|Subcommittee Work Session|Work Session|Public Hearing|Continued Public Hearing|Hearing|Conference Committee Meeting)[^0-9]*?(\d{1,2})/(\d{1,2})/(\d{4})(?:,?\s*(?:Room\s*)?([^,;]*?),?\s*)?(?:(\d{1,2}:\d{2})\s*(am|pm))?", re.I)


# --------------------------------------------------------------------------- #
# HTTP
# --------------------------------------------------------------------------- #
def fetch(url: str, timeout: int = 180, retries: int = 3, max_bytes: int | None = None) -> bytes | None:
    sep = "&" if "?" in url else "?"
    busted = f"{url}{sep}x={int(time.time())}"
    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(busted, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = resp.read(max_bytes) if max_bytes else resp.read()
                print(f"  GET {url} -> {resp.status} {len(data):,} bytes", flush=True)
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
    return data.decode("utf-8-sig", errors="replace").replace("﻿", "")


# --------------------------------------------------------------------------- #
# Pipe-delimited parsing
# --------------------------------------------------------------------------- #
def modal_field_count(lines: list[str]) -> int:
    counts = collections.Counter(len(l.split("|")) for l in lines if "|" in l)
    return counts.most_common(1)[0][0] if counts else 0


def split_records(text: str, expected: int | None = None) -> tuple[list[list[str]], dict]:
    lines = [l for l in text.replace("\r\n", "\n").replace("\r", "\n").split("\n") if l.strip() != ""]
    if expected is None:
        expected = modal_field_count(lines)
    records: list[list[str]] = []
    bad = joined = 0
    buf: list[str] | None = None
    for line in lines:
        parts = line.split("|")
        if buf is not None:
            merged = buf[:-1] + [buf[-1] + "\n" + parts[0]] + parts[1:]
            if len(merged) == expected:
                records.append(merged); joined += 1; buf = None; continue
            if len(merged) < expected:
                buf = merged; continue
            bad += 1; buf = None
        if len(parts) == expected:
            records.append(parts)
        elif len(parts) < expected:
            buf = parts
        else:
            records.append(parts); bad += 1
    if buf is not None:
        bad += 1
    return records, {"lines": len(lines), "records": len(records), "expected_fields": expected, "joined": joined, "irregular": bad}


def field_histogram(lines: list[str]) -> list[tuple[int, int]]:
    return collections.Counter(len(l.split("|")) for l in lines if l.strip()).most_common(5)


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
DATE_FORMATS = ["%m/%d/%Y %I:%M:%S %p", "%m/%d/%Y %H:%M:%S", "%m/%d/%Y", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"]


def parse_ts(s: str) -> dt.datetime | None:
    s = (s or "").strip()
    for fmt in DATE_FORMATS:
        try:
            return dt.datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None


def iso_date(s: str) -> str:
    d = parse_ts(s)
    return d.date().isoformat() if d else ""


def norm_bill_id(raw: str) -> str:
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
    t = re.sub(r"\d{1,2}/\d{1,2}/\d{2,4}", "<date>", text)
    t = re.sub(r"#?\s*\d{4}-\d+[hs]\b", "<amend>", t)
    t = re.sub(r"\b\d+\b", "<n>", t)
    return re.sub(r"\s+", " ", t).strip()


def is_scheduling(text: str) -> bool:
    return bool(SCHEDULING_RE.match(text))


def is_annotation(text: str) -> bool:
    return bool(ANNOTATION_RE.match(text))


# --------------------------------------------------------------------------- #
# Classification
# --------------------------------------------------------------------------- #
VOTE_RE = re.compile(r"RC\s*(\d+)\s*Y?\s*-\s*(\d+)\s*N?", re.I)


def classify(actions: list[dict]) -> tuple[str, dict]:
    """(status code, details). Uses the last substantive action, except vetoes
    and enactment, which are read from the whole history."""
    det: dict = {}
    if not actions:
        return "unknown", det
    texts = [a["text"] for a in actions]

    veto_idx = [i for i, t in enumerate(texts) if re.search(r"vetoed by (the )?governor", t, re.I)]
    if veto_idx:
        vi = veto_idx[-1]
        after = actions[vi + 1:]
        veto: dict = {"veto_date": actions[vi]["date"], "house": None, "senate": None}
        m = re.search(r"(\d{1,2}/\d{1,2}/\d{4})", texts[vi])
        if m:
            veto["veto_date"] = iso_date(m.group(1)) or veto["veto_date"]
        for a in after:
            t = a["text"]
            side = "house" if a["body"] == "H" else "senate" if a["body"] == "S" else None
            if side and re.search(r"veto (overridden|sustained)", t, re.I):
                v = VOTE_RE.search(t)
                veto[side] = {"result": "overridden" if re.search(r"veto overridden", t, re.I) else "sustained",
                              "vote": f"{v.group(1)}-{v.group(2)}" if v else "", "date": a["date"]}
        det["veto"] = veto
        if any(re.search(r"chapter\s*\d+|law without signature|enacted in accordance", a["text"], re.I) for a in after):
            return "veto_overridden", det
        if any(re.search(r"veto sustained", a["text"], re.I) for a in after):
            return "veto_sustained", det
        if veto["house"] and veto["senate"] and veto["house"]["result"] == veto["senate"]["result"] == "overridden":
            return "veto_overridden", det
        return "vetoed", det

    if any(re.search(r"signed by (the )?governor|law without signature|enacted in accordance with article 44", t, re.I) for t in texts):
        return "law", det

    substantive = [a for a in actions if not is_scheduling(a["text"]) and not is_annotation(a["text"])]
    last = substantive[-1]["text"] if substantive else texts[-1]
    det["decisive_action"] = last
    rules = [
        ("died_on_table", r"died on (the )?table"),
        ("conference_failed", r"conference committee report[:;]?\s*(not signed off|not filed)|refuse[sd]? to accede"),
        ("recommitted", r"\brecommit"),
        ("returned_to_house", r"returned to the house per senate rule"),
        ("nonconcurred", r"non-?concur"),
        ("enrolled", r"\benrolled\b"),
        ("conference", r"committee of conference|conference committee"),
        ("interim_study", r"interim study"),
        ("retained", r"retained in committee"),
        ("rereferred", r"re-?referred to committee"),
        ("tabled", r"laid on (the )?table"),
        ("killed", r"inexpedient to legislate|indefinitely postpone|bill killed|not adopted|\bMF\b"),
        ("passed_chamber", r"ought to pass|\bpassed\b|\badopted\b|OT3rdg|concur"),
        ("in_committee", r"introduced|referred to"),
    ]
    for code, pat in rules:
        if re.search(pat, last, re.I):
            return code, det
    if substantive is not actions and is_annotation(texts[-1]) and re.search(r"committee report", texts[-1], re.I):
        return "committee_report", det
    if is_scheduling(texts[-1]):
        return "hearing", det
    return "unknown", det


def extract_effective(actions: list[dict]) -> tuple[dict, list[str]]:
    out: dict = {}
    dates: list[str] = []
    for a in actions:
        t = a["text"]
        m = re.search(r"chapter\s*(\d+)", t, re.I)
        if m:
            out["chapter"] = int(m.group(1))
        for em in re.finditer(r"eff(?:ective)?\.?\s*(\d{1,2}/\d{1,2}/\d{2,4})", t, re.I):
            d = em.group(1)
            for fmt in ("%m/%d/%Y", "%m/%d/%y"):
                try:
                    iso = dt.datetime.strptime(d, fmt).date().isoformat()
                    if iso not in dates:
                        dates.append(iso)
                    break
                except ValueError:
                    continue
        if re.search(r"eff(?:ective)?\.?\s*(upon|on)\s*passage", t, re.I):
            out["effective_on_passage"] = True
    return out, sorted(dates)


def docket_committee(actions: list[dict]) -> str | None:
    for a in actions:
        m = re.search(r"referred to (?:the )?(?:committee on )?([A-Z][A-Za-z ,&/'\-]+?)(?:;|\.|\s+HJ|\s+SJ|\s+\d|$)", a["text"])
        if m:
            return m.group(1).strip()
    return None


def next_events(actions: list[dict], today: dt.date) -> list[dict]:
    out = []
    for a in actions:
        m = SCHED_DATE_RE.search(a["text"])
        if not m or a["text"].lstrip().startswith("==CANCELLED=="):
            continue
        try:
            d = dt.date(int(m.group(4)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            continue
        if d >= today:
            out.append({"date": d.isoformat(), "kind": re.sub(r"\s+", " ", m.group(1)).title(), "text": re.sub(r"\s+", " ", a["text"]).strip()})
    out.sort(key=lambda e: e["date"])
    dedup: list[dict] = []
    for e in out:
        if not any(x["text"] == e["text"] for x in dedup):
            dedup.append(e)
    return dedup[:6]


def parse_rss_items(xml_text: str) -> list[dict]:
    import xml.etree.ElementTree as ET
    items: list[dict] = []
    try:
        root = ET.fromstring(xml_text.encode("utf-8", errors="replace"))
    except ET.ParseError:
        return items
    for item in root.iter("item"):
        items.append({child.tag.split("}")[-1].lower(): (child.text or "").strip() for child in item})
    return items


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sessions", default="2025,2026,2027")
    ap.add_argument("--out", default="data")
    ap.add_argument("--raw-limit-mb", type=float, default=6.0)
    ap.add_argument("--offline", action="store_true", help="read files from <out>/raw instead of fetching")
    ap.add_argument("--today", default=None, help="override today's date (YYYY-MM-DD) for reproducible builds")
    args = ap.parse_args()

    out_dir, raw_dir = args.out, os.path.join(args.out, "raw")
    os.makedirs(os.path.join(raw_dir, "samples"), exist_ok=True)
    wanted = [s.strip() for s in args.sessions.split(",") if s.strip()]
    now = dt.datetime.now(dt.timezone.utc)
    today = dt.date.fromisoformat(args.today) if args.today else now.date()
    report: list[str] = [f"# NH dynamicdatadump discovery report\n\nGenerated {now.isoformat(timespec='seconds')}{' (offline rebuild from data/raw)' if args.offline else ''}\n"]

    # ---- get the files -------------------------------------------------------
    texts: dict[str, str] = {}
    # When the General Court's files were last pulled. A daytime rebuild reads the
    # saved copies, so its build time says nothing about how fresh the data is.
    fetched_marker = os.path.join(raw_dir, "_fetched_at.txt")
    reused_copy = False
    if args.offline:
        for name in list(REQUIRED_FILES) + OPTIONAL_FILES:
            p = os.path.join(raw_dir, name)
            if os.path.exists(p):
                texts[name] = open(p, encoding="utf-8").read()
        report.append("_Offline rebuild: files read from data/raw._\n")
    else:
        print("Fetching directory index", flush=True)
        idx = fetch(BASE)
        if idx:
            html = decode(idx)
            links = sorted(set(re.findall(r'href="([^"]+\.(?:txt|csv|zip|pdf|xls|xlsx))"', html, re.I)))
            open(os.path.join(raw_dir, "_directory_index.html"), "w", encoding="utf-8").write(html)
            report.append("## Directory index\n\n" + ("\n".join(f"- {l}" for l in links) if links else "_no file links in index_") + "\n")
        for name in list(REQUIRED_FILES) + OPTIONAL_FILES:
            print(f"Fetching {name}", flush=True)
            data = fetch(BASE + name)
            if data is None:
                report.append(f"## {name}\n\n_not available_\n"); continue
            text = decode(data)
            if len(text.strip()) < 64:
                # The dump sometimes serves a 3-byte file. Keep yesterday's copy if we have one.
                prev = os.path.join(raw_dir, name)
                if os.path.exists(prev) and os.path.getsize(prev) > 1024:
                    text = open(prev, encoding="utf-8").read()
                    reused_copy = True
                    report.append(f"## {name}\n\n**Served empty ({len(data)} bytes); reused the previous run's copy.**\n")
                    print(f"  {name} served empty; reusing previous copy", flush=True)
                else:
                    report.append(f"## {name}\n\n**Served empty ({len(data)} bytes) and no previous copy exists.**\n")
                    continue
            texts[name] = text
            if len(data) / 1_000_000 <= args.raw_limit_mb:
                open(os.path.join(raw_dir, name), "w", encoding="utf-8", newline="\n").write(text)
        if all(n in texts for n in REQUIRED_FILES) and not reused_copy:
            open(fetched_marker, "w", encoding="utf-8").write(now.isoformat(timespec="seconds") + "\n")
        for session in wanted:
            print(f"Fetching RSS bill list for {session}", flush=True)
            data = fetch(RSS_URL.format(session=session), retries=1, timeout=90)
            if data:
                open(os.path.join(raw_dir, f"rss_{session}.xml"), "w", encoding="utf-8", newline="\n").write(decode(data))

    fetched_at = open(fetched_marker, encoding="utf-8").read().strip() if os.path.exists(fetched_marker) else None
    report.append(f"_Files last pulled from the General Court: {fetched_at or 'unknown'}._\n")

    for name, text in texts.items():
        lines = [l for l in text.replace("\r\n", "\n").split("\n") if l.strip()]
        hist = field_histogram(lines)
        report.append(f"## {name}\n\n{REQUIRED_FILES.get(name, '')}\n\n- bytes: {len(text.encode('utf-8')):,}; rows: {len(lines):,}; sha256: {hashlib.sha256(text.encode('utf-8')).hexdigest()[:16]}\n"
                      f"- field-count histogram: {', '.join(f'{k}: {v}' for k, v in hist)}\n\n")
        for l in lines[:2]:
            report.append("```\n" + "\n".join(f"[{i}]={p[:140]}" for i, p in enumerate(l.split("|"))) + "\n```\n")

    if "Docket.txt" not in texts:
        write_report(raw_dir, report)
        print("FATAL: Docket.txt unavailable", file=sys.stderr)
        return 2

    # ---- committees -----------------------------------------------------------
    committees: dict[str, str] = {}
    if "Committees.txt" in texts:
        for r, _ in [split_records(texts["Committees.txt"])]:
            for row in r:
                if len(row) >= 2:
                    committees[row[0].strip().upper()] = row[1].strip()

    def cname(code: str) -> str:
        code = (code or "").strip()
        return committees.get(code.upper(), code) if code else ""

    # ---- legislators ----------------------------------------------------------
    legislators: dict[str, dict] = {}
    if "legislators.txt" in texts:
        recs, st = split_records(texts["legislators.txt"])
        report.append(f"\n## Parse: legislators.txt\n\n{json.dumps(st)}\n")
        for r in recs:
            if len(r) < 9:
                continue
            first, middle, last = r[2].strip(), r[3].strip(), r[1].strip()
            legislators[r[0].strip()] = {
                "id": r[0].strip(), "name": " ".join(p for p in (first, middle, last) if p), "last": last,
                "body": r[4].strip(), "chamber": {"H": "House", "S": "Senate"}.get(r[4].strip(), r[4].strip()),
                "county_code": r[6].strip(), "county": COUNTY_CODES.get(r[6].strip(), ""), "district": r[7].strip(),
                "party": r[8].strip().upper(), "email": r[14].strip() if len(r) > 14 else "",
            }

    def leg_ref(emp: str) -> dict:
        leg = legislators.get(emp)
        if not leg:
            return {"id": emp, "name": f"Former or unlisted member (id {emp})", "party": "", "body": "", "district": "", "county": ""}
        return {"id": emp, "name": leg["name"], "party": leg["party"], "body": leg["body"], "district": leg["district"], "county": leg["county"]}

    # ---- bills from LSRs.txt ----------------------------------------------------
    bills: dict[str, dict] = {}
    by_bill_id: dict[str, str] = {}
    lsr_rows: list[list[str]] = []
    if "LSRs.txt" in texts:
        lsr_rows, st = split_records(texts["LSRs.txt"])
        report.append(f"\n## Parse: LSRs.txt\n\n{json.dumps(st)}\n\nSession years: {dict(collections.Counter(r[0].strip() for r in lsr_rows))}\n")
    for r in lsr_rows:
        if len(r) < 33:
            continue
        session, lsr, title, body = r[0].strip(), r[1].strip(), r[2].strip(), r[3].strip()
        bid = norm_bill_id(r[10].strip() or r[9].strip())
        title_note = ""
        m = re.match(r"^\(([^)]*)\)\s*(.*)$", title, re.S)
        if m:
            title_note, title = m.group(1).strip(), m.group(2).strip()
        key = lsr_key(session, lsr)
        chapter = int(r[11]) if r[11].strip().isdigit() else None
        house_c = [cname(c) for c in (r[13], r[14]) if c.strip()]
        senate_c = [cname(c) for c in (r[21], r[22]) if c.strip()]
        bills[key] = {
            "session": session, "lsr": lsr.lstrip("0") or "0", "lsr_id": r[8].strip() or f"{session[-2:]}-{lsr.zfill(4)}",
            "bill_id": bid, "bill_label": bill_label(bid) if bid else "", "bill_type": TYPE_LABELS.get(bill_prefix(bid), bill_prefix(bid) or "LSR"),
            "title": title, "title_note": title_note, "origin_body": body, "origin_chamber": {"H": "House", "S": "Senate"}.get(body, body),
            "subject_code": r[12].strip(), "subject": SUBJECT_LABELS.get(r[12].strip(), r[12].strip()),
            "committees": {"house": sorted(set(house_c), key=house_c.index), "senate": sorted(set(senate_c), key=senate_c.index), "current": cname(r[30])},
            "dates": {"house_intro": iso_date(r[15]), "house_last_floor": iso_date(r[19]), "senate_intro": iso_date(r[23]), "senate_last_floor": iso_date(r[27]), "last_action_official": iso_date(r[25])},
            "status_codes": {"house": r[16].strip(), "senate": r[24].strip(), "general": r[29].strip()},
            "last_hearing": {"when": r[31].strip(), "room": r[32].strip()} if r[31].strip() else None,
            "chapter": chapter, "source_row": "LSRs.txt", "sponsors": [], "actions": [], "roll_calls": [],
        }
        if bid:
            by_bill_id[f"{session}|{bid}"] = key

    # ---- doc ids and titles from LsrsOnly ---------------------------------------
    doc_ids: dict[str, str] = {}
    only_titles: dict[str, str] = {}
    only_prime: dict[str, set] = collections.defaultdict(set)
    if "LsrsOnly.txt" in texts:
        recs, st = split_records(texts["LsrsOnly.txt"])
        report.append(f"\n## Parse: LsrsOnly.txt\n\n{json.dumps(st)}\n")
        for r in recs:
            if len(r) < 8 or "-" not in r[0]:
                continue
            yy, num = r[0].strip().split("-", 1)
            session = r[3].strip() or (("20" + yy) if len(yy) == 2 else yy)
            key = lsr_key(session, re.sub(r"\D", "", num))
            doc_ids[key] = r[2].strip()
            only_titles[key] = r[7].strip()
            if r[4].strip().lower() == "prime":
                only_prime[key].add(r[1].strip())

    def ensure_bill(session: str, lsr: str, bid: str, body: str, source: str) -> dict:
        key = lsr_key(session, lsr)
        if key not in bills:
            bid = norm_bill_id(bid)
            title = only_titles.get(key, "")
            bills[key] = {
                "session": session, "lsr": lsr.lstrip("0") or "0", "lsr_id": f"{session[-2:]}-{(lsr.lstrip('0') or '0').zfill(4)}",
                "bill_id": bid, "bill_label": bill_label(bid) if bid else "", "bill_type": TYPE_LABELS.get(bill_prefix(bid), bill_prefix(bid) or "LSR"),
                "title": title, "title_note": "", "origin_body": body, "origin_chamber": {"H": "House", "S": "Senate"}.get(body, body or ""),
                "subject_code": "", "subject": "", "committees": {"house": [], "senate": [], "current": ""},
                "dates": {}, "status_codes": {}, "last_hearing": None, "chapter": None, "source_row": source,
                "sponsors": [], "actions": [], "roll_calls": [],
            }
            if bid:
                by_bill_id[f"{session}|{bid}"] = key
        return bills[key]

    # ---- docket -------------------------------------------------------------------
    recs, st = split_records(texts["Docket.txt"])
    report.append(f"\n## Parse: Docket.txt\n\n{json.dumps(st)}\n\nSession years: {dict(collections.Counter(r[0].strip() for r in recs))}\n")
    vocab: collections.Counter = collections.Counter()
    for r in recs:
        if len(r) < 6:
            continue
        session, lsr, ts, bid, body, action = (x.strip() for x in r[:6])
        if session not in wanted:
            continue
        b = ensure_bill(session, lsr, bid, body if body in ("H", "S") else "", "docket")
        when = parse_ts(ts)
        b["actions"].append({"date": when.date().isoformat() if when else ts, "ts": when.isoformat(timespec="minutes") if when else ts,
                             "body": body, "chamber": {"H": "House", "S": "Senate", "G": "Governor"}.get(body, body), "text": re.sub(r"\s+", " ", action).strip()})
        vocab[normalize_action(action)] += 1
    for b in bills.values():
        b["actions"].sort(key=lambda a: a["ts"])
        if b.get("doc_id") is None and lsr_key(b["session"], b["lsr"]) in doc_ids:
            b["doc_id"] = doc_ids[lsr_key(b["session"], b["lsr"])]
    report.append("\n### Most common docket action patterns\n\n```\n" + "\n".join(f"{n:6d}  {t[:140]}" for t, n in vocab.most_common(80)) + "\n```\n")

    # ---- sponsors -------------------------------------------------------------------
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
            ref = leg_ref(emp)
            bills[key]["sponsors"].append({"id": emp, "name": ref["name"], "party": ref["party"],
                                           "primary": primary == "1" or emp in only_prime.get(key, set()),
                                           "seq": int(seq) if seq.isdigit() else 0})
        for b in bills.values():
            seen = set(); uniq = []
            for s in sorted(b["sponsors"], key=lambda s: (not s["primary"], s["seq"])):
                if s["id"] not in seen:
                    seen.add(s["id"]); s.pop("seq", None); uniq.append(s)
            b["sponsors"] = uniq

    # ---- roll calls -------------------------------------------------------------------
    rcs: dict[str, dict] = {}
    if "RollCallSummary.txt" in texts:
        recs, st = split_records(texts["RollCallSummary.txt"])
        report.append(f"\n## Parse: RollCallSummary.txt\n\n{json.dumps(st)}\n")
        for r in recs:
            if len(r) < 13:
                continue
            def toint(x: str) -> int:
                try: return int(x.strip())
                except ValueError: return 0
            session, body, vnum, ts, bid = (x.strip() for x in r[:5])
            when = parse_ts(ts)
            rc = {"id": f"{session}|{body}|{vnum}", "session": session, "body": body, "chamber": {"H": "House", "S": "Senate"}.get(body, body),
                  "vote_num": vnum, "date": when.date().isoformat() if when else ts, "bill_id": norm_bill_id(bid),
                  "yeas": toint(r[5]), "nays": toint(r[6]), "not_voting": toint(r[7]), "excused": toint(r[8]),
                  "motion": r[11].strip() or "[motion not recorded]", "bill_title": r[12].strip(), "party_split": {}}
            rcs[rc["id"]] = rc
            key = by_bill_id.get(f"{session}|{rc['bill_id']}")
            if key:
                bills[key]["roll_calls"].append(rc)
                if not bills[key]["title"] and rc["bill_title"]:
                    bills[key]["title"] = rc["bill_title"]
        for b in bills.values():
            b["roll_calls"].sort(key=lambda v: (v["date"], int(v["vote_num"]) if v["vote_num"].isdigit() else 0))

    # ---- roll-call history: party splits and legislator stats -----------------------
    leg_stats: dict[str, dict] = {}
    if "RollCallHistory.txt" in texts:
        votes_by_rc: dict[str, list[tuple[str, str]]] = collections.defaultdict(list)
        for line in texts["RollCallHistory.txt"].split("\n"):
            p = line.split("|")
            if len(p) < 7 or p[0].strip() not in wanted:
                continue
            votes_by_rc[f"{p[0].strip()}|{p[1].strip()}|{p[2].strip()}"].append((p[4].strip(), p[6].strip()))
        vote_values: collections.Counter = collections.Counter()
        for rcid, votes in votes_by_rc.items():
            rc = rcs.get(rcid)
            split: dict[str, dict] = collections.defaultdict(lambda: {"yea": 0, "nay": 0, "other": 0})
            for emp, v in votes:
                vote_values[v] += 1
                party = legislators.get(emp, {}).get("party", "?") or "?"
                k = "yea" if v.startswith("Yea") else "nay" if v.startswith("Nay") else "other"
                split[party][k] += 1
            majority = {pty: ("yea" if c["yea"] > c["nay"] else "nay") if (c["yea"] + c["nay"]) and max(c["yea"], c["nay"]) / (c["yea"] + c["nay"]) >= 0.6 else None for pty, c in split.items()}
            if rc is not None:
                rc["party_split"] = {pty: dict(c) for pty, c in split.items() if pty in ("R", "D", "I")}
                r_, d_ = split.get("R"), split.get("D")
                rc["party_line"] = bool(r_ and d_ and majority.get("R") and majority.get("D") and majority["R"] != majority["D"])
            session, body = rcid.split("|")[0], rcid.split("|")[1]
            for emp, v in votes:
                s = leg_stats.setdefault(f"{session}|{emp}", {"session": session, "roll_calls": 0, "yea": 0, "nay": 0, "not_voting": 0, "excused": 0, "presiding": 0, "against_party": 0, "party_votes": 0})
                s["roll_calls"] += 1
                if v.startswith("Yea"): s["yea"] += 1
                elif v.startswith("Nay"): s["nay"] += 1
                elif "Not Excused" in v: s["not_voting"] += 1
                elif "Excused" in v: s["excused"] += 1
                elif v.startswith("Presiding"): s["presiding"] += 1
                party = legislators.get(emp, {}).get("party", "")
                if party and majority.get(party) and v[:3] in ("Yea", "Nay"):
                    s["party_votes"] += 1
                    if v[:3].lower() != majority[party]:
                        s["against_party"] += 1
        report.append(f"\n## Parse: RollCallHistory.txt\n\nDistinct vote values: {dict(vote_values)}\n")

    # ---- finalize bills -----------------------------------------------------------------
    for b in bills.values():
        code, det = classify(b["actions"])
        b["status"], b["status_label"], b["group"] = code, STATUS_LABELS.get(code, code), GROUP_OF.get(code, "process")
        b["status_detail"] = det
        eff, dates = extract_effective(b["actions"])
        if b.get("chapter") is None and eff.get("chapter"):
            b["chapter"] = eff["chapter"]
        b["effective_dates"] = dates
        if eff.get("effective_on_passage"):
            b["effective_on_passage"] = True
        b["committee"] = b["committees"].get("current") or docket_committee(b["actions"]) or ""
        b["last_action"] = b["actions"][-1]["text"] if b["actions"] else ""
        b["last_action_date"] = b["actions"][-1]["date"] if b["actions"] else ""
        b["first_action_date"] = b["actions"][0]["date"] if b["actions"] else ""
        b["n_actions"], b["n_roll_calls"] = len(b["actions"]), len(b["roll_calls"])
        b["next_events"] = next_events(b["actions"], today)
        b["prime_sponsor"] = next((s["name"] for s in b["sponsors"] if s["primary"]), b["sponsors"][0]["name"] if b["sponsors"] else "")
        b["prime_party"] = next((s["party"] for s in b["sponsors"] if s["primary"]), "")
        parties = {s["party"] for s in b["sponsors"] if s["party"] in ("R", "D")}
        b["bipartisan"] = len(parties) == 2
        beats = set()
        for beat, spec in BEATS.items():
            if b["subject_code"] in spec["codes"] or any(re.search(w, b["title"], re.I) for w in spec["words"]):
                beats.add(beat)
        b["beats"] = sorted(beats)
        b["closest_margin"] = min((abs(v["yeas"] - v["nays"]) for v in b["roll_calls"]), default=None)
        # Per-bill links are built in the browser (nh-bills/app.js, linkHub) from doc_id, LSR and bill id;
        # the URL patterns are documented in docs/METHODOLOGY.md.

    # ---- emit -------------------------------------------------------------------------------
    emitted = []
    for session in wanted:
        sb = [b for b in bills.values() if b["session"] == session]
        if not sb:
            continue
        sb.sort(key=lambda b: (bill_prefix(b["bill_id"]) or "ZZ", int(re.sub(r"\D", "", b["bill_id"]) or 0), int(b["lsr"]) if b["lsr"].isdigit() else 0))
        titled = sum(1 for b in sb if b["title"])
        note = ""
        if titled < len(sb) * 0.5:
            note = ("Prior-session bills rebuilt from the docket file alone. The General Court's current data dump does not carry titles or "
                    "sponsors for bills that finished in an earlier session, so most rows here show a bill number and docket only.")
        payload = {
            "generated_at": now.isoformat(timespec="seconds"), "fetched_at": fetched_at, "as_of": today.isoformat(), "session": session,
            "session_note": note,
            "source": {"name": "New Hampshire General Court bill status data dump", "url": BASE,
                       "note": "Pipe-delimited files published by the General Court; parsed by scripts/fetch_nh_bills.py. Column mapping documented in docs/METHODOLOGY.md and audited in data/raw/_discovery_report.md."},
            "counts": {"bills": len(sb), "with_title": titled, "by_status": dict(collections.Counter(b["status"] for b in sb)),
                       "by_group": dict(collections.Counter(b["group"] for b in sb)), "by_chamber": dict(collections.Counter(b["origin_chamber"] for b in sb)),
                       "roll_calls": sum(b["n_roll_calls"] for b in sb), "actions": sum(b["n_actions"] for b in sb),
                       "with_upcoming_events": sum(1 for b in sb if b["next_events"])},
            "status_labels": STATUS_LABELS, "group_of": GROUP_OF,
            "link_patterns": {
                "bill_status_page": "https://gc.nh.gov/bill_Status/billinfo.aspx?id=<doc_id>&inflect=2",
                "bill_text_pdf": "https://gc.nh.gov/bill_Status/pdf.aspx?id=<doc_id>&q=billVersion",
                "bill_text_html": "https://gc.nh.gov/bill_status/legacy/bs2016/billText.aspx?sy=<session>&id=<doc_id>&txtFormat=html",
                "docket": "https://gc.nh.gov/bill_status/legacy/bs2016/bill_docket.aspx?lsr=<lsr>&sy=<session>&sortoption=&txtsessionyear=<session>",
                "legiscan": "https://legiscan.com/NH/bill/<bill_id>/<session>",
                "plural": "https://open.pluralpolicy.com/nh/bills/<session>/<bill_id>/"},
            "subject_codes": {c: SUBJECT_LABELS.get(c, c) for c in sorted({b["subject_code"] for b in sb if b["subject_code"]})},
            "story_leads": story_leads(sb, today, leg_stats, legislators, session),
            "bills": sb,
        }
        path = os.path.join(out_dir, f"nh_bills_{session}.json")
        json.dump(payload, open(path, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
        emitted.append({"session": session, "file": os.path.basename(path), "bills": len(sb), "with_title": titled, "by_group": payload["counts"]["by_group"]})
        report.append(f"\n## Emitted {path}: {len(sb)} bills; {json.dumps(payload['counts']['by_status'])}\n")

    leg_out = []
    for k, st_ in leg_stats.items():
        session, emp = k.split("|", 1)
        row = dict(leg_ref(emp)); row["session"] = session; row.update(st_)
        leg_out.append(row)
    roster = {emp: {kk: vv for kk, vv in leg.items() if kk != "email"} for emp, leg in legislators.items()}
    json.dump({"generated_at": now.isoformat(timespec="seconds"), "roster": roster, "county_codes_inferred": COUNTY_CODES, "stats": leg_out},
              open(os.path.join(out_dir, "legislators.json"), "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    old = os.path.join(out_dir, "legislator_votes.json")
    if os.path.exists(old):
        os.remove(old)
    json.dump({"generated_at": now.isoformat(timespec="seconds"), "fetched_at": fetched_at, "as_of": today.isoformat(), "sessions": emitted, "source": BASE}, open(os.path.join(out_dir, "index.json"), "w", encoding="utf-8"), indent=2)

    write_report(raw_dir, report)
    print("\n" + "=" * 78 + "\nDISCOVERY REPORT\n" + "=" * 78 + "\n" + "\n".join(report))
    print(json.dumps(emitted, indent=2))
    if not emitted:
        print("FATAL: no bills built", file=sys.stderr)
        return 2
    return 0


def story_leads(sb: list[dict], today: dt.date, leg_stats: dict, legislators: dict, session: str) -> dict:
    """Data-driven story hooks with the evidence attached."""
    L: dict = {}
    def brief(b: dict, **extra) -> dict:
        d = {"bill": b["bill_label"] or b["lsr_id"], "title": b["title"], "status": b["status_label"], "date": b["last_action_date"], "beats": b["beats"], "sponsor": b["prime_sponsor"], "party": b["prime_party"]}
        d.update(extra); return d

    vetoed = [b for b in sb if b["status"] in ("vetoed", "veto_overridden", "veto_sustained")]
    L["vetoes"] = {"title": "Every veto and what happened to it", "why": "Veto fights are the clearest record of where the governor and the legislature's majority split.",
                   "bills": [brief(b, outcome=b["status_label"], veto=b["status_detail"].get("veto"), last_action=b["last_action"]) for b in vetoed]}

    close = []
    for b in sb:
        for v in b["roll_calls"]:
            total, margin = v["yeas"] + v["nays"], abs(v["yeas"] - v["nays"])
            if total and margin <= (3 if v["body"] == "S" else 12):
                close.append({"bill": b["bill_label"], "title": b["title"], "chamber": v["chamber"], "date": v["date"], "motion": v["motion"], "yeas": v["yeas"], "nays": v["nays"], "margin": margin, "status": b["status_label"], "party_split": v.get("party_split", {})})
    close.sort(key=lambda x: (x["margin"], x["date"]))
    L["close_votes"] = {"title": "Bills decided by a handful of votes", "why": "A close roll call means a few legislators decided the outcome. Name them.", "votes": close[:80], "total": len(close)}

    up = [b for b in sb if b["next_events"]]
    up.sort(key=lambda b: b["next_events"][0]["date"])
    L["upcoming_events"] = {"title": "Committee sessions already on the calendar", "why": "Work the docket says is scheduled from today forward, mostly interim-study bills the public assumes are dead.",
                            "bills": [brief(b, next=b["next_events"][0]) for b in up]}

    parked = [b for b in sb if b["group"] == "parked"]
    L["parked"] = {"title": "Bills parked without a final vote", "why": "Interim study, retention, re-referral and tabling end bills quietly. Who asked for the parking, and why.",
                   "bills": [brief(b, how=b["status_label"], committee=b["committee"]) for b in parked]}

    soon = []
    for b in sb:
        for d in b.get("effective_dates", []):
            dd = dt.date.fromisoformat(d)
            if today - dt.timedelta(days=30) <= dd <= today + dt.timedelta(days=150):
                soon.append(brief(b, chapter=b.get("chapter"), effective=d))
    soon.sort(key=lambda x: x["effective"])
    L["effective_soon"] = {"title": "Laws taking effect soon", "why": "Readers want to know what changes on the day it changes.", "bills": soon}

    contested = sorted([b for b in sb if b["n_roll_calls"]], key=lambda b: -b["n_roll_calls"])[:30]
    L["most_roll_calls"] = {"title": "The most fought-over bills", "why": "Roll-call count is a proxy for how hard each side pushed.", "bills": [brief(b, roll_calls=b["n_roll_calls"]) for b in contested]}

    cross = []
    for b in sb:
        other = "S" if b["origin_body"] == "H" else "H"
        passed_origin = any(a["body"] == b["origin_body"] and re.search(r"ought to pass.*\bMA\b|ought to pass.*OT3rdg", a["text"], re.I) for a in b["actions"])
        died_other = b["group"] in ("killed", "parked") and b["actions"] and b["actions"][-1]["body"] == other
        if passed_origin and died_other:
            cross.append(brief(b, origin=b["origin_chamber"], died_in={"H": "House", "S": "Senate"}[other], how=b["status_label"]))
    L["died_in_other_chamber"] = {"title": "Passed one chamber, died in the other", "why": "House-Senate friction inside one party is under-covered.", "bills": cross}

    party_line = []
    for b in sb:
        for v in b["roll_calls"]:
            if v.get("party_line"):
                party_line.append({"bill": b["bill_label"], "title": b["title"], "chamber": v["chamber"], "date": v["date"], "motion": v["motion"], "yeas": v["yeas"], "nays": v["nays"], "party_split": v.get("party_split", {}), "status": b["status_label"]})
    party_line.sort(key=lambda x: x["date"], reverse=True)
    L["party_line_votes"] = {"title": "Party-line roll calls", "why": "Votes where the two caucuses split cleanly; the crossovers on each are the story.", "votes": party_line[:120], "total": len(party_line)}

    cut = (today - dt.timedelta(days=45)).isoformat()
    late = sorted([b for b in sb if b["last_action_date"] >= cut], key=lambda b: b["last_action_date"], reverse=True)
    L["recent_activity"] = {"title": "What moved in the last 45 days", "why": "Anything still moving after the session ended is news by definition.", "bills": [brief(b, last_action=b["last_action"]) for b in late[:100]], "total": len(late)}

    prime = collections.Counter(b["prime_sponsor"] for b in sb if b["prime_sponsor"])
    L["top_prime_sponsors"] = {"title": "Who filed the most bills", "why": "Volume filers and their success rates.",
                               "sponsors": [{"name": n, "party": next((b["prime_party"] for b in sb if b["prime_sponsor"] == n), ""), "bills": c,
                                             "laws": sum(1 for b in sb if b["prime_sponsor"] == n and b["group"] == "law"),
                                             "killed": sum(1 for b in sb if b["prime_sponsor"] == n and b["group"] == "killed")} for n, c in prime.most_common(30)]}

    rows = []
    for k, s in leg_stats.items():
        sess, emp = k.split("|", 1)
        if sess != session or s["roll_calls"] < 20:
            continue
        leg = legislators.get(emp, {})
        rows.append({"name": leg.get("name", f"id {emp}"), "party": leg.get("party", ""), "chamber": leg.get("chamber", ""), "district": leg.get("district", ""), "county": leg.get("county", ""),
                     "roll_calls": s["roll_calls"], "not_voting": s["not_voting"], "excused": s["excused"], "against_party": s["against_party"], "party_votes": s["party_votes"],
                     "not_voting_pct": round(100 * s["not_voting"] / s["roll_calls"], 1), "against_party_pct": round(100 * s["against_party"] / s["party_votes"], 1) if s["party_votes"] else 0})
    L["attendance"] = {"title": "Who missed the most roll calls", "why": "\"Not voting / not excused\" is the General Court's own label. Ask the member why.",
                       "legislators": sorted(rows, key=lambda r: -r["not_voting"])[:40]}
    L["party_breakers"] = {"title": "Who breaks with their party most", "why": "Members whose recorded votes most often go against their caucus majority.",
                           "legislators": sorted([r for r in rows if r["party_votes"] >= 30], key=lambda r: -r["against_party_pct"])[:40]}

    L["beats"] = {"title": "Bills by GSR beat", "why": "Subject code plus title keywords; a starting list, not a verdict.", "counts": dict(collections.Counter(beat for b in sb for beat in b["beats"]).most_common())}
    return L


def write_report(raw_dir: str, report: list[str]) -> None:
    open(os.path.join(raw_dir, "_discovery_report.md"), "w", encoding="utf-8").write("\n".join(report))


if __name__ == "__main__":
    sys.exit(main())
