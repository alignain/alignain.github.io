# Academic website of Md Zulquar Nain (Quarto + GitHub Pages)

Personal academic website with an animated economics background on the
homepage (network of economic variables, floating equations,
self-drawing impulse-response panels) and content driven by a single
Excel file.

## ONE file to update everything

**`cvnain/data/cv_data.xlsx`** is the single source of truth. It drives:

- the **PDF CV** (rendered from `cvnain/Dr Nain_CV.qmd`), and
- the **website**: publications (+ per-year chart + homepage cards),
  projects, presentations, awards, workshops, service, memberships,
  skills, teaching courses, advising, and Google Scholar fallback stats.

Workflow after editing the Excel file:

1. (Optional) re-render the PDF CV inside `cvnain/` — the site copies
   `cvnain/Dr-Nain_CV.pdf` to `cv.pdf` automatically before each render
   (`R/pre-render.R`).
2. Re-render the site: `quarto render` (or Render in RStudio).
3. Push to GitHub — done.

To feature specific papers on the homepage, add `YES` in the `selected` column to
the `publications` sheet; otherwise the three most recent articles are shown.

The few things NOT in the Excel file (they rarely change) are edited
directly in the pages: hero text and research-interest cards
(`index.qmd`), education/appointments (`cv.qmd`), the teaching intro
(`teaching.qmd`).


`data/mospi_cache.csv` is kept as the offline cache for the homepage
Data corner chart.

## How everything is wired

- `R/helpers.R` — ALL shared code. Every page only calls functions from
  here (e.g. `print_publications()`, `print_teaching()`,
  `econ_chart()`). To change how a section looks, edit it once here.
- `R/pre-render.R` — runs before each render; refreshes `cv.pdf`.
- `background.js` — the animated homepage background. The `STYLE` block
  at the top is the control panel:
  - `intensity`: master visibility (0.5 subtle … 2 bold)
  - `speed`: animation pace
  - `ink` / `accent`: the two colours
  - per-layer opacities, equation font sizes, link distance
  - the `EQUATIONS` and `LABELS` arrays hold the floating formulas and
    node labels.
- `styles.css` — colours (`--accent` at the top), fonts, cards. The
  `.section` background alpha (0.80) controls how much of the animation
  shows through the content sections.
- `_quarto.yml` — navbar, footer, excluded folders (`cv/`, `cvnain/`
  are not rendered or published).

## Blog

`blog.qmd` lists everything in `posts/`. New post = new folder
`posts/whatever/index.qmd` with `title`, `date`, `description`,
`categories` in the YAML header.

## Preview locally

```
quarto preview
```

(Requires R with packages: readxl, dplyr, glue, plotly, WDI, tidyr,
knitr, rmarkdown — all already installed on this machine.)

## Publish on GitHub Pages

Account: <https://github.com/alignain>

1. Create a **public** repo named `alignain.github.io` with no README,
   `.gitignore` or licence, so the site lives at
   <https://alignain.github.io/>.
2. Push this folder to `main`:
   ```
   git init
   git add .
   git commit -m "Academic website"
   git branch -M main
   git remote add origin https://github.com/alignain/alignain.github.io.git
   git push -u origin main
   ```
3. On GitHub: **Settings → Pages → Source → GitHub Actions**. Nothing is
   published until this is set. There is no `gh-pages` branch — the built
   site is uploaded as an artifact, so it never enters the repo history.
4. Watch the first run under **Actions** (10–20 min; later builds are
   faster).
5. Set `site-url: https://alignain.github.io/` in `_quarto.yml` and push.

Thereafter every push to `main` auto-deploys via
`.github/workflows/publish.yml`.

Do **not** run `quarto publish gh-pages` — it would create a branch that
competes with the Actions deployment.
