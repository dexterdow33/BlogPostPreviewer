# NH Bill Tracker: method, sources, and caveats

Version 2 · 2026-09-30 · Granite State Report

## What the tracker is

A static page (`nh-bills/`) that reads JSON rebuilt once a day from the New
Hampshire General Court's own bill-status database. For every legislative
service request (LSR) and bill in the current session it shows the outcome
the docket supports, sponsors with party, committees, the full docket,
recorded roll calls with party splits, sessions already scheduled from
today forward, and a link hub. A "story leads" panel surfaces patterns in
the data. The dataset is public: `data/nh_bills_<session>.json`,
`data/legislators.json`, `data/index.json`.

## Source

The General Court publishes its bill-status tables as pipe-delimited text
files at `https://gc.nh.gov/dynamicdatadump/` (linked from
`https://gc.nh.gov/downloads/`). The files this tracker reads, and the
columns it uses, verified against real rows on 2026-09-30:

| File | Rows (2026-09-30) | Fields | Columns used (0-based) |
|---|---|---|---|
| `LSRs.txt` | 1,387 | 39 | [0] session year · [1] LSR number · [2] title · [3] body of origin · [8] LSR id `YY-NNNN` · [10] bill id · [11] session-law chapter number · [12] subject code · [13],[14] House committee codes · [15] House introduction date · [16] House status code · [19] last House floor-action date · [21],[22] Senate committee codes · [23] Senate introduction date · [24] Senate status code · [25] last action date · [27] last Senate floor-action date · [29] general status code · [30] current committee code · [31],[32] last hearing date-time and room |
| `Docket.txt` | 25,352 | 7 | [0] session · [1] LSR · [2] timestamp · [3] bill id · [4] body · [5] action text |
| `LsrSponsors.txt` | 8,571 | 5 | [0] session · [1] LSR · [2] sequence · [3] legislator id · [4] prime flag |
| `LsrsOnly.txt` | 7,039 | 8 | [0] LSR id · [1] legislator id · [2] bill-page document id · [3] session · [4] `Prime`/`Sponsor` · [5] bill id · [7] title |
| `legislators.txt` | 406 | 15 | [0] legislator id · [1] last · [2] first · [3] middle · [4] body · [6] county code · [7] district · [8] party |
| `RollCallSummary.txt` | 419 | 15 | [0] session · [1] body · [2] vote number · [3] timestamp · [4] bill id · [5] yeas · [6] nays · [7] not voting (not excused, includes presiding) · [8] excused · [11] motion · [12] bill title |
| `RollCallHistory.txt` | 131,199 | 8 | [0] session · [1] body · [2] vote number · [4] legislator id · [6] vote (`Yea`, `Nay`, `Not Voting/Excused`, `Not Voting/Not Excused`, `Presiding`) |
| `Committees.txt` | 60 | 3 | [0] code · [1] name |

How the columns were verified: the Open States New Hampshire scraper gave
the starting positions for the bill id, docket, sponsor and roll-call
files. The rest came from cross-checking real rows: column 11 of
`LSRs.txt` is populated only for bills whose docket says "Chapter N";
columns 7 and 8 of the roll-call summary match the per-legislator
"Not Voting/Not Excused" plus "Presiding" and "Not Voting/Excused" counts
in the history file; the four date columns were checked against docket
dates for HB 54, SB 434 and HB 2026; the legislator id in column 0 of the
roster is the id used in all three sponsor and vote files (353 of 353,
360 of 381 and 406 of 420 ids matched; the rest are members no longer on
the roster). The script writes `data/raw/_discovery_report.md` on every
run with field-count histograms and sample rows so drift shows up.

Two things the first live run showed. `LSRs.txt` and `legislators.txt`
were served as 3-byte files once and full an hour later. The script now
keeps the previous run's copy when a file comes back empty, and says so in
the report. The session RSS feed (`rssFeeds/rssQueryResults.aspx`) timed
out on the server side for 2026 and 2027 and answered "RSS Feed only for
current legislation" for 2025; it is fetched as a fallback only.

## Keying

