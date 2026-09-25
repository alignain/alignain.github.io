# ============================================================
# India Data Splicer — a Shiny app for joining Indian macro
# series published at different base years (WPI, CPI, IIP, GDP
# old/new series, ...) into one continuous series.
#
# Data format expected (CSV or Excel):
#   - column 1: period  (YYYY, YYYY-MM, "Jan 2012", 2012 Q1, or a date)
#   - remaining columns: the SAME indicator at different bases,
#     one column per base, ordered OLDEST base -> NEWEST base.
#     Leave cells empty where a base was not published.
#
# Methods:
#   link    ratio splice at one link period (default: first overlap)
#   avg     ratio splice using the average ratio over the overlap
#   growth  retropolation: extend the new series backwards with
#           the period-on-period growth rates of the old series
# ============================================================

library(shiny)
library(bslib)
library(readxl)
library(zoo)
library(plotly)
library(DT)
library(writexl)

# ---------- helpers ----------

parse_period <- function(x) {
  x <- trimws(as.character(x))
  if (all(grepl("^\\d{4}$", x))) {
    return(list(t = as.numeric(x), lab = x))
  }
  for (fmt in list(NULL, "%Y-%m", "%m-%Y", "%b-%Y")) {
    ym <- suppressWarnings(
      if (is.null(fmt)) zoo::as.yearmon(x) else zoo::as.yearmon(x, fmt)
    )
    if (!any(is.na(ym))) return(list(t = as.numeric(ym), lab = format(ym)))
  }
  yq <- suppressWarnings(zoo::as.yearqtr(x))
  if (!any(is.na(yq))) return(list(t = as.numeric(yq), lab = format(yq)))
  d <- suppressWarnings(as.Date(x))
  if (!any(is.na(d))) return(list(t = as.numeric(d), lab = as.character(d)))
  NULL
}

# splice one pair: keep `new` where available, extend backwards from `old`
splice_pair <- function(old, new, method = "link", link_pos = NULL) {
  overlap <- which(!is.na(old) & !is.na(new) & old != 0)
  if (length(overlap) == 0)
    stop("Two consecutive series have no overlapping periods — splicing needs an overlap.")
  out <- new
  factor <- NA_real_
  if (method == "growth") {
    first_new <- min(which(!is.na(new)))
    if (first_new > 1) {
      for (t in seq(first_new - 1, 1)) {
        out[t] <- if (!is.na(old[t]) && !is.na(old[t + 1]) && !is.na(out[t + 1]) && old[t + 1] != 0)
          out[t + 1] * old[t] / old[t + 1] else NA_real_
      }
    }
  } else {
    factor <- if (method == "avg") {
      mean(new[overlap] / old[overlap])
    } else {
      lp <- if (is.null(link_pos) || !(link_pos %in% overlap)) overlap[1] else link_pos
      new[lp] / old[lp]
    }
    fill <- is.na(new) & !is.na(old)
    out[fill] <- old[fill] * factor
  }
  list(series = out, factor = factor, overlap_n = length(overlap))
}

# chain splice across k segments ordered oldest -> newest
splice_chain <- function(mat, method = "link", link_pos = NULL) {
  k <- ncol(mat)
  current <- mat[, k]
  info <- data.frame(pair = character(0), factor = numeric(0), overlap = integer(0))
  if (k >= 2) {
    for (i in seq(k - 1, 1)) {
      res <- splice_pair(mat[, i], current, method,
                         if (i == k - 1) link_pos else NULL)
      current <- res$series
      info <- rbind(info, data.frame(
        pair = paste(colnames(mat)[i], "→", colnames(mat)[i + 1]),
        factor = round(res$factor, 5),
        overlap = res$overlap_n))
    }
  }
  list(series = current, info = info)
}

# illustrative demo: an index at base 2004-05 and at base 2011-12
demo_data <- function() {
  y1 <- 1994:2014
  g1 <- 0.05 + 0.02 * sin(seq_along(y1[-1]) / 3)
  v1 <- cumprod(c(1, 1 + g1))
  v1 <- round(100 * v1 / v1[y1 == 2004], 1)      # 2004 = 100
  y2 <- 2012:2024
  g2 <- 0.045 + 0.015 * cos(seq_along(y2[-1]) / 2.5)
  v2 <- round(106.9 * cumprod(c(1, 1 + g2)), 1)  # 2011-12 = 100 base
  yrs <- 1994:2024
  data.frame(
    period            = as.character(yrs),
    index_base_2004_05 = v1[match(yrs, y1)],
    index_base_2011_12 = v2[match(yrs, y2)],
    check.names = FALSE
  )
}

