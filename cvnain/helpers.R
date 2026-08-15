# =========================
# helpers.R
# =========================

library(readxl)
library(dplyr)
library(glue)
library(knitr)
library(kableExtra)
library(rvest)
library(stringr)

# ---------- LaTeX utils ----------
latex_escape <- function(x) {
  x <- ifelse(is.na(x), "", x)
  x <- gsub("&", "\\\\&", x)
  x <- gsub("%", "\\\\%", x)
  x <- gsub("_", "\\\\_", x)
  x <- gsub("#", "\\\\#", x)
  x <- gsub("\\$", "\\\\$", x)
  x <- gsub("\\{", "\\\\{", x)
  x <- gsub("\\}", "\\\\}", x)
  x
}

# Column names in cv_data.xlsx drift over time — the presentations sheet
# has been through both 'venue' and 'organised'. Take the first candidate
# that is present and filled. `df$venue` on a missing column returns NULL,
# which paste0() silently swallows as "", so the old code emitted a stray
# comma where the organiser should have been.
first_of <- function(df, i, ...) {
  for (n in c(...)) {
    if (n %in% names(df)) {
      v <- df[[n]][i]
      if (!is.na(v) && v != "") return(as.character(v))
    }
  }
  ""
}

bold_author <- function(x, me = "Md Zulquar Nain") {
  x <- latex_escape(x)
  gsub(me, paste0("\\textbf{", me, "}"), x, fixed = TRUE)
}

# ---------- Section helpers ----------
print_section <- function(title) {
  cat("\n\n\\section*{", latex_escape(title), "}\n\n", sep = "")
}

print_subsection <- function(title) {
  cat("\n\n\\subsection*{", latex_escape(title), "}\n\n", sep = "")
}

print_numbered <- function(x) {
  cat(paste0(seq_along(x), ". ", x, collapse = "\n\n"), "\n\n")
}

print_bullets <- function(x) {
  cat("\\begin{itemize}\n")
  cat(paste0("\\item ", x, collapse = "\n"))
  cat("\n\\end{itemize}\n")
}

# ---------- Advising ----------
adv_heading <- function(level) {
  switch(
    level,
    phd = "Ph.D. Students",
    ms = "Masters Students",
    ug = "Undergraduate Students",
    hs = "High School Students",
    committee = "Ph.D. Committee Member",
    NULL
  )
}

print_adv <- function(df) {
  titles <- ifelse(!is.na(df$title) & df$title != "",
                   paste0(", ``", latex_escape(df$title), "''"), "")
  notes <- ifelse(!is.na(df$notes) & df$notes != "",
                  paste0(" ", latex_escape(df$notes)), "")
  cat(
    paste0(
      seq_len(nrow(df)), ". ",
      latex_escape(df$name),
      titles,
      ", ",
      latex_escape(df$institution),
      " (", df$start_year, "-", df$end_year, ").",
      notes,
      collapse = "\n\n"
    ),
    "\n\n"
  )
}

# ---------- Google Scholar ----------
# Fetch order: Google Scholar live -> scholar_fallback sheet -> OpenAlex.
# NOTE: when Scholar serves its captcha page, read_html still succeeds
# but the stats table is empty — so we must validate, not just tryCatch,
# otherwise the CV prints "NA".
print_scholar_stats <- function(url, fb) {
  vals <- tryCatch({
    page <- rvest::read_html(url)
    stats <- rvest::html_nodes(page, "td.gsc_rsb_std") |> rvest::html_text(trim = TRUE)
    if (length(stats) < 5) stop("Scholar blocked (captcha) or layout changed")
    list(c = stats[1], h = stats[3], i = stats[5])
  }, error = function(e) NULL)

  if (is.null(vals)) {
    vals <- list(c = fb$citations[1], h = fb$h_index[1], i = fb$i10_index[1])
  }

  bad <- function(x) is.null(x) || is.na(x) || x == ""
  if (bad(vals$c) || bad(vals$h) || bad(vals$i)) {
    vals <- tryCatch({
      j <- jsonlite::fromJSON("https://api.openalex.org/authors/A5034570980")
      list(c = j$cited_by_count, h = j$summary_stats$h_index, i = j$summary_stats$i10_index)
    }, error = function(e) vals)
  }

  cat("\\fcolorbox{blue!20}{blue!10}{\\textbf{Citations: ", vals$c,
      "} \\quad \\textbf{h-index: ", vals$h,
      "} \\quad \\textbf{i10-index: ", vals$i, "}}", sep = "")
}


