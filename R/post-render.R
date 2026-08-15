# Runs after every render (see _quarto.yml) and guarantees that EVERY published
# page carries the GoatCounter tag — not just the ones Quarto renders itself.
#
# Why this exists:
#   `format > html > include-in-header` in _quarto.yml only reaches pages Quarto
#   builds. Whole sections of this site are copied in as finished HTML instead —
#   the 15 Rclass_2025 lecture decks, the hand-rendered inflation tracker, the
#   Shinylive splicer app — and those were being served untracked. Working on
#   _site/ after the render is the only place that sees all of them at once, and
#   it keeps working for anything added later without further edits here.
#
# The tag itself is NOT written twice: it is read out of _quarto.yml, so that
# file stays the single place where the analytics endpoint is defined.

site <- Sys.getenv("QUARTO_PROJECT_OUTPUT_DIR", "_site")
if (!dir.exists(site)) {
  message("post-render: no ", site, " directory — nothing to do.")
} else {

  # --- the tag, taken from _quarto.yml so the two can never drift apart ---
  yml <- readLines("_quarto.yml", warn = FALSE)
  tag_line <- grep("data-goatcounter", yml, value = TRUE)
  tag <- if (length(tag_line) >= 1) trimws(tag_line[1]) else NA_character_

  if (is.na(tag) || !nzchar(tag)) {
    message("post-render: no data-goatcounter line in _quarto.yml — ",
            "skipping analytics injection.")
  } else {

    pages <- list.files(site, pattern = "\\.html$", recursive = TRUE,
                        full.names = TRUE)
    added <- 0L
    already <- 0L
    skipped <- character(0)

    insert <- charToRaw(paste0(tag, "\n"))

    for (f in pages) {
      # Raw byte splice rather than readLines()/writeLines(). These files are a
      # mix of encodings — the lecture decks are not all UTF-8 — and a
      # read-then-write round trip through R's line handling would re-encode
      # them and mangle characters. Working on bytes touches nothing except the
      # few bytes being inserted. useBytes = TRUE on the searches for the same
      # reason: no re-interpretation of the content.
      size <- file.size(f)
      if (is.na(size) || size == 0) next
      bytes <- readBin(f, "raw", size)
      txt <- rawToChar(bytes)

      if (grepl("goatcounter", txt, fixed = TRUE, useBytes = TRUE)) {
        already <- already + 1L
        next
      }

      m <- regexpr("</head>", txt, ignore.case = TRUE, useBytes = TRUE)
      if (m < 1) {
        # Fragments and partial documents have no <head> to put it in.
        skipped <- c(skipped, f)
        next
      }

      before <- as.integer(m) - 1L
      out <- if (before > 0) {
        c(bytes[seq_len(before)], insert, bytes[(before + 1L):size])
      } else {
        c(insert, bytes)
      }
      writeBin(out, f)
      added <- added + 1L
    }

    message(sprintf(
      "post-render: analytics tag — %d page(s) already had it, %d added, %d skipped (no </head>).",
      already, added, length(skipped)))
    if (length(skipped)) {
      message("  skipped: ", paste(basename(skipped), collapse = ", "))
    }

    total <- already + added
    if (total < length(pages)) {
      message(sprintf("  NOTE: %d of %d pages are untracked.",
                      length(pages) - total, length(pages)))
    }
  }
}