ACCENT <- "#4e8d7e"

# ---------- UI ----------

ui <- page_sidebar(
  title = "India Data Splicer — join series across base-year changes",
  theme = bs_theme(version = 5, primary = ACCENT,
                   base_font = font_google("Inter", local = FALSE)),
  sidebar = sidebar(
    width = 330,
    h6("1. Data"),
    fileInput("file", NULL, accept = c(".csv", ".xlsx", ".xls"),
              buttonLabel = "Upload", placeholder = "CSV or Excel"),
    actionLink("demo", "→ or load the demo dataset"),
    uiOutput("col_pickers"),
    hr(),
    h6("2. Splicing method"),
    radioButtons("method", NULL,
      c("Ratio splice at a link period" = "link",
        "Ratio splice, average over overlap" = "avg",
        "Growth-rate retropolation" = "growth")),
    uiOutput("link_picker"),
    hr(),
    h6("3. Rebase (optional)"),
    checkboxInput("rebase", "Rebase spliced series (= 100)", FALSE),
    uiOutput("base_picker"),
    hr(),
    downloadButton("dl_csv", "Download CSV", class = "btn-sm"),
    downloadButton("dl_xlsx", "Download Excel", class = "btn-sm")
  ),

  navset_card_tab(
    nav_panel("Chart",
      plotlyOutput("chart", height = "430px"),
      uiOutput("factors_ui")),
    nav_panel("Table", DTOutput("table")),
    nav_panel("Notes", uiOutput("notes"))
  )
)

# ---------- server ----------

