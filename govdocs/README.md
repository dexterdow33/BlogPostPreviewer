# govdocs: federal and New Hampshire public-document collector

This tool builds a searchable index (SQLite, exportable to CSV or JSON Lines) of public documents from official federal APIs and New Hampshire state websites. It can also download the files.

It does not copy "every government document on the internet," and nothing can. Federal volume alone runs to millions of records. So the tool works one source and one date window at a time, and every run can be resumed.

## What it collects

| Source | Jurisdiction | What | Key needed |
|---|---|---|---|
| `federalregister` | federal | Rules, proposed rules, notices, presidential documents (federalregister.gov API) | none |
| `govinfo` | federal | GPO GovInfo packages: bills, public laws, CFR, Congressional Record, committee reports, hearings, US court opinions, budget, presidential documents | api.data.gov key |
| `regulationsgov` | federal | Regulations.gov rulemaking and docket documents (not public comments) | api.data.gov key |
| `congress` | federal | Congress.gov bill and resolution metadata with latest action | api.data.gov key |
| `courtlistener` | NH + federal | Opinions from NH Supreme Court (`nh`), D.N.H. (`nhd`), Bankr. D.N.H. (`nhb`), First Circuit (`ca1`), SCOTUS | free CourtListener token |
| `nh-crawl` | NH | Crawls NH state sites listed in `govdocs/seeds/nh.json` and indexes linked PDF, Word, Excel and similar files | none |

Wherever a source offers an official API, the tool uses it rather than scraping pages. NH has no statewide documents API, so the NH sites are crawled.

CourtListener is run by the Free Law Project, a nonprofit, not a government. It republishes court opinions. When you download, the tool fetches the court's own copy first (for example the PDF on www.courts.nh.gov) and uses CourtListener's mirror only when the court's copy isn't available.

## Setup

```
cd govdocs
pip install -r requirements.txt        # just `requests`
export GOVDOCS_CONTACT="you@example.org"   # goes in the User-Agent so site admins can reach you
export DATA_GOV_API_KEY=...            # free: https://api.data.gov/signup/
export COURTLISTENER_TOKEN=...         # free account at courtlistener.com
```

If you don't set a key, the tool uses `DEMO_KEY`, which works but is heavily rate-limited. You can also give each service its own key: `GOVINFO_API_KEY`, `REGULATIONS_GOV_API_KEY`, `CONGRESS_API_KEY`.

## Use

```
python -m govdocs sources                                   # list sources
python -m govdocs collect federalregister --since 2026-09-01
python -m govdocs collect govinfo --since 2026-01-01 --collections BILLS,PLAW
python -m govdocs collect courtlistener --courts nh,nhd --since 2025-01-01
python -m govdocs collect nh-crawl --max-pages 300          # per seed
python -m govdocs collect all --since 2026-09-22            # everything, last week
python -m govdocs stats
python -m govdocs download --source federalregister --limit 50 --out files
python -m govdocs export --format csv --out index.csv
```

- If you leave out `--since`, the window is the last 7 days, so a first run can't turn into a months-long pull by accident.
- Re-running is safe. Documents are keyed on (source, ID) and updated in place, and `stats` shows first and last dates per source.
- `--query` filters by full text on `federalregister` and `regulationsgov`.
- The default delay is 1 second between requests to the same host (`--delay` changes it). The crawler also obeys `robots.txt` rules and `Crawl-delay`.

## How each source is walked, and its limits

- **Federal Register:** one publication day per query, because the API pages through at most 2,000 results per query. It covers documents published since 1994. VERIFY that start year before a full historical pull.
- **GovInfo:** uses the `/published` endpoint (filtered by issue date) one month at a time, following `offsetMark` pagination. Default collections: BILLS, PLAW, CRPT, CHRG, CREC, FR, CFR, USCOURTS, BUDGET, CPD. Download links come from each package's summary, which the tool fetches only when you run `download`.
- **Regulations.gov:** one posted-date day per query. The API returns at most 5,000 records per query, and the tool logs a warning if a day hits that cap.
- **Congress.gov:** filters on the bill's `updateDate` (last change), not its introduction date. Full bill text is in GovInfo `BILLS`.
- **CourtListener:** the `clusters` endpoint filtered by `docket__court` and `date_filed`.
- **NH crawl:** for each seed, reads the sitemaps listed in robots.txt (or `/sitemap.xml`), then crawls the seed's allowed domains breadth-first up to `--max-depth` and `--max-pages`. It records document links but doesn't download them. Dates come from sitemap `lastmod` when present, and otherwise stay blank. It never guesses a date.

## Before relying on it

- **The live APIs have not been exercised yet.** The build environment's network policy blocked every .gov host. The code follows each API's published documentation and was checked against it where the docs could be reached: GovInfo's GitHub docs, the Congress.gov README, and the CourtListener schema, which was queried live. The tests run offline against mocked responses. Run a small `--limit 5` pull from each source before a large one.
- **Seed list:** the NH seed hosts were confirmed through search results and one CourtListener record, not by loading them. Each seed in `seeds/nh.json` carries a `checked` note saying how it was confirmed. Add agencies there as you need them.
- An index row means a document is listed at a URL. The row is not the document itself. Cite from the downloaded file or the source page.

## Tests

```
python -m unittest discover -s tests -v
```
