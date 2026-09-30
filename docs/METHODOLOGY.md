# NH Bill Tracker: method, sources, and caveats

Version 1 · 2026-09-30 · Granite State Report

## What the tracker is

A static page (`nh-bills/`) that reads JSON built once a day from the New
Hampshire General Court's own bill-status database. It shows every
legislative service request (LSR) and bill for a session, the outcome the
docket supports, sponsors, the full docket, recorded roll calls, and a link
hub for each bill. A "story leads" panel surfaces patterns in the data.

## Source

The General Court publishes its bill-status tables as pipe-delimited text
files at `https://gc.nh.gov/dynamicdatadump/` (linked from
`https://gc.nh.gov/downloads/`). The files this tracker reads:

| File | What it holds | Fields used |
|---|---|---|
| `LSRs.txt` | one row per LSR / bill | session year [0], LSR number [1], title [2], body of origin [3], expanded bill id [9], bill id [10] |
| `LsrsOnly.txt` | LSR id to bill-page document id | `YY-NNNN` [0], document id [2] |
| `Docket.txt` | one row per docket action | session [0], LSR [1], timestamp [2], bill id [3], body [4], action text [5] |
| `LsrSponsors.txt` | sponsor rows | session [0], LSR [1], sequence [2], legislator employee id [3], prime flag [4] |
| `legislators.txt` | roster | employee id [0], last [1], first [2], middle [3], body [4], seat [5] |
| `RollCallSummary.txt` | roll-call tallies | session [0], body [1], vote number [2], timestamp [3], bill id [4], yeas [5], nays [6], present [7], absent [8], motion [11] |
| `RollCallHistory.txt` | per-legislator votes | session [0], body [1], vote number [2], employee id [4], bill id [5], vote [6] |

Field positions were taken from the Open States New Hampshire scraper, which
has parsed these files for years, and are re-checked on every run: the
script writes `data/raw/_discovery_report.md` with each file's field-count
histogram, sample rows, and the raw fields of several known bills. Columns
not listed above are kept in the report until they are mapped. **See the
"Column audit" section at the end of this document for what the first real
run showed.**

## Courtesy to the source

The General Court asks automated clients to stay off the site between
6 a.m. and 9 p.m. Eastern. The refresh runs at 07:35 UTC (03:35 EDT / 02:35
EST), fetches each file once, and identifies itself with a User-Agent that
names this repository.

## Outcome classification

Each bill's outcome is read from its docket text with ordered rules. The
last action decides, except for vetoes, which look at the whole history:

| Code | Label on the page | Rule (case-insensitive) |
|---|---|---|
| `veto_overridden` | Vetoed; override passed | a "vetoed" action followed by an action containing "overrid" |
| `veto_sustained` | Vetoed; veto sustained | a "vetoed" action followed by "sustain" or "fail" |
| `vetoed` | Vetoed by Governor | "vetoed" with no later override or sustain action |
| `law` | Signed into law | "signed by governor", "became law without", or "chapter N" |
| `enrolled` | Enrolled / awaiting Governor | "enrolled" |
| `conference` | Committee of conference | "committee of conference" |
| `interim_study` | Interim study | "interim study" |
| `retained` | Retained in committee | "retained in committee" |
| `rereferred` | Re-referred to committee | "re-referred" / "rereferred" |
| `tabled` | Laid on table | "laid on table" / "tabled" |
| `killed` | Killed | "inexpedient to legislate", "indefinitely postpone", "killed", "not adopted", "failed" |
| `passed_chamber` | Passed a chamber / in process | "ought to pass", "passed", "adopted" |
| `hearing` | Hearing scheduled | "hearing" |
| `in_committee` | In committee | "introduced", "referred to" |
| `unknown` | Status not classified | nothing matched; read the docket |

The page groups these into five outcomes for the summary tiles and chart:
Became law (law, veto overridden), Vetoed (vetoed, sustained), Killed,
Parked (interim study, retained, re-referred, tabled), and In process /
other (everything else).

These rules are a sorting aid. They will misread an unusual docket. Every
bill on the page links to its docket and bill page so the label can be
checked in seconds. Do not quote a label without reading the docket.

## Other derived fields

- **Chapter and effective dates**: regular expressions for "Chapter N" and
  "eff. MM/DD/YYYY" in docket text. Bills with several effective dates keep
  them all.
- **Committee**: the first "referred to ..." phrase in the docket.
- **Beats**: keyword matches on the bill title against a list in the script
  (`BEATS`). A beat tag is a starting list, not a verdict.
- **Close vote**: a roll call with a margin of 12 or fewer in the House or 3
  or fewer in the Senate.

## Link hub

Every link is a documented URL pattern filled with the bill's identifiers.
Nothing is fetched or guessed per bill.

| Link | Pattern |
|---|---|
| Bill status page | `https://gc.nh.gov/bill_Status/billinfo.aspx?id=<doc id>&inflect=2` |
| Bill text PDF | `https://gc.nh.gov/bill_Status/pdf.aspx?id=<doc id>&q=billVersion` |
| Bill text HTML (legacy viewer) | `https://gc.nh.gov/bill_status/legacy/bs2016/billText.aspx?sy=<session>&id=<doc id>&txtFormat=html` |
| Docket (legacy viewer) | `https://gc.nh.gov/bill_status/legacy/bs2016/bill_docket.aspx?lsr=<lsr>&sy=<session>&sortoption=&txtsessionyear=<session>` |
| LegiScan | `https://legiscan.com/NH/bill/<BILLID>/<session>` |
| Plural (Open States) | `https://open.pluralpolicy.com/nh/bills/<session>/<BILLID>/` |
| News and web searches | Google News, Google, DuckDuckGo, New Hampshire Bulletin, InDepthNH, NHPR site searches for the quoted bill number plus "New Hampshire" |
| Governor's newsroom | `https://www.governor.nh.gov/news-and-media` (veto messages and signing statements are posted here; no per-bill pattern exists) |

A search link may return nothing for a bill nobody has written about.

## Story leads

Computed in `story_leads()` in the script and shown on the page:

- Every veto and its outcome
- Roll calls decided by a handful of votes
- Bills that passed one chamber and died in the other
- Bills parked without a final vote
- New laws taking effect within the next 150 days (or the last 30)
- The most fought-over bills, by roll-call count
- What moved in the last 45 days
- Who filed the most bills, and how many became law
- Bills by GSR beat

## Known gaps

- Voice votes and division votes are not in the roll-call files; only
  recorded roll calls appear.
- Sponsor names come from `legislators.txt`. If that file is stale or a
  legislator is missing, the page shows "employee <id>".
- Carry-over bills keep the prior year's LSR prefix and may lack a bill-page
  document id in the current year's mapping; those bills still get a docket
  link, which works from the LSR number and session year.
- The page shows what the data dump says. If the dump is degraded (the
  script refuses to build from an `LSRs.txt` under 1 KB), the previous day's
  data stays up and the workflow run fails loudly.

## Column audit

_Filled from the first real run; see `data/raw/_discovery_report.md` for the
current run's sample rows._