server <- function(input, output, session) {

  raw <- reactiveVal(NULL)

  observeEvent(input$demo, raw(demo_data()))

  observeEvent(input$file, {
    ext <- tolower(tools::file_ext(input$file$name))
    df <- tryCatch(
      if (ext == "csv") read.csv(input$file$datapath, check.names = FALSE)
      else as.data.frame(read_excel(input$file$datapath)),
      error = function(e) NULL)
    if (is.null(df) || ncol(df) < 3) {
      showNotification("Could not read the file, or it has fewer than 3 columns (period + at least 2 series).", type = "error")
    } else raw(df)
  })

  output$col_pickers <- renderUI({
    req(raw())
    cols <- names(raw())
    tagList(
      selectInput("period_col", "Period column", cols, selected = cols[1]),
      selectizeInput("series_cols", "Series, ordered OLDEST base → NEWEST base",
                     cols, selected = cols[-1], multiple = TRUE,
                     options = list(plugins = list("drag_drop"))))
  })

  # parsed, sorted working data
  work <- reactive({
    req(raw(), input$period_col, length(input$series_cols) >= 2)
    df <- raw()
    pp <- parse_period(df[[input$period_col]])
    validate(need(!is.null(pp), "Could not parse the period column (use YYYY, YYYY-MM, 'Jan 2012', '2012 Q1' or dates)."))
    ord <- order(pp$t)
    mat <- as.matrix(df[ord, input$series_cols, drop = FALSE])
    storage.mode(mat) <- "numeric"
    list(lab = pp$lab[ord], mat = mat)
  })

  output$link_picker <- renderUI({
    req(input$method == "link", work())
    w <- work()
    k <- ncol(w$mat)
    ov <- which(!is.na(w$mat[, k - 1]) & !is.na(w$mat[, k]))
    req(length(ov) > 0)
    selectInput("link_period", "Link period (newest pair)",
                setNames(ov, w$lab[ov]), selected = ov[1])
  })

  output$base_picker <- renderUI({
    req(input$rebase, work())
    w <- work()
    selectInput("base_period", "Base period for rebasing",
                setNames(seq_along(w$lab), w$lab))
  })

  spliced <- reactive({
    w <- work()
    lp <- if (!is.null(input$link_period)) as.integer(input$link_period) else NULL
    res <- tryCatch(splice_chain(w$mat, input$method, lp),
                    error = function(e) validate(need(FALSE, conditionMessage(e))))
    s <- res$series
    if (isTRUE(input$rebase) && !is.null(input$base_period)) {
      b <- s[as.integer(input$base_period)]
      if (!is.na(b) && b != 0) s <- s / b * 100
    }
    list(lab = w$lab, mat = w$mat, series = round(s, 3), info = res$info)
  })

  output$chart <- renderPlotly({
    sp <- spliced()
    p <- plot_ly()
    pal <- c("#2a78d6", "#eda100", "#8064a2", "#e34948")
    for (j in seq_len(ncol(sp$mat))) {
      p <- add_trace(p, x = sp$lab, y = sp$mat[, j], type = "scatter",
                     mode = "lines", name = colnames(sp$mat)[j],
                     line = list(dash = "dot", width = 1.6,
                                 color = pal[(j - 1) %% length(pal) + 1]))
    }
    p <- add_trace(p, x = sp$lab, y = sp$series, type = "scatter",
                   mode = "lines", name = "Spliced",
                   line = list(color = ACCENT, width = 3))
    layout(p, hovermode = "x unified",
           xaxis = list(title = "", type = "category"),
           yaxis = list(title = "Index"),
           legend = list(orientation = "h", x = 0, y = 1.12)) |>
      config(displayModeBar = FALSE)
  })

  output$factors_ui <- renderUI({
    sp <- spliced()
    if (nrow(sp$info) == 0) return(NULL)
    tags$small(tags$b("Splice factors: "),
      paste(apply(sp$info, 1, function(r)
        sprintf("%s: factor %s (overlap %s periods)", r["pair"],
                ifelse(is.na(r["factor"]), "growth-linked", r["factor"]),
                r["overlap"])), collapse = " | "))
  })

  result_df <- reactive({
    sp <- spliced()
    data.frame(period = sp$lab, sp$mat, spliced = sp$series, check.names = FALSE)
  })

  output$table <- renderDT({
    datatable(result_df(), rownames = FALSE,
              options = list(pageLength = 25, scrollX = TRUE))
  })

  output$dl_csv <- downloadHandler(
    filename = function() "spliced_series.csv",
    content = function(f) write.csv(result_df(), f, row.names = FALSE))

  output$dl_xlsx <- downloadHandler(
    filename = function() "spliced_series.xlsx",
    content = function(f) writexl::write_xlsx(result_df(), f))

  output$notes <- renderUI(HTML("
    <h5>Why splicing?</h5>
    <p>Indian statistical agencies periodically shift the base year of major
    indices — WPI (1993-94 &rarr; 2004-05 &rarr; 2011-12), IIP (2004-05 &rarr;
    2011-12), CPI-IW (2001 &rarr; 2016), and the National Accounts
    (GDP/GVA, 2004-05 &rarr; 2011-12). Because weights and coverage change,
    the levels of old- and new-base series are not directly comparable and
    must be <em>spliced</em> to obtain one long series for time-series work.</p>
    <h5>Methods implemented</h5>
    <ul>
      <li><b>Ratio splice at a link period</b> — multiply the old-base series by
      the ratio (new/old) observed at one chosen overlapping period.
      Preserves the old series' growth rates exactly.</li>
      <li><b>Average-overlap ratio</b> — same, but the conversion factor is the
      mean ratio over the whole overlap window; less sensitive to a single
      unusual month/year.</li>
      <li><b>Growth-rate retropolation</b> — extend the new series backwards
      period by period using the old series' growth rates. Identical to the
      link-period splice when the link is the first overlap period; differs
      when old and new growth rates disagree inside the overlap.</li>
    </ul>
    <h5>Caveats</h5>
    <ul>
      <li>Splicing preserves growth rates of the old series but its
      <em>levels</em> before the link carry the new base's scale — do not read
      pre-link levels as official statistics.</li>
      <li>More than two bases are chained sequentially from the newest
      backwards; each pair needs an overlap.</li>
      <li>For National Accounts, compare results against the official
      back-series (MoSPI, 2018) where available.</li>
    </ul>"))
}

shinyApp(ui, server)
