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
python -m govdocs archive plan                        # see "Filing documents into the Granite State Archive"
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

## Filing documents into the Granite State Archive

`archive` sends harvested documents to the Granite State Archive at granitestatereport.com/archive/. That page already lists every file in the WordPress media library whose caption carries an `[archive ...]` tag. This command uploads each document and writes that tag, so nothing on the page is edited per document.

```
python -m govdocs archive plan --out plan.csv         # series, counts, every row; no network
python -m govdocs archive publish --dry-run --limit 20
export GSR_WP_USER=...                                  # a WordPress username on granitestatereport.com
export GSR_WP_APP_PASSWORD=...                          # wp-admin > Users > Profile > Application Passwords
python -m govdocs archive publish --series rsa --limit 25
python -m govdocs archive publish --series governor-press
```

**Series (categories).** Each document goes into one series. A series that does not exist yet is created on the page when its first file arrives, with its own heading and filter button:

- RSA chapters from gc.nh.gov go to **New Hampshire Revised Statutes Annotated (RSA)** (`rsa`).
- Governor's press releases and statements go to `governor-press`. Governor's executive orders go to `governor-executive-orders`.
- Court opinions are split by court: `nh-supreme-court`, `federal-courts-nh`, `first-circuit`, `us-supreme-court`.
- Federal material is split by collection: `federal-register`, `congress-bills`, `public-laws`, `cfr`, `congressional-record`, `congress-reports-hearings`, `federal-court-opinions`, `federal-budget`, `presidential-documents`, `federal-rulemaking`.
- Anything else goes to a new series named after its agency (for example "NH Secretary of State"). For the broad `*.nh.gov` sweep, it goes to a series named after its website ("Documents from www.dhhs.nh.gov").

Rules live in `govdocs/archive/rules.json`. Add or edit a rule to create, merge or rename a series. A seed in `seeds/nh.json` can name its series with `archive_series`.

**What each entry says.** The caption records the document's own date when the source gives one (Federal Register, court filing date, GovInfo issue date). Otherwise the page says "Retrieved <date>". It never presents the upload date as the document's date. Every entry links to the page it came from. API keys are stripped from every URL before it is written.

**Web pages become text files.** RSA chapters and press releases are HTML pages, so they are saved as `.txt` captures. Each capture starts with the source URL and retrieval date, followed by the page's own words, with navigation and scripts removed. Nothing is summarized.

**No duplicates.** Each file's SHA-256 is written into its media description. `publish` checks the library for that hash before uploading, so re-runs, and runs from a fresh database, skip anything already there.

**The page change.** The page's script (block 2 of page 6462) needs the update in `wordpress/archive-page-block2.html` before new series appear. Without it:

- Tagged files whose series the page does not know are filed under "Series I · Records obtained under RSA 91-A".
- Only the newest 100 media files are read.

`wordpress/page-script-test.js` renders the page in headless Chromium with a mocked media library and checks both behaviours:

```
NODE_PATH=$(npm root -g) node wordpress/page-script-test.js
```

**Before a large run:**

- Every uploaded file is at a public address as soon as it is uploaded, even before the page lists it.
- Check the WordPress.com plan's storage allowance. The full RSA set is roughly a thousand chapters, and GovInfo collections run far larger. VERIFY the allowance before a bulk run.
- Regulations.gov dockets can include material submitted by private parties. Before publishing that series, review it and add `rights=thirdparty` where it applies.
- The "Extent" and "Dates of material" figures at the top of the page are typed into the page. They do not update as files arrive.

## Tests

```
python -m unittest discover -s tests -v
```
