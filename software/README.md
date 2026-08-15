# India Data Splicer

## Inflation tracker

`inflation-tracker.qmd` is a Quarto page that pulls live All-India CPI data from
MoSPI's open API (no key needed) and renders headline trend, rural/urban split,
division-wise inflation, contributions to the headline rate, and a 2012-base
historical view. Rebuild it any time with:

```
quarto render inflation-tracker.qmd
```

(or the Render button in RStudio). Output: `inflation-tracker.html`,
self-contained. API pulls are cached in `data_cache/` — the current year
refreshes after 12 hours; delete the folder to force a full re-download.
New CPI data lands around the 12th of each month at 4 pm IST.

A Shiny app to join Indian macro series published at different base years
(WPI, IIP, CPI, GDP/GVA old vs new series, ...) into one continuous series.

## Files

| file | what it is |
|------|------------|
| `splice-core.R` | period parsing, the three splicing methods, demo data, Notes copy — no UI |
| `app.R` | full desktop app: plotly chart, DT table. Develop against this |
| `app-web.R` | slim front end published on the website: base-graphics chart, plain table |
| `build-shinylive.R` | stages `app-web.R` + `splice-core.R` and exports to `splicer-app/` |

Both apps source `splice-core.R`, so a fix to the splicing logic lands in
both. Only the presentation layer is duplicated — keep the two in step when
you change the interface.

**Why two front ends.** A Shinylive page ships every package the app uses to
the browser as WebAssembly, and installs it there before showing anything.
plotly and DT pull in ggplot2, stringi, data.table, httr, rmarkdown and about
thirty more — ~50 MB of package tarballs on top of the 33 MB webR runtime.
The published page never finished loading. `app-web.R` needs ~5 MB instead
and starts in well under a minute. `build-shinylive.R` fails the build if a
heavy package creeps back in.

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
workflow from `app-web.R`. It runs R in the browser, so uploaded files never
leave the visitor's machine and there is no server to pay for. The trade-off
is a one-time download of the R runtime on first visit, and a static chart
and plain table instead of plotly/DT.

If the interactive chart and table matter more than the load time, the
alternative is **shinyapps.io** (free tier): `rsconnect::deployApp("software")`
deploys `app.R` unchanged, and the website would link out to it instead.
