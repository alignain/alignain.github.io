# ============================================================
# helpers.R — ALL shared code for the website lives here.
# Every page (.qmd) only calls functions from this file.
#
# SINGLE SOURCE OF TRUTH:
#   The website reads the SAME Excel file that builds the PDF
#   CV (cvnain/data/cv_data.xlsx). Update that one file and
#   re-render: both the CV and the website stay in sync.
# ============================================================

library(readxl)
library(dplyr)
library(glue)
library(plotly)
library(httr2)
library(jsonlite)

# ---- 1. DATA -----------------------------------------------
DATA_FILE <- "cvnain/data/cv_data.xlsx"

# A missing sheet returns an empty table with a loud warning instead of
# aborting the whole render — one deleted sheet should not take the
# entire site down with it. Watch the render log for these.
load_sheet <- function(sheet) {
  if (!sheet %in% readxl::excel_sheets(DATA_FILE)) {
    warning("Sheet '", sheet, "' is missing from ", DATA_FILE,
            " — that section will render empty.", call. = FALSE)
    return(data.frame())
  }
  read_excel(DATA_FILE, sheet = sheet)
}

ok <- function(x) length(x) == 1 && !is.na(x) && x != ""

# Column names in the Excel sheets drift over time — the presentations
# sheet has been through both 'venue' and 'organised'. Take the first
# candidate that is actually present and filled, so a rename in Excel
# degrades to the next name instead of silently dropping the field.
# (Plain `row$venue` returns NULL for a missing column, and ok(NULL) is
# FALSE, so the old code dropped every organiser without complaint.)
first_of <- function(row, ...) {
  for (n in c(...)) if (n %in% names(row) && ok(row[[n]])) return(row[[n]])
  ""
}

# Your name, bolded wherever it appears in author lists
bold_me      <- function(a) gsub("Md Zulquar Nain", "**Md Zulquar Nain**", a)
bold_me_html <- function(a) gsub("Md Zulquar Nain", "<strong>Md Zulquar Nain</strong>", a)

# Robust "year from a date column" (Excel date or plain text)
year_of <- function(x) {
  if (inherits(x, c("Date", "POSIXct", "POSIXt"))) return(format(x, "%Y"))
  m <- regmatches(as.character(x), regexpr("[0-9]{4}", as.character(x)))
  if (length(m)) m else ""
}

# ---- 2. PUBLICATIONS ---------------------------------------
# The 'category' column in the publications sheet decides the
# section. Add new categories here (order = display order).
# Canonical keys, shared with the PDF CV (cvnain/helpers.R):
#   journal | book_chapter | submitted | working | thesis
PUB_SECTIONS <- c(
  "journal"      = "Refereed Journal Articles",
  "book_chapter" = "Book Chapters",
  "submitted"    = "Under Review / Submitted",
  "working"      = "Working Papers",
  "thesis"       = "Theses"
)

# One publication -> one markdown entry
pub_entry <- function(p) {
  refpart <- ""
  if (ok(p$journal)) {
    refpart <- if (identical(p$category, "submitted") || identical(p$category, "under_review")) {
      glue(" Under review at *{p$journal}*.")
    } else {
      vol <- if (ok(p$volume)) glue(", {p$volume}") else ""
      iss <- if (ok(p$issue))  glue("({trimws(p$issue)})")  else ""
      pgs <- if (ok(p$pages))  glue(", {p$pages}")  else ""
      glue(" *{p$journal}*{vol}{iss}{pgs}.")
    }
  }
  doi <- if (ok(p$doi)) glue(" [DOI: {p$doi}](https://doi.org/{p$doi})") else ""
  glue("{bold_me(p$authors)} ({p$year}). \"{p$title}\".{refpart}{doi}")
}

