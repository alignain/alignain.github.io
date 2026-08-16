# Data Splicer

## Inflation tracker

`inflation-tracker.qmd` is a Quarto page that pulls live All-India CPI data from
MoSPI's open API and renders headline trend, rural/urban split,
division-wise inflation, contributions to the headline rate, and a 2012-base
historical view. Rebuild it any time with:

```
quarto render inflation-tracker.qmd
```

Output: `inflation-tracker.html`,
self-contained. API pulls are cached in `data_cache/` — the current year
refreshes after 12 hours; delete the folder to force a full re-download.
New CPI data lands around the 12th of each month at 4 pm IST.

A Shiny app to join macro series published at different base years
(WPI, IIP, CPI, GDP/GVA old vs new series, ...) into one continuous series.

## Files

| file | what it is |
|------|------------|
| `splice-core.R` | period parsing, the three splicing methods, demo data, Notes copy — no UI |
| `app.R` | the app: plotly chart, DT table. The one front end, run locally and published |
| `build-shinylive.R` | stages `app.R` + `splice-core.R` and exports to `splicer-app/` |


`app.R` sources `splice-core.R`, so the splicing logic lives in exactly one
place and the desktop and browser versions can never drift apart.




## Run

From R / RStudio:

```r
shiny::runApp("software")          # full app, from the repo root
```

To rebuild the browser version (the publish workflow does this automatically
on every push):

```
cd software
Rscript build-shinylive.R
```

Then serve `splicer-app/` over http to test it — Shinylive needs a real
server, opening `index.html` from disk will not work:

```r
httpuv::runStaticServer(dir = "software/splicer-app", port = 8765)
```

## Data format

CSV or Excel, one row per period:

| period | index_base_2004_05 | index_base_2011_12 |
|--------|--------------------|--------------------|
| 2010   | 141.9              |                    |
| 2012   | 156.1              | 106.9              |
| 2013   | 163.4              | 112.5              |
| 2015   |                    | 118.2              |

- **period**: `YYYY`, `YYYY-MM`, `Jan 2012`, `2012 Q1`, or a date.
- Following columns: the same indicator at each base, ordered
  **oldest base → newest base** (you can reorder in the app).
- Leave cells blank where a base was not published. Consecutive bases
  must overlap in at least one period.
- More than two bases are allowed; they are chained from the newest
  backwards.

`example_data.csv` in this folder shows the format (illustrative numbers,
not official statistics).

## Methods

1. **Ratio splice at a link period** — old series × (new/old) at one chosen
   overlap period; preserves old growth rates.
2. **Average-overlap ratio** — conversion factor = mean ratio over the whole
   overlap; robust to a single odd period.
3. **Growth-rate retropolation** — extend the new series backwards with the
   old series' period-on-period growth rates.

Optional rebasing of the final series (chosen period = 100), chart
(originals dotted, spliced solid), full table, CSV/Excel download.

## Published version

<https://alignain.github.io/software/splicer-app/> — built by the publish
workflow from `app.R`, plotly chart and DT table included. It runs R in the
browser, so uploaded files never leave the visitor's machine and there is no
server to pay for. The trade-off is a one-time download of the R runtime on
first visit.


