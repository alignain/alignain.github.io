# Builds the browser version of the India Data Splicer.
#
# app.R is the single front end: the full app, plotly chart and DT table.
# It sources splice-core.R for the splicing logic. This script stages both
# and exports a Shinylive (WebAssembly) site to splicer-app/.
#
#
#
#
#
# splicer-app/ is generated output and is NOT committed (see .gitignore);
# the publish workflow re-runs this script before rendering the site.
#
# Re-run after every edit to app.R or splice-core.R:
#   Rscript build-shinylive.R        (from the software/ folder)

# large wasm package downloads exceed R's default 60s timeout
options(timeout = 600)

# Packages the browser app loads that are NOT already in the webR base
# image. shinylive::export() decides what to ship by walking the dependency
# tree of the packages installed on *this* machine, so anything missing here
# is silently dropped from the export and the published app dies on startup
# with no error in the console. Check before building rather than after
# deploying — this is how zoo and writexl went missing once already.
NEEDED <- c("zoo", "readxl", "writexl", "plotly", "DT")

missing <- NEEDED[!vapply(NEEDED, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  stop("not installed on this machine: ", paste(missing, collapse = ", "),
       " — shinylive would omit them from the export. install.packages() them first.")
}

stage <- file.path(tempdir(), "splicer")
unlink(stage, recursive = TRUE)   # never inherit files from an earlier run
dir.create(stage, showWarnings = FALSE)

# shinylive::export() adds to its output directory without clearing it, so
# packages from a previous build survive and get published. Wipe it first —
# splicer-app/ is generated output, there is nothing here to keep.
unlink("splicer-app", recursive = TRUE)

stopifnot(file.copy("app.R", stage, overwrite = TRUE),
          file.copy("splice-core.R", stage, overwrite = TRUE))

shinylive::export(stage, "splicer-app")

shipped <- list.files("splicer-app/shinylive/webr/packages")

# The other half of the NEEDED check above: installed locally is necessary
# but not sufficient — confirm they actually made it into the export.
dropped <- setdiff(NEEDED, shipped)
if (length(dropped)) {
  stop("shinylive did not export: ", paste(dropped, collapse = ", "),
       " — the published app would fail to start. Check that they are ",
       "installed and that app.R/splice-core.R still library() them.")
}

cat("Shipped", length(shipped), "packages:", paste(sort(shipped), collapse = ", "), "\n")

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