# One publication -> one year-gutter entry on the Research page.
# Title first (that is what a reader scans for), then authors, then the
# venue and DOI in quieter type. `year_label` is blank for the second and
# later papers of the same year.
pub_entry_html <- function(p, year_label) {
  title <- htmltools::htmlEscape(p$title)
  title <- if (ok(p$doi)) {
    glue("<a href='https://doi.org/{p$doi}'>{title}</a>")
  } else title

  venue <- ""
  if (ok(p$journal)) {
    jrnl <- htmltools::htmlEscape(p$journal)
    venue <- if (identical(p$category, "submitted") ||
                 identical(p$category, "under_review")) {
      glue("Under review at <em>{jrnl}</em>")
    } else {
      vol <- if (ok(p$volume)) glue(", {p$volume}") else ""
      iss <- if (ok(p$issue))  glue("({trimws(p$issue)})") else ""
      pgs <- if (ok(p$pages))  glue(", {p$pages}")  else ""
      glue("<em>{jrnl}</em>{vol}{iss}{pgs}")
    }
  }
  doi <- if (ok(p$doi)) {
    glue("<a class='pub-doi' href='https://doi.org/{p$doi}'>doi:{p$doi}</a>")
  } else ""
  sep <- if (nzchar(venue) && nzchar(doi)) " · " else ""

  meta <- if (nzchar(venue) || nzchar(doi)) {
    glue("<p class='pub-venue'>{venue}{sep}{doi}</p>")
  } else ""

  glue(
    "<div class='pub-entry'>",
    "<div class='pub-year'>{year_label}</div>",
    "<div class='pub-body'>",
    "<p class='pub-title'>{title}</p>",
    "<p class='pub-authors'>{bold_me_html(htmltools::htmlEscape(p$authors))}</p>",
    "{meta}",
    "</div></div>\n"
  )
}

# Print all publications, grouped into sections by 'category'
print_publications <- function() {
  pubs <- load_sheet("publications") %>%
    mutate(category = ifelse(is.na(category), "journal", category)) %>%
    arrange(desc(year))

  seen <- character(0)
  cats <- c(intersect(names(PUB_SECTIONS), pubs$category),
            setdiff(unique(pubs$category), names(PUB_SECTIONS)))
  for (cg in cats) {
    heading <- if (cg %in% names(PUB_SECTIONS)) PUB_SECTIONS[[cg]] else tools::toTitleCase(cg)
    if (heading %in% seen) next
    seen <- c(seen, heading)
    grp <- names(PUB_SECTIONS)[PUB_SECTIONS == heading]
    if (!length(grp)) grp <- cg
    df <- pubs %>% filter(category %in% grp)
    if (nrow(df) == 0) next
    cat("## ", heading, "\n\n", sep = "")
    cat("<div class='pub-list'>\n")
    last_year <- ""
    for (i in seq_len(nrow(df))) {
      p <- as.list(df[i, ])
      # Show the year only on the first entry of each year, so runs of
      # papers group visually instead of repeating the same number.
      yr <- as.character(p$year)
      shown <- if (identical(yr, last_year)) "" else yr
      last_year <- yr
      cat(pub_entry_html(p, shown))
    }
    cat("</div>\n\n")
  }
}

# Homepage cards: marked selected = "YES" in Excel (add a
# 'selected' column); falls back to the n most recent articles.
print_selected_publications_html <- function(n = 3) {
  pubs <- load_sheet("publications")
  sel <- if ("selected" %in% names(pubs)) {
    pubs %>% filter(!is.na(selected) & toupper(selected) == "YES")
  } else pubs[0, ]
  if (nrow(sel) == 0) {
    sel <- pubs %>% filter(category %in% c(NA, "journal")) %>%
      arrange(desc(year)) %>% slice_head(n = n)
  }
  sel <- sel %>% arrange(desc(year))
  for (i in seq_len(nrow(sel))) {
    p <- as.list(sel[i, ])
    title <- if (ok(p$doi)) {
      glue("<a href='https://doi.org/{p$doi}' target='_blank'>{p$title}</a>")
    } else p$title
    cat(glue(
      "<div class='paper'>",
      "<h3>{title}</h3>",
      "<p class='paper-meta'>{p$journal} · {p$year}</p>",
      "<p>{bold_me_html(p$authors)}</p>",
      "</div>\n\n"
    ))
  }
}