`Docket.txt` keys carry-over bills by the **current** session year plus the
bare LSR number: HB 561, filed as LSR 25-0001, appears in 2026 rows as
`2026|0001`. `LSRs.txt` lists only the current session (with carry-overs).
The 2025 file in this tracker is therefore rebuilt from docket rows alone
and has no titles or sponsors; the page says so on a banner.

## Courtesy to the source

The General Court asks automated clients to stay off the site between
6 a.m. and 9 p.m. Eastern. The scheduled refresh runs at 07:35 UTC (03:35
EDT / 02:35 EST), fetches each file once, and identifies itself with a
User-Agent naming this repository. A run started by a push or pull request
during the day does not fetch; it rebuilds from the last saved raw files
(`--offline`). A manual run can force a daytime fetch with the
`force_fetch` input; use that sparingly. Pull-request runs validate the
build and do not commit data; commits come from the nightly schedule,
manual runs, and pushes to the default branch.

## Outcome classification

Scheduling lines (`Executive Session`, `Public Hearing`, `Hearing`,
`Work Session`, `Conference Committee Meeting`) and annotations
(`Pending Motion`, `Committee Report`, `Majority/Minority Committee
Report`, `Special Order`, `Reconsider`, consent-calendar moves) are set
aside. The last remaining docket line is the **decisive action**, shown in
the bill drawer. Vetoes and enactment are read from the whole history.

| Code | Label | Rule (case-insensitive) |
|---|---|---|
| `veto_overridden` | Vetoed; override succeeded (law) | "vetoed by governor" followed by "Chapter N", "Law Without Signature" or "Enacted in accordance with Article 44", or by "Veto Overridden" in **both** chambers |
| `veto_sustained` | Vetoed; veto sustained | "vetoed by governor" followed by "Veto Sustained" in either chamber |
| `vetoed` | Vetoed; override pending | "vetoed by governor" with neither of the above |
| `law` | Signed into law / enacted | "Signed by Governor", "Law Without Signature", "Enacted in accordance with Article 44" |
| `died_on_table` | Died on table at session end | "Died on Table" |
| `conference_failed` | Conference refused, not filed, or not signed | "Conference Committee Report: Not Filed / Not Signed Off", "Refused to Accede" |
| `returned_to_house` | Returned to House (Senate Rule 3-21) | "returned to the House per Senate Rule" |
| `nonconcurred` | Died on nonconcurrence | "Nonconcur" as the decisive action |
| `enrolled` | Enrolled / awaiting Governor | "Enrolled" |
| `conference` | Committee of conference | "Committee of Conference" |
| `interim_study` | Interim study | "Interim Study" |
| `retained` | Retained in committee | "Retained in Committee" |
| `rereferred` | Re-referred to committee | "Rereferred to Committee" |
| `tabled` | Laid on table | "Laid on Table" (the Senate records the pending motion on the next line) |
| `killed` | Killed | "Inexpedient to Legislate", "Indefinitely Postponed", "MF" (motion failed) |
| `passed_chamber` | Passed a chamber / in process | "Ought to Pass ... MA", "OT3rdg", "Passed", "Adopted", "Concur" |
| `recommitted` | Recommitted to committee | "Recommit" |
| `committee_report` | Committee report filed; floor action pending | only a committee report after the last floor action |
| `in_committee` | In committee | "Introduced", "Referred to" |
| `unknown` | No final action recorded | nothing matched |

The page groups these into five outcomes: Became law (law, veto
overridden), Vetoed (vetoed, sustained), Killed (killed, died on table,
conference failed, nonconcurred, returned to House), Parked (interim
study, retained, re-referred, tabled), and In process / other.

A veto overridden in one chamber and sustained in the other **stands**.
Four 2026 bills (HB 1766, SB 434, SB 552, SB 661) were overridden in one
chamber only; an earlier version of these rules counted them as overrides.
The corrected count of successful 2026 overrides is seven, matching the
Concord Monitor and NHPR reports of Veto Day, August 19, 2026.

Bills that end the session at "In committee" or "Passed a chamber" with
no further docket entry have no recorded disposition. The General Court
does not write a death line for them; the page leaves them in "In process
/ other" rather than inferring one.

## Other derived fields

- **Chapter**: `LSRs.txt` column 11, else "Chapter N" in the docket.
- **Effective dates**: every "eff. MM/DD/YY(YY)" or "Effective MM/DD/YYYY" in
  the docket; bills with several dates keep them all.
