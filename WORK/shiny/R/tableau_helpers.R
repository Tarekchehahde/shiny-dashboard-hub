# =============================================================================
# tableau_helpers.R — shared building blocks used by the /apps/*_tableau* suite
# (the Tableau-parity dashboards the in-house team compares against Candida's
# output). None of these helpers touch the DB directly — they only emit SQL
# fragments that `mastr_query()` then executes remotely via DuckDB httpfs.
# =============================================================================

suppressPackageStartupMessages({ library(DBI) })

# The standard BNetzA / Candida size buckets used in the "KPI Bundeslaender"
# and Inbetriebnahmen sheets. ORDER MATTERS — the first matching WHEN wins.
TABLEAU_SIZE_BUCKETS <- list(
  list(label = "<= 1 kW",     upper = 1),
  list(label = "<= 3 kW",     upper = 3),
  list(label = "<= 5 kW",     upper = 5),
  list(label = "<= 10 kW",    upper = 10),
  list(label = "<= 15 kW",    upper = 15),
  list(label = "<= 25 kW",    upper = 25),
  list(label = "<= 50 kW",    upper = 50),
  list(label = "<= 100 kW",   upper = 100),
  list(label = "<= 125 kW",   upper = 125),
  list(label = "<= 150 kW",   upper = 150),
  list(label = "<= 250 kW",   upper = 250),
  list(label = "<= 500 kW",   upper = 500),
  list(label = "<= 1000 kW",  upper = 1000),
  list(label = "<= 2500 kW",  upper = 2500),
  list(label = "<= 5000 kW",  upper = 5000),
  list(label = "<= 10000 kW", upper = 10000),
  list(label = "> 10000 kW",  upper = Inf)
)
TABLEAU_BUCKET_LABELS <- vapply(TABLEAU_SIZE_BUCKETS, `[[`, character(1), "label")

#' Emit a DuckDB CASE expression that assigns each row to a TABLEAU size bucket
#' based on a kW column. The CASE is built programmatically so the bucket list
#' stays a single source of truth.
sql_size_bucket <- function(kw_col = "Bruttoleistung") {
  inner <- vapply(TABLEAU_SIZE_BUCKETS, function(b) {
    if (is.infinite(b$upper))
      sprintf("ELSE '%s'", b$label)
    else
      sprintf("WHEN %s <= %g THEN '%s'", kw_col, b$upper, b$label)
  }, character(1))
  paste0("CASE ", paste(head(inner, -1), collapse = " "), " ",
         tail(inner, 1), " END")
}

#' Candida's three-segment split: Home / C&I / Large Scale.
#' Thresholds straight from her dashboard caption:
#'   "<10 kW = Home, <1 MW = C&I, Rest Large Scale."
sql_segment_3 <- function(kw_col = "Bruttoleistung") {
  sprintf("CASE
    WHEN %s < 10    THEN 'Home'
    WHEN %s < 1000  THEN 'C&I'
    ELSE                 'Large Scale' END", kw_col, kw_col)
}

#' Year/Quartal/Monat buckets that show up again and again in the Tableau sheets
sql_ibn_year    <- function(col = "Inbetriebnahmedatum")
  sprintf("EXTRACT(YEAR  FROM %s)", col)
sql_ibn_quarter <- function(col = "Inbetriebnahmedatum")
  sprintf("CAST(EXTRACT(QUARTER FROM %s) AS INTEGER)", col)
sql_ibn_month   <- function(col = "Inbetriebnahmedatum")
  sprintf("EXTRACT(MONTH FROM %s)", col)

#' Registrierungsdatum is stored as VARCHAR (ISO-8601 date) in the parquet,
#' while Inbetriebnahmedatum is already DATE. Emit a TRY_CAST so malformed
#' rows become NULL instead of failing the whole query — DuckDB's plain CAST
#' would abort with "invalid input syntax for date".
sql_reg_date <- function(col = "Registrierungsdatum")
  sprintf("TRY_CAST(%s AS DATE)", col)

#' Month names in German, so labels match the Candida screenshot exactly.
MONTHS_DE <- c("Januar","Februar","Maerz","April","Mai","Juni",
               "Juli","August","September","Oktober","November","Dezember")

#' Fail-soft IF a raw column is missing (some releases may drop rarely-used
#' columns). Returns NULL if the column does not exist, a literal SQL snippet
#' otherwise. Useful for the "Fernsteuerbarkeit" / "Lage" filter guards.
sql_if_column <- function(con, table, column, fragment) {
  cols <- tryCatch(
    DBI::dbGetQuery(con, sprintf("DESCRIBE %s", table))$column_name,
    error = function(e) character(0))
  if (column %in% cols) fragment else NULL
}

#' Safe column check (shared by several Tableau apps before they wire filters).
has_column <- function(con, table, column) {
  cols <- tryCatch(
    DBI::dbGetQuery(con, sprintf("DESCRIBE %s", table))$column_name,
    error = function(e) character(0))
  column %in% cols
}

#' Format a % deviation for tables — matches Candida's "Abw. zu Vorjahr" style.
#' Accepts numeric, returns character with German-style thousand/decimal marks.
fmt_pct_de <- function(x, digits = 2) {
  out <- ifelse(is.na(x), "—",
                paste0(formatC(x * 100, format = "f", digits = digits,
                               big.mark = ".", decimal.mark = ","), "%"))
  out
}

#' Small wrapper that highlights "this is what Candida does too, we do it in R".
#' Emits a compact info banner at the top of each Tableau-parity dashboard.
tableau_parity_banner <- function(tableau_name = NULL) {
  txt <- if (is.null(tableau_name)) {
    "Dieses Dashboard bildet eine vergleichbare Tableau-Ansicht nach."
  } else {
    sprintf("Nachbau von Tableau-Blatt \u201E%s\u201C \u2014 gleiche Metriken, identische Filter, R Shiny-Backend.", tableau_name)
  }
  shiny::tags$div(
    class = "alert alert-info py-2 mb-3", style = "font-size:0.85rem;",
    shiny::tags$strong("Tableau-Parit\u00E4t:"), " ", txt
  )
}
