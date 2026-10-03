# Granite State Report tools

## NH Bill Tracker

A public dashboard of every New Hampshire bill, where it stands, and links to
everything on the record about it. Built from the General Court's own
bill-status data and refreshed automatically.

- **Live page:** https://granitestatereport.com/nh-bill-tracker/ (embeds `nh-bills/` from this repo; rebuild the embed with `scripts/build_wp_embed.py` when the page code changes)
- **Standalone page:** `https://dexterdow33.github.io/BlogPostPreviewer/nh-bills/` once GitHub Pages is enabled (Settings → Pages → Source: GitHub Actions); the nightly workflow deploys it automatically after that
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

`.github/workflows/nh-bills.yml` offers the script a slot every hour from
02:17 to 09:17 UTC, which is overnight Eastern. GitHub often starts scheduled
runs hours late, so the first slot that pulls a full set of files does the
refresh and the later slots stop early. The General Court asks automated
clients to use the site outside 6 a.m. to 9 p.m. Eastern, and the workflow
respects that: any run that lands in those hours, scheduled or not, rebuilds
from the last saved raw files instead of fetching. The workflow commits the
refreshed `data/` files and, on the default branch, publishes the site to
GitHub Pages. It can also be run from the Actions tab.
Runs started by a push or pull request during the day rebuild from the last
saved raw files instead of fetching, and pull-request runs validate the build
without committing data.

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