# =========================
# Teaching helpers
# =========================

render_teaching_table <- function(df) {

  # ---- Coerce numeric columns safely ----
  n_resp     <- suppressWarnings(as.numeric(df$n_resp))
  n_enrolled <- suppressWarnings(as.numeric(df$n_enrolled))
  instr_fce  <- suppressWarnings(as.numeric(df$instr_fce))
  dept_mean  <- suppressWarnings(as.numeric(df$dept_mean))

  # ---- Base columns (always present) ----
  out <- df |>
    mutate(
      Course = paste(course_code, course_title)
    ) |>
    select(
      `Sem.` = sem,
      Course,
      Level = level
    )

  # ---- Optional: enrollment ----
  has_enrollment <- any(!is.na(n_resp) & !is.na(n_enrolled))

  if (has_enrollment) {
    out <- out |>
      mutate(
        `N. Resp. / N. Enrolled` =
          ifelse(
            is.na(n_resp) | is.na(n_enrolled),
            "",
            paste0(n_resp, "/", n_enrolled)
          )
      )
  }

  # ---- Optional: FCE ----
  has_fce <- any(!is.na(instr_fce) & !is.na(dept_mean))

  if (has_fce) {
    out <- out |>
      mutate(
        `Instr. FCE / Dept Mean` =
          ifelse(
            is.na(instr_fce) | is.na(dept_mean),
            "",
            paste0(
              formatC(instr_fce, format = "f", digits = 1),
              "/",
              formatC(dept_mean, format = "f", digits = 1)
            )
          )
      )
  }

  # ---- Render table ----
  tbl <- out |>
    kable(
      format = "latex",
      booktabs = TRUE,
      longtable = TRUE,
      escape = TRUE
    ) |>
    kable_styling(
      latex_options = "repeat_header",
      position = "center"
    )

  # ---- Footnote only if FCE exists ----
  if (has_fce) {
    tbl <- tbl |>
      footnote(
        general =
          "Faculty Course Evaluations (FCE) are scored by students (1 = worst, 5 = best).",
        threeparttable = FALSE
      )
  }

  tbl
}

# =========================
# Publications helpers
# =========================
# Canonical category keys in cv_data.xlsx "publications" sheet:
#   journal | book_chapter | submitted | working | thesis
# (thesis is not printed here — the dissertation appears under Education)

print_pub_section <- function(pubs, label, key) {

  x <- pubs |>
    filter(category == key) |>
    arrange(desc(year))
  if (nrow(x) == 0) return(invisible(NULL))

  cat("\n\n\\subsection*{", latex_escape(label), "}\n\n", sep = "")

  blank <- function(v) is.na(v) | trimws(as.character(v)) == ""

  # Volume(issue), pages — printed only where present
  vol_iss <- ifelse(
    blank(x$volume), "",
    paste0(", \\emph{", trimws(x$volume), "}",
           ifelse(blank(x$issue), "", paste0("(", trimws(x$issue), ")")))
  )
  pgs <- ifelse(blank(x$pages), "", paste0(", ", latex_escape(trimws(x$pages))))

  # Container (journal or book title), styled by category
  container <- ifelse(
    blank(x$journal), "",
    paste0(
      if (key == "submitted") "Under review at " else if (key == "book_chapter") "In " else "",
      "\\emph{", latex_escape(x$journal), "}",
      if (key == "submitted") "" else paste0(vol_iss, pgs),
      ". "
    )
  )

  publisher <- if (key == "book_chapter") {
    ifelse(blank(x$publisher), "", paste0(latex_escape(x$publisher), ". "))
  } else ""

  doi <- ifelse(
    blank(x$doi), "",
    paste0("DOI: \\href{https://doi.org/", x$doi, "}{", x$doi, "}")
  )

  entries <- paste0(
    "\\hangindent=2.2em \\hangafter=1 ",
    seq_len(nrow(x)), ". ",
    bold_author(x$authors), " (", x$year, ") ",
    "``", latex_escape(x$title), "''. ",
    container, publisher, doi
  )

  cat(paste(entries, collapse = "\n\n"), "\n\n")
}

