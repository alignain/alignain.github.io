# Builds the browser version of the India Data Splicer.
#
# Two front ends share splice-core.R:
#   app.R      the full desktop app (plotly + DT) — develop against this
#   app-web.R  the slim build published here
#
# This script stages app-web.R *as* app.R alongside splice-core.R and
# exports a Shinylive (WebAssembly) site to splicer-app/.
#
# Why not export app.R directly: Shinylive ships every package the app
# uses to the browser as WebAssembly, to be downloaded and installed
# before the first pixel appears. plotly and DT pull in ggplot2,
# stringi, data.table, httr, rmarkdown and about thirty more — roughly
# 50 MB of package tarballs on top of the 33 MB webR runtime. The page
# never finished loading on GitHub Pages. app-web.R needs ~5 MB of
# packages instead.
#
# splicer-app/ is generated output and is NOT committed (see .gitignore);
# the publish workflow re-runs this script before rendering the site.
#
# Re-run after every edit to app-web.R or splice-core.R:
#   Rscript build-shinylive.R        (from the software/ folder)

# large wasm package downloads exceed R's default 60s timeout
options(timeout = 600)

stage <- file.path(tempdir(), "splicer")
unlink(stage, recursive = TRUE)   # never inherit files from an earlier run
dir.create(stage, showWarnings = FALSE)

# shinylive::export() adds to its output directory without clearing it, so
# packages from a previous build survive and get published. Wipe it first —
# splicer-app/ is generated output, there is nothing here to keep.
unlink("splicer-app", recursive = TRUE)

# shinylive requires the entry point to be called app.R
stopifnot(file.copy("app-web.R", file.path(stage, "app.R"), overwrite = TRUE),
          file.copy("splice-core.R", stage, overwrite = TRUE))

shinylive::export(stage, "splicer-app")

# Guard against the heavy dependencies creeping back in: if a future
# edit reintroduces plotly or DT, the export balloons and the page stops
# loading, which is invisible until someone opens it. Fail the build here
# instead.
banned <- c("plotly", "DT", "ggplot2", "stringi")
present <- intersect(banned, list.files("splicer-app/shinylive/webr/packages"))
if (length(present)) {
  stop("app-web.R pulled in ", paste(present, collapse = ", "),
       " — these make the browser build too large to load. ",
       "Keep heavy packages in app.R only.")
}

payload <- sum(file.info(list.files("splicer-app", recursive = TRUE,
                                    full.names = TRUE))$size, na.rm = TRUE)

# shinylive::export() writes its own index.html, so the GoatCounter tag the
# rest of the site gets from _quarto.yml has to be re-applied here after
# every export — otherwise this one page silently stops being counted.
index <- "splicer-app/index.html"
tag <- paste0(
  '<script data-goatcounter="https://alignain.goatcounter.com/count"',
  ' async src="https://gc.zgo.at/count.js"></script>'
)

html <- readLines(index, warn = FALSE)
if (!any(grepl("goatcounter", html, fixed = TRUE))) {
  head_close <- grep("</head>", html, fixed = TRUE)[1]
  if (is.na(head_close)) {
    stop("no </head> in ", index, " — cannot insert the analytics tag")
  }
  html <- append(html, paste0("    ", tag), after = head_close - 1L)
  writeLines(html, index)
  cat("Re-applied the GoatCounter tag to", index, "\n")
}

cat(sprintf("\nExported to splicer-app/ (%.0f MB) — re-render the website to publish.\n",
            payload / 1024^2))