- **Committees**: House and Senate committee codes from `LSRs.txt`, named
  through `Committees.txt`; the "current" committee is column 30.
- **Scheduled from today forward**: scheduling lines whose date is today or
  later (cancelled sessions excluded).
- **Subject**: `LSRs.txt` column 12. The dump ships no key, so the labels in
  `SUBJECT_LABELS` are inferred from the titles filed under each code and
  the raw code is always shown beside the label.
- **County**: roster column 6, codes 1-10. Inferred as alphabetical county
  order; seat counts per code match county populations (Hillsborough 122,
  Rockingham 92, Merrimack 47, Strafford 40, Grafton 27, Cheshire 24,
  Belknap 17, Carroll 16, Sullivan 13, Coos 8). Inferred, not confirmed by
  the General Court.
- **Party split and party-line votes**: per roll call, yeas and nays by
  party from the history file joined to the roster. A vote is "party-line"
  when each caucus has a 60 percent-or-better majority and the two
  majorities point opposite ways.
- **Attendance**: per legislator, counts of "Not Voting/Not Excused" and
  "Not Voting/Excused". A member with every vote marked not voting may
  have resigned or the seat may have been vacant; check before naming.
- **Against party**: a member's recorded yea or nay that goes against
  their caucus's 60-percent majority on that roll call.
- **Beats**: subject codes plus title keywords, listed in `BEATS`. A
  starting list, not a verdict. The GSR house-style skills were not
  available when the list was written.
- **Close vote**: margin of 12 or fewer in the House, 3 or fewer in the
  Senate.

## Link hub

Built in the browser from documented URL patterns and the bill's own
identifiers. Nothing is fetched or guessed per bill.

| Link | Pattern |
|---|---|
| Bill status page | `https://gc.nh.gov/bill_Status/billinfo.aspx?id=<doc id>&inflect=2` |
| Bill text PDF | `https://gc.nh.gov/bill_Status/pdf.aspx?id=<doc id>&q=billVersion` |
| Bill text HTML (legacy viewer) | `https://gc.nh.gov/bill_status/legacy/bs2016/billText.aspx?sy=<session>&id=<doc id>&txtFormat=html` |
| Docket (legacy viewer) | `https://gc.nh.gov/bill_status/legacy/bs2016/bill_docket.aspx?lsr=<lsr>&sy=<session>&sortoption=&txtsessionyear=<session>` |
| LegiScan | `https://legiscan.com/NH/bill/<BILLID>/<session>` |
| Plural (Open States) | `https://open.pluralpolicy.com/nh/bills/<session>/<BILLID>/` |
| News and web searches | Google News, Google, DuckDuckGo, New Hampshire Bulletin, InDepthNH, NHPR and Granite State Report site searches for the quoted bill number plus "New Hampshire" |
| Governor's newsroom | `https://www.governor.nh.gov/news-and-media` |

The document id comes from `LsrsOnly.txt`, which covers current-year LSRs
only; 232 carry-over bills have no bill-page link but keep the docket link,
which works from the LSR number. A search link may return nothing for a
bill nobody has written about.

## Story leads

Computed in `story_leads()` and shown on the page: committee sessions on
the calendar from today forward; what moved in the last 45 days; every
veto with both chambers' votes; roll calls decided by a handful of votes;
party-line roll calls; bills that passed one chamber and died in the
other; parked bills; laws taking effect within 150 days; the most
fought-over bills by roll-call count; who filed the most bills; who missed
the most roll calls; who breaks with their party most; bills by beat.

## Known gaps

- Voice and division votes are not in the roll-call files; only recorded
  roll calls appear.
- 202 sponsor rows reference ids not on the current roster (members who
  left); they show as "Former or unlisted member".
- `LSRs.txt` columns 5, 6, 7, 18, 26, 33-38 are not mapped. Columns 16, 24
  and 29 are status codes without a published key; the page shows them
  raw, labeled as undocumented.
- Prior-session (2025) bills have no titles or sponsors in the current dump.
- If the dump is degraded, the script reuses the previous copy of an empty
  file and says so; if `Docket.txt` itself is missing the run fails loudly
  and the previous day's JSON stays up.