print_all_publications <- function(pubs) {
  sections <- c(
    journal      = "Refereed Journal Articles",
    book_chapter = "Book Chapters",
    submitted    = "Papers Under Review / Submitted",
    working      = "Working Papers"
  )
  n <- 0
  for (key in names(sections)) {
    if (!any(pubs$category == key, na.rm = TRUE)) next
    n <- n + 1
    print_pub_section(pubs, paste0(LETTERS[n], ". ", sections[[key]]), key)
  }
}

# =========================
# Presentations helpers
# =========================

print_presentations <- function(talks_df) {

  print_section("Presentations / Conferences")

  # ---- Parse dates & sort globally ----
  talks_df <- talks_df |>
    mutate(date_parsed = suppressWarnings(as.Date(date))) |>
    arrange(desc(date_parsed))

  counter <- 1  # global counter

  for (grp in unique(talks_df$category)) {

    df <- talks_df |> filter(category == grp)
    if (nrow(df) == 0) next

    cat("\n\n\\subsection*{", latex_escape(grp), "}\n\n", sep = "")

    entries <- character(0)

    for (i in seq_len(nrow(df))) {

      entry <- paste0(
        counter, ". ",
        "``", latex_escape(df$title[i]), "''. ",

        # With
        ifelse(
          is.na(df$with[i]) | df$with[i] == "",
          "",
          paste0("With ", latex_escape(df$with[i]), ". ")
        ),

        # Organiser + location (either part may be missing; no stray commas)
        {
          org <- first_of(df, i, "organised", "organizer", "venue")
          loc <- first_of(df, i, "location")
          paste0(
            if (nzchar(org)) paste0(latex_escape(org), if (nzchar(loc)) ", " else ". ") else "",
            if (nzchar(loc)) paste0(latex_escape(loc), ". ") else ""
          )
        },

        # Date
        ifelse(
          is.na(df$date_parsed[i]),
          "",
          paste0(format(df$date_parsed[i], "%b %d, %Y"), ". ")
        ),

        # Slides
        ifelse(
          is.na(df$slides[i]) | df$slides[i] == "",
          "",
          paste0("\\href{", df$slides[i], "}{Slides}.")
        )
      )

      entries <- c(entries, entry)
      counter <- counter + 1
    }

    cat(paste(entries, collapse = "\n\n"), "\n\n")
  }
}


# =========================
# Workshops helpers
# =========================

# =========================
# Workshops helpers
# =========================

print_workshops <- function(workshops_df) {

  if (nrow(workshops_df) == 0) {
    cat("No workshops and training data available.\n\n")
    return(invisible(NULL))
  }

  # Sort by date (most recent first)
  workshops_df <- workshops_df %>%
    arrange(desc(date))

  # Format the date to show only month and year
  workshops_df <- workshops_df %>%
    mutate(
      date_formatted = format(as.Date(date), "%B %Y")
    )

  # Print each workshop
  for (i in seq_len(nrow(workshops_df))) {

    # Build the workshop entry with bold title
    entry <- paste0(
      i, ". ",
      "\\textbf{", latex_escape(workshops_df$title[i]), "}. ",
      ifelse(!is.na(workshops_df$organizer[i]) & workshops_df$organizer[i] != "",
             paste0("Organized by ", latex_escape(workshops_df$organizer[i]), ". "), ""),
      ifelse(!is.na(workshops_df$location[i]) & workshops_df$location[i] != "",
             paste0(latex_escape(workshops_df$location[i]), ". "), ""),
      ifelse(!is.na(workshops_df$date_formatted[i]) & workshops_df$date_formatted[i] != "",
             paste0(latex_escape(workshops_df$date_formatted[i]), "."), "")
    )

    cat(entry, "\n")

    # Add spacing between items (except after the last one)
    if (i < nrow(workshops_df)) {
      cat("\\vspace{6pt}\n\n")
    } else {
      cat("\n")
    }
  }
}
