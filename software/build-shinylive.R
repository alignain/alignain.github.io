# Builds the browser version of the India Data Splicer.
#
# The normal Shiny app (app.R) stays the single source of truth.
# This script stages a copy and exports a Shinylive (WebAssembly)
# site to splicer-app/, which the website publishes as-is.
#
# splicer-app/ is generated output and is NOT committed (see .gitignore);
# the publish workflow re-runs this script before rendering the site.
#
# Re-run after every edit to app.R:
#   Rscript build-shinylive.R        (from the software/ folder)

# large wasm package downloads exceed R's default 60s timeout
options(timeout = 600)

stage <- file.path(tempdir(), "splicer")
dir.create(stage, showWarnings = FALSE)
file.copy("app.R", stage, overwrite = TRUE)

shinylive::export(stage, "splicer-app")

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

cat("\nExported to splicer-app/ — re-render the website to publish.\n")
