# ============================================================
# India Data Splicer — Shinylive (browser) build.
#
# Same app as app.R over the same splice-core.R, with two
# substitutions:
#
#   plotly  -> base graphics  (renderPlot)
#   DT      -> renderTable
#
# Why: a Shinylive page has to download and install every R
# package it uses as WebAssembly before it shows anything.
# plotly and DT drag in ggplot2, stringi, data.table, httr,
# rmarkdown and ~30 more — about 50 MB of package tarballs on
# top of the 33 MB webR runtime. That never finished loading
# on GitHub Pages. Without them the extra payload is ~5 MB.
#
# What is lost here: hover tooltips and zoom on the chart, and
# search/sort/paging on the table. Everything else — parsing,
# the three splicing methods, rebasing, both downloads — is
# identical, because it all lives in splice-core.R.
#
# Not run directly: build-shinylive.R stages this file as app.R.
# ============================================================

library(shiny)
library(bslib)
library(readxl)
library(writexl)

source("splice-core.R")

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
      plotOutput("chart", height = "430px"),
      uiOutput("factors_ui")),
    nav_panel("Table",
      div(style = "max-height: 460px; overflow: auto;",
          tableOutput("table"))),
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

  # Base-graphics stand-in for the plotly chart: dotted lines for each
  # base series, one thick solid line for the spliced result. Periods
  # are drawn on a categorical axis (1..n) so that irregular gaps in
  # the data do not stretch the x scale, matching type = "category".
  output$chart <- renderPlot({
    sp <- spliced()
    k <- ncol(sp$mat)
    n <- length(sp$lab)
    vals <- c(as.vector(sp$mat), sp$series)
    vals <- vals[is.finite(vals)]
    validate(need(length(vals) > 0, "The selected series contain no numeric values."))

    ylim <- range(vals)
    if (diff(ylim) == 0) ylim <- ylim + c(-1, 1)
    cols <- SERIES_PAL[(seq_len(k) - 1) %% length(SERIES_PAL) + 1]

    op <- par(mar = c(5.5, 4.5, 5, 1), bty = "n", las = 1,
              mgp = c(3, 0.6, 0), cex.axis = 0.85)
    on.exit(par(op), add = TRUE)

    plot(NA, xlim = c(1, max(n, 2)), ylim = ylim,
         xaxt = "n", xlab = "", ylab = "Index")

    # Thin the period labels — a monthly series would otherwise
    # print several hundred of them on top of each other.
    at <- unique(round(seq(1, n, length.out = min(n, 12))))
    axis(1, at = at, labels = sp$lab[at], las = 2, cex.axis = 0.8)
    grid(nx = NA, ny = NULL, col = "#e6e6e6", lty = 1)

    for (j in seq_len(k)) {
      lines(seq_len(n), sp$mat[, j], lty = 3, lwd = 1.8, col = cols[j])
    }
    lines(seq_len(n), sp$series, lwd = 3, col = ACCENT)

    # Legend sits in the top margin, where it cannot cover the series.
    legend("top", inset = c(0, -0.20), xpd = NA, bty = "n",
           ncol = min(3, k + 1), cex = 0.85,
           legend = c(colnames(sp$mat), "Spliced"),
           col = c(cols, ACCENT),
           lty = c(rep(3, k), 1), lwd = c(rep(1.8, k), 3))
  }, res = 96)

  output$factors_ui <- renderUI({
    txt <- factors_text(spliced()$info)
    if (is.null(txt)) return(NULL)
    tags$small(tags$b("Splice factors: "), txt)
  })

  result_df <- reactive({
    sp <- spliced()
    data.frame(period = sp$lab, sp$mat, spliced = sp$series, check.names = FALSE)
  })

  output$table <- renderTable(result_df(), rownames = FALSE, digits = 3,
                              na = "", striped = TRUE, hover = TRUE,
                              spacing = "xs", width = "100%")

  output$dl_csv <- downloadHandler(
    filename = function() "spliced_series.csv",
    content = function(f) write.csv(result_df(), f, row.names = FALSE))

  output$dl_xlsx <- downloadHandler(
    filename = function() "spliced_series.xlsx",
    content = function(f) writexl::write_xlsx(result_df(), f))

  output$notes <- renderUI(HTML(paste0(notes_html(), "
    <h5>About this browser version</h5>
    <p>This page runs R itself inside your browser (WebAssembly) — nothing
    you upload leaves your machine, and there is no server. To keep the
    one-time download small, the chart here is a static image and the table
    is plain; the splicing, rebasing and downloads are exactly the same as
    in the desktop app.</p>")))
}

shinyApp(ui, server)
