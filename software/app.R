# ============================================================
# Data Splicer — the app.
#
# Joins series published at different base years
# (WPI, CPI, IIP, GDP old/new series, ...) into one continuous
# series. Splicing logic, period parsing and the Notes text all
# live in splice-core.R; this file is only the interface.
#
# Run with:  shiny::runApp("software")
#
# This same file is what the website publishes: build-shinylive.R
# exports it to WebAssembly, plotly and DT included. There is no
# separate web front end to keep in step.
# ============================================================

library(shiny)
library(bslib)
library(readxl)
library(plotly)
library(DT)
library(writexl)

source("splice-core.R")

# ---------- UI ----------

# Chromium (crbug 468227) does not route requests from an <a download> link
# through a service worker. Shinylive serves the entire app from one, so the
# download URL escapes to the real host — GitHub Pages — which 404s, and the
# browser saves that 404 page as dl_csv.htm / dl_xlsx.htm. Dropping the
# attribute leaves target="_blank"; Shiny's Content-Disposition header still
# makes it a download, under the right filename. Harmless in Firefox.
download_btn <- function(...) {
  tag <- downloadButton(...)
  tag$attribs$download <- NULL
  tag
}

ui <- page_sidebar(
  title = "Data Splicer — join series across base-year changes",
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
    download_btn("dl_csv", "Download CSV", class = "btn-sm"),
    download_btn("dl_xlsx", "Download Excel", class = "btn-sm")
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
    for (j in seq_len(ncol(sp$mat))) {
      p <- add_trace(p, x = sp$lab, y = sp$mat[, j], type = "scatter",
                     mode = "lines", name = colnames(sp$mat)[j],
                     line = list(dash = "dot", width = 1.6,
                                 color = SERIES_PAL[(j - 1) %% length(SERIES_PAL) + 1]))
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
    txt <- factors_text(spliced()$info)
    if (is.null(txt)) return(NULL)
    tags$small(tags$b("Splice factors: "), txt)
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

  output$notes <- renderUI(HTML(notes_html()))
}

shinyApp(ui, server)
