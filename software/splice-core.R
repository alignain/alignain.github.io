# ============================================================
# India Data Splicer — shared core.
#
# Everything here is presentation-independent: period parsing,
# the three splicing methods, the demo dataset, and the Notes
# copy. Both front ends source this file:
#
#   app.R      full desktop app (plotly chart, DT table)
#   app-web.R  slim build for Shinylive (base graphics, plain
#              table) — see build-shinylive.R for why
#
# Fix a splicing bug once, here, and both get it.
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

library(zoo)

ACCENT <- "#4e8d7e"

# Colours for the original (un-spliced) base series.
SERIES_PAL <- c("#2a78d6", "#eda100", "#8064a2", "#e34948")

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

# one-line summary of the conversion factors, shown under the chart
factors_text <- function(info) {
  if (nrow(info) == 0) return(NULL)
  paste(apply(info, 1, function(r)
    sprintf("%s: factor %s (overlap %s periods)", r["pair"],
            ifelse(is.na(r["factor"]), "growth-linked", r["factor"]),
            r["overlap"])), collapse = " | ")
}

notes_html <- function() "
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
    </ul>"
