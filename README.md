# Granite State Report tools

## NH Bill Tracker

A public dashboard of every New Hampshire bill, where it stands, and links to
everything on the record about it. Built from the General Court's own
bill-status data and refreshed automatically.

- **Live page:** `https://dexterdow33.github.io/BlogPostPreviewer/nh-bills/` (after GitHub Pages is enabled on the default branch)
- **Data (JSON):** `data/nh_bills_<session>.json`, `data/index.json`, `data/legislator_votes.json`
- **Column-mapping audit:** `data/raw/_discovery_report.md` is rewritten on every run
- **Method and caveats:** `docs/METHODOLOGY.md`
- **Story leads:** `docs/`

### How the refresh works

`scripts/fetch_nh_bills.py` downloads the pipe-delimited files the General
Court publishes at `https://gc.nh.gov/dynamicdatadump/` (LSRs, docket,
sponsors, legislators, roll-call summary and history), parses them, classifies
each bill's outcome from its docket text, builds a per-bill link hub, and
computes data-driven story leads. It has no third-party dependencies.

`.github/workflows/nh-bills.yml` runs the script every day at 07:35 UTC, which
is early morning Eastern. The General Court asks automated clients to use the
site outside 6 a.m. to 9 p.m. Eastern, and the schedule respects that. The
workflow commits the refreshed `data/` files and, on the default branch,
publishes the site to GitHub Pages. It can also be run from the Actions tab.
Runs started by a push or pull request during the day rebuild from the last
saved raw files instead of fetching.

### Run it yourself

```bash
python3 scripts/fetch_nh_bills.py --sessions 2025,2026,2027 --out data
python3 -m http.server 8000   # then open http://localhost:8000/nh-bills/
```

### Caveats

Outcome labels are rule-based readings of docket text and are a sorting aid.
The docket, bill page, and roll-call record on gc.nh.gov are the record, and
every bill on the page links to them. LegiScan, Plural, and news-search links
are built from the bill number, not checked bill by bill.

## Blog Post Previewer

The original jQuery blog post previewer exercise lives in the repository root
(`index.html`, `app.js`, `style.css`).
