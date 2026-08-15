# Runs automatically before every site render (see _quarto.yml).

# 1. Fetch Google Scholar stats ONCE and cache them, so every
#    page shows the same numbers (pages render in separate R
#    sessions and must not fetch independently).
source("R/helpers.R")
refresh_scholar_cache()

# 2. Keep the downloadable cv.pdf in sync with the latest PDF CV
#    rendered from the cvnain project.
src <- "cvnain/Dr-Nain_CV.pdf"
if (file.exists(src)) {
  invisible(file.copy(src, "cv.pdf", overwrite = TRUE))
  message("cv.pdf refreshed from ", src)
} else {
  message("NOTE: ", src, " not found; keeping existing cv.pdf")
}