# ---- Google Scholar (fetched LIVE from the profile) --------
# Order of preference at render time:
#   1. live scrape of the profile page (stats + citations/year),
#      cached to data/scholar_*.csv on every success;
#   2. the cache from the last successful fetch;
#   3. the scholar_fallback sheet in the Excel file.
SCHOLAR_ID  <- "7Db2EHMAAAAJ"
SCHOLAR_URL <- paste0("https://scholar.google.co.in/citations?user=", SCHOLAR_ID, "&hl=en")
SCHOLAR_UA  <- paste0("Mozilla/5.0 (Windows NT 10.0; Win64; x64) ",
                      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36")
STATS_CACHE <- "data/scholar_stats_cache.csv"
YEARS_CACHE <- "data/scholar_years_cache.csv"

fetch_scholar_live <- function() {
  page <- rvest::read_html(httr::GET(SCHOLAR_URL, httr::user_agent(SCHOLAR_UA)))
  std <- rvest::html_text(rvest::html_nodes(page, "td.gsc_rsb_std"), trim = TRUE)
  if (length(std) < 5) stop("Scholar page blocked (captcha) or layout changed")
  stats <- data.frame(citations = std[1], h_index = std[3], i10_index = std[5],
                      updated = as.character(Sys.Date()))

  # citations per year: map bars to years via their pixel offsets,
  # because Scholar labels only a subset of years on the axis
  years <- tryCatch({
    labs <- rvest::html_nodes(page, ".gsc_g_t")
    bars <- rvest::html_nodes(page, ".gsc_g_a")
    lab_yr <- as.numeric(rvest::html_text(labs))
    px <- function(nodes) as.numeric(gsub(".*right:(-?[0-9.]+)px.*", "\\1",
                                          rvest::html_attr(nodes, "style")))
    lab_px <- px(labs); bar_px <- px(bars)
    cites  <- as.numeric(rvest::html_text(bars))
    if (length(lab_yr) >= 2 && length(cites) > 0 && all(is.finite(c(lab_px, bar_px)))) {
      fit <- stats::lm(lab_yr ~ lab_px)
      data.frame(year = round(as.numeric(stats::predict(fit, data.frame(lab_px = bar_px)))),
                 cites = cites)
    } else NULL
  }, error = function(e) NULL)

  list(stats = stats, years = years, source = "live")
}

# OpenAlex (free API, never blocked) — used as a further fallback
OPENALEX_ID <- "A5034570980"

fetch_openalex <- function() {
  j <- jsonlite::fromJSON(paste0("https://api.openalex.org/authors/", OPENALEX_ID),
                          simplifyDataFrame = FALSE)
  stats <- data.frame(citations = j$cited_by_count,
                      h_index   = j$summary_stats$h_index,
                      i10_index = j$summary_stats$i10_index,
                      updated   = as.character(Sys.Date()))
  years <- do.call(rbind, lapply(j$counts_by_year, function(x)
    data.frame(year = x$year, cites = x$cited_by_count)))
  years <- years[order(years$year), ]
  list(stats = stats, years = years, source = "openalex")
}

# Refresh the shared cache ONCE per site render (called from
# R/pre-render.R). Pages never fetch on their own: each .qmd runs
# in its own R session, so per-page fetches can disagree when
# Scholar blocks some requests but not others — the cache is what
# keeps every page showing identical numbers.
# Order of preference:
#   stats: Scholar live > previous cache > Excel sheet > OpenAlex
#   chart: Scholar live > previous cache > OpenAlex
refresh_scholar_cache <- function() {
  live <- tryCatch(fetch_scholar_live(), error = function(e) NULL)
  if (!is.null(live)) {
    write.csv(live$stats, STATS_CACHE, row.names = FALSE)
    if (!is.null(live$years)) write.csv(live$years, YEARS_CACHE, row.names = FALSE)
    message("Scholar stats: live fetch OK (", live$stats$citations, " citations)")
    return(invisible(NULL))
  }
  if (file.exists(STATS_CACHE)) {
    message("Scholar stats: live fetch blocked; keeping cache from ",
            read.csv(STATS_CACHE)$updated[1])
    return(invisible(NULL))
  }
  # First render with Scholar blocked and no cache yet: seed it
  # from the Excel fallback sheet, filling gaps from OpenAlex.
  oa <- tryCatch(fetch_openalex(), error = function(e) NULL)
  s  <- load_sheet("scholar_fallback")[1, ]
  st <- data.frame(citations = s$citations, h_index = s$h_index,
                   i10_index = s$i10_index, updated = year_of(s$updated))
  if (any(is.na(st[1, 1:3])) && !is.null(oa)) st <- oa$stats
  write.csv(st, STATS_CACHE, row.names = FALSE)
  if (!is.null(oa) && !is.null(oa$years)) write.csv(oa$years, YEARS_CACHE, row.names = FALSE)
  message("Scholar stats: seeded cache from fallback (", st$citations[1], " citations)")
}

scholar_data <- function() {
  if (!file.exists(STATS_CACHE)) refresh_scholar_cache()
  list(
    stats = read.csv(STATS_CACHE, colClasses = "character"),
    years = if (file.exists(YEARS_CACHE)) read.csv(YEARS_CACHE) else NULL
  )
}

# Highlighted stats badges (links to the Scholar profile)
print_scholar_stats <- function() {
  s <- as.list(scholar_data()$stats)
  cat(glue(
    "<p class='scholar-badges'><a href='{SCHOLAR_URL}' target='_blank'>",
    "<span class='sbadge'>Citations: {s$citations}</span>",
    "<span class='sbadge'>h-index: {s$h_index}</span>",
    "<span class='sbadge'>i10-index: {s$i10_index}</span>",
    "</a></p>\n\n"
  ))
}

# Homepage one-liner under the selected publications
scholar_line_html <- function() {
  s <- as.list(scholar_data()$stats)
  cat(glue(
    "<p class='more-link'>",
    "<a href='{SCHOLAR_URL}' target='_blank'>",
    "Citations: {s$citations} · h-index: {s$h_index}</a>",
    " &nbsp;·&nbsp; <a href='research.qmd'>All publications →</a></p>\n"
  ))
}

# Citations-per-year bar chart (only when live/cached data exists)
scholar_chart <- function() {
  d <- scholar_data()
  if (is.null(d$years) || nrow(d$years) == 0) return(invisible(NULL))
  plot_ly(d$years, x = ~year, y = ~cites, type = "bar",
          marker = list(color = "#4e8d7e"),
          hovertemplate = "%{y} citations in %{x}<extra></extra>",
          height = 220) %>%
    chart_theme() %>%
    layout(bargap = 0.55)
}

# ---- 3. OTHER CV SECTIONS ----------------------------------
print_projects <- function() {
  pr <- load_sheet("projects") %>% arrange(desc(submission_date))
  for (i in seq_len(nrow(pr))) {
    p <- as.list(pr[i, ])
    amt <- if (ok(p$amount)) glue(" ({p$amount})") else ""
    co  <- if (identical(p$co_pi, "yes") && ok(p$co_pi_name)) glue(" With {p$co_pi_name}.") else ""
    cat(glue("- \"{p$title}\". *{p$sponsor}*{amt}, {p$period}.{co}\n\n"))
  }
}

print_presentations <- function() {
  df <- load_sheet("presentations") %>%
    mutate(date_parsed = suppressWarnings(as.Date(date))) %>%
    arrange(desc(date_parsed))
  for (grp in unique(df$category)) {
    d <- df %>% filter(category == grp)
    if (nrow(d) == 0) next
    if (ok(grp)) cat("### ", grp, "\n\n", sep = "")
    for (i in seq_len(nrow(d))) {
      t <- as.list(d[i, ])
      org <- first_of(t, "organised", "organizer", "venue")
      ven <- if (nzchar(org))    glue(", organised by {org}") else ""
      loc <- if (ok(t$location)) glue(", {t$location}") else ""
      yr  <- year_of(t$date)
      yr  <- if (yr != "") glue(", {yr}") else ""
      cat(glue("- **{t$title}**{ven}{loc}{yr}.\n\n"))
    }
  }
}

print_awards <- function() {
  aw <- load_sheet("awards") %>% arrange(desc(year))
  for (i in seq_len(nrow(aw))) {
    a <- as.list(aw[i, ])
    cat(glue("- {a$year} — {a$description}\n\n"))
  }
}

print_workshops <- function() {
  ws <- load_sheet("workshops") %>%
    mutate(date_parsed = suppressWarnings(as.Date(date))) %>%
    arrange(desc(date_parsed))
  for (i in seq_len(nrow(ws))) {
    w <- as.list(ws[i, ])
    org <- if (ok(w$organizer)) glue(" Organised by {w$organizer}.") else ""
    loc <- if (ok(w$location))  glue(" {w$location}.") else ""
    yr  <- year_of(w$date)
    yr  <- if (yr != "") glue(" {yr}.") else ""
    cat(glue("- **{w$title}**.{org}{loc}{yr}\n\n"))
  }
}

# Level codes in the Excel sheet -> the heading each one prints under.
# Order here is the display order. A level not listed still prints, under
# its raw code, after these — so a new code in Excel is never dropped.
TEACH_LEVELS <- c(UG = "Undergraduate", PG = "Postgraduate", PhD = "Ph.D.")

# Courses for one institution and one level, alphabetical, as one
# semicolon-separated sentence.
teaching_line <- function(df, lvl) {
  courses <- df %>%
    filter(!is.na(level) & level == lvl) %>%
    arrange(course_title) %>%
    pull(course_title)
  courses <- courses[!is.na(courses) & courses != ""]
  if (!length(courses)) return("")
  paste0(paste(courses, collapse = "; "), ".")
}

print_teaching <- function() {
  te <- load_sheet("teaching_courses")
  for (inst in unique(te$institution)) {
    df <- te %>% filter(institution == inst)
    if (nrow(df) == 0) next
    cat("## Courses Taught — ", inst, "\n\n", sep = "")
    lvls <- c(names(TEACH_LEVELS),
              setdiff(unique(df$level[!is.na(df$level)]), names(TEACH_LEVELS)))
    for (lvl in lvls) {
      line <- teaching_line(df, lvl)
      if (line == "") next
      heading <- if (lvl %in% names(TEACH_LEVELS)) TEACH_LEVELS[[lvl]] else lvl
      cat("### ", heading, "\n\n", sep = "")
      cat(line, "\n\n", sep = "")
    }
  }
}

ADV_HEADINGS <- c(
  phd = "Ph.D. Supervision", ms = "Masters Supervision",
  ug = "Undergraduate Students", hs = "High School Students",
  committee = "Ph.D. Committee Member"
)

print_advising <- function() {
  ad <- load_sheet("advising")
  for (lvl in names(ADV_HEADINGS)) {
    df <- ad %>% filter(level == lvl)
    if (nrow(df) == 0) next
    cat("## ", ADV_HEADINGS[[lvl]], "\n\n", sep = "")
    for (i in seq_len(nrow(df))) {
      a <- as.list(df[i, ])
      ttl <- if (ok(a$title)) glue(", \"{a$title}\"") else ""
      end <- if (ok(a$end_year)) a$end_year else "present"
      nts <- if (ok(a$notes)) glue(" {a$notes}.") else ""
      cat(glue("{i}. **{a$name}**{ttl}, {a$institution} ({a$start_year}–{end}).{nts}\n\n"))
    }
  }
}

print_service <- function() {
  sv <- load_sheet("service")
  for (i in seq_len(nrow(sv))) {
    s <- as.list(sv[i, ])
    cat(glue("- {s$role}, {s$organization} ({s$years}).\n\n"))
  }
}

print_memberships <- function() {
  mb <- load_sheet("memberships")
  for (i in seq_len(nrow(mb))) cat(glue("- {mb$organization[i]}\n\n"))
}

# Software tools / apps: one card per row of the 'software' sheet.
# Buttons render only for the links that are filled in — e.g. paste
# a shinyapps.io URL into app_url after deploying and the Launch
# button appears on the next render.
print_software <- function() {
  sw <- load_sheet("software")
  for (i in seq_len(nrow(sw))) {
    s <- as.list(sw[i, ])
    btn <- function(url, label, filled = FALSE) {
      if (!ok(url)) return("")
      cls <- if (filled) "btn-filled" else "btn-outline"
      glue("<a class='btn-pill {cls}' href='{url}'>{label}</a>")
    }
    launch <- btn(s$app_url, "Launch app &rarr;", filled = TRUE)
    source <- btn(s$source_url, "Source code")
    data   <- btn(s$data_url, "Example data")
    # .soft-note, not .paper-meta: paper-meta is uppercase, which is fine
    # for a short label like the tech line but unreadable for a sentence.
    note   <- if (ok(s$note)) glue("<p class='soft-note'>{s$note}</p>") else ""
    # Pages that are rebuilt periodically write a small JSON status file at
    # render time (see software/inflation-tracker.qmd). Point the sheet's
    # status_file column at it and the card stamps its own data date, so a
    # stale page announces itself instead of quietly ageing.
    stamp <- ""
    if (ok(s$status_file) && file.exists(s$status_file)) {
      st <- tryCatch(jsonlite::fromJSON(s$status_file), error = function(e) NULL)
      if (!is.null(st$latest_label)) {
        stamp <- glue("<p class='soft-stamp'>Data through <strong>{st$latest_label}</strong>",
                      "{if (!is.null(st$rendered)) paste0(' · page rebuilt ', format(as.Date(st$rendered), '%d %b %Y')) else ''}</p>")
      }
    }
    cat(glue(
      "<div class='paper soft-card'>",
      "<h3>{s$title}</h3>",
      "<p class='paper-meta'>{s$tech}</p>",
      "<p>{s$description}</p>",
      "{note}",
      "{stamp}",
      "<p class='soft-links'>{launch}{source}{data}</p>",
      "</div>\n\n"
    ))
  }
}

print_skills <- function() {
  sk <- load_sheet("skills")
  for (i in seq_len(nrow(sk))) {
    s <- as.list(sk[i, ])
    cat(glue("- **{s$category}:** {s$items}\n\n"))
  }
}

# ---- 4. ECONOMIC DATA (MoSPI, live) ------------------------
# Monthly Indian macro data straight from the Ministry of Statistics
# and Programme Implementation's open API — the same backend as the
# eSankhyiki portal, and the same one software/inflation-tracker.qmd
# uses. No API key is required.
#
# Fetched fresh at render time and cached to data/mospi_cache.csv so
# an offline render (or an API outage) still draws the last good data.
# ECON_YEARS sets how much history the homepage chart shows.
MOSPI_BASE  <- "https://api.mospi.gov.in"
MOSPI_CACHE <- "data/mospi_cache.csv"
ECON_YEARS  <- 5

# Paged GET. The API caps `limit` per endpoint (100 for getCPIData,
# 1000 for the others) and returns {"data": [...]}.
mospi_get <- function(path, params, limit = 100, max_pages = 100) {
  out <- list(); page <- 1L
  repeat {
    resp <- httr2::request(MOSPI_BASE) |>
      httr2::req_url_path(path) |>
      httr2::req_url_query(!!!params, Format = "JSON", limit = limit, page = page) |>
      httr2::req_user_agent("md-zulquar-nain website (R/httr2)") |>
      httr2::req_timeout(90) |>
      httr2::req_retry(max_tries = 3, backoff = ~2) |>
      httr2::req_perform()
    d <- jsonlite::fromJSON(httr2::resp_body_string(resp))$data
    if (is.null(d) || NROW(d) == 0) break
    out[[page]] <- as_tibble(d)
    if (NROW(d) < limit) break
    page <- page + 1L
    if (page > max_pages) break
  }
  if (!length(out)) tibble() else bind_rows(out)
}

month_start <- function(y, m) as.Date(sprintf("%s-%02d-01", y, match(m, month.name)))

# CHAIN-LINKING. MoSPI republishes each index on a new base every few
# years, and the series disagree where they overlap — the base 2022-23
# IIP puts March 2024 growth at 19.0% while base 2011-12 puts the same
# month near 5%, because the new base's first year is measured against
# a partial history. Splicing on "newest base wins" would draw that
# spike as if it were real.
#
# So: take the oldest base first and let each newer base contribute
# only the months the previous one does not reach. The long-running
# series carries the history, the newest one extends the tip, and the
# join sits at the end where the discontinuity is smallest.
chain_bases <- function(df) {
  starts <- df %>% group_by(base) %>% summarise(from = min(date), .groups = "drop") %>%
    arrange(from) %>% pull(base)
  out <- df[0, ]
  for (b in starts) {
    add <- df %>% filter(base == b, !date %in% out$date)
    out <- bind_rows(out, add)
  }
  out %>% arrange(date) %>% select(-base)
}

# Headline CPI inflation, All-India, Combined (rural + urban).
# Base 2012 runs Jan 2013 - Dec 2025; base 2024 takes over from 2026.
cpi_series <- function() {
  this_year <- as.integer(format(Sys.Date(), "%Y"))
  old <- mospi_get("/api/cpi/getCPIIndex",
                   list(base_year = "2012", series = "Current", state_code = "99"),
                   limit = 1000) %>%
    filter(sector == "Combined", group == "General") %>%
    transmute(date = month_start(year, month), base = "2012",
              value = suppressWarnings(as.numeric(inflation)))
  new <- bind_rows(lapply(2025:this_year, function(y)
    mospi_get("/api/cpi/getCPIData",
              list(base_year = "2024", series = "Current", state_code = "1",
                   sector_code = "3", division_code = "0", year = y),
              limit = 100)))
  if (nrow(new)) {
    new <- new %>% transmute(date = month_start(year, month), base = "2024",
                             value = suppressWarnings(as.numeric(inflation)))
  } else {
    new <- old[0, ]
  }
  bind_rows(old, new) %>% filter(!is.na(value)) %>% chain_bases() %>%
    mutate(variable = "CPI inflation (YoY %)")
}

# Index of Industrial Production, General index, year-on-year growth.
iip_series <- function() {
  mospi_get("/api/iip/getIIPData", list(frequency = "Monthly"), limit = 1000) %>%
    filter(type == "General") %>%
    transmute(date = month_start(year, month), base = base_year,
              value = suppressWarnings(as.numeric(growth_rate))) %>%
    filter(!is.na(value)) %>%
    chain_bases() %>%
    mutate(variable = "IIP growth (YoY %)")
}

# The chart and the note under it both want this data. Fetch once per R
# session and hand out the same table, so a page render makes one round
# trip to MoSPI rather than one per caller.
.econ_cache <- new.env(parent = emptyenv())

econ_data <- function() {
  if (!is.null(.econ_cache$d)) return(.econ_cache$d)
  d <- tryCatch({
    fresh <- bind_rows(cpi_series(), iip_series()) %>%
      filter(!is.na(date)) %>%
      arrange(variable, date)
    if (nrow(fresh) == 0) stop("MoSPI returned no rows")
    write.csv(fresh, MOSPI_CACHE, row.names = FALSE)
    message("MoSPI: live fetch OK (", nrow(fresh), " observations, latest ",
            format(max(fresh$date), "%b %Y"), ")")
    fresh
  }, error = function(e) {
    message("MoSPI: live fetch failed (", conditionMessage(e), ") — using cache")
    read.csv(MOSPI_CACHE) %>% mutate(date = as.Date(date))
  })
  d <- d %>% filter(date >= seq(Sys.Date(), by = paste0("-", ECON_YEARS, " years"),
                                length.out = 2)[2])
  .econ_cache$d <- d
  d
}

# ---- 5. CHARTS (plotly, interactive) -----------------------
CHART_COLORS <- c("#2a78d6", "#1baf7a", "#eda100", "#008300", "#4a3aa7", "#e34948")

chart_theme <- function(p, ytitle = "") {
  p %>%
    layout(
      hovermode = "x unified",
      xaxis = list(title = "", showgrid = FALSE, linecolor = "#c3c2b7",
                   tickfont = list(color = "#52514e")),
      yaxis = list(title = list(text = ytitle, font = list(color = "#52514e")),
                   gridcolor = "#e1e0d9", zeroline = FALSE,
                   tickfont = list(color = "#52514e")),
      legend = list(orientation = "h", x = 0, y = 1.12),
      margin = list(t = 10, r = 10),
      paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
      font = list(family = "Inter, system-ui, -apple-system, Segoe UI, sans-serif")
    ) %>%
    config(displayModeBar = FALSE, responsive = TRUE)
}

# Homepage: monthly CPI inflation and IIP growth
econ_chart <- function() {
  d <- econ_data()
  d$variable <- factor(d$variable, levels = unique(d$variable))
  # shape = "spline" curves the segments between points instead of joining
  # them with straight lines. `smoothing` runs 0 (straight) to 1.3 (most
  # curved); 1.0 is plotly's default and is deliberate here — higher values
  # overshoot at sharp turning points, which on monthly data would draw
  # troughs deeper than the published figures.
  plot_ly(d, x = ~date, y = ~value,
          color = ~variable, colors = CHART_COLORS[seq_along(unique(d$variable))],
          type = "scatter", mode = "lines",
          line = list(width = 2.4, shape = "spline", smoothing = 1),
          hovertemplate = "%{y:.1f}%<extra></extra>",
          height = 340) %>%
    chart_theme(ytitle = "Percent (%)") %>%
    layout(xaxis = list(showgrid = FALSE, linecolor = "#c3c2b7",
                        tickfont = list(color = "#52514e")),
           shapes = list(list(type = "line", xref = "paper", x0 = 0, x1 = 1,
                              yref = "y", y0 = 0, y1 = 0,
                              line = list(color = "#c3c2b7", width = 1))))
}

# Latest reading of each series, for the note under the chart
econ_latest_note <- function() {
  d <- econ_data()
  bits <- d %>% group_by(variable) %>% filter(date == max(date)) %>% ungroup() %>%
    arrange(variable) %>%
    mutate(txt = sprintf("%s: <strong>%.1f%%</strong> (%s)",
                         sub(" \\(YoY %\\)", "", variable), value,
                         format(date, "%b %Y"))) %>%
    pull(txt)
  cat(paste(bits, collapse = " &nbsp;·&nbsp; "))
}

# Research page: bar chart of publications per year
pubs_chart <- function() {
  counts <- load_sheet("publications") %>% count(year)
  plot_ly(counts, x = ~year, y = ~n, type = "bar",
          marker = list(color = "#69b3a2"),
          hovertemplate = "%{y} publication(s) in %{x}<extra></extra>",
          height = 220) %>%
    chart_theme() %>%
    layout(bargap = 0.55, yaxis = list(dtick = 1))
}
