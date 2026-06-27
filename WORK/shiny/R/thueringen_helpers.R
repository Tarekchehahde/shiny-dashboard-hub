# Shared helpers for erwicon connect 2026 Thüringen dashboard demos.

ERWICON_PRIMARY <- "#6B1D3A"
TH_BUNDESLAND <- "1415"
THUERINGEN_MAP_LNG <- 11.03
THUERINGEN_MAP_LAT <- 50.98
THUERINGEN_MAP_ZOOM <- 8L

thueringen_set_view <- function(map, zoom = THUERINGEN_MAP_ZOOM) {
  leaflet::setView(map, THUERINGEN_MAP_LNG, THUERINGEN_MAP_LAT, zoom)
}

.thueringen_data_dir <- function() {
  candidates <- c(
    file.path("data"),
    file.path("..", "..", "data", "thueringen"),
    "/opt/mastr-shiny/WORK/shiny/data/thueringen",
    "/opt/mastr-shiny/WORK/shiny/apps/thueringen_solar_wirtschaft/data"
  )
  for (d in candidates) {
    p <- file.path(d, "kreis_population_th.csv")
    if (file.exists(p)) {
      return(normalizePath(d, winslash = "/", mustWork = FALSE))
    }
  }
  stop("Th\u00fcringen Kreis data not found (kreis_population_th.csv)")
}

thueringen_kreis_meta <- function() {
  utils::read.csv(
    file.path(.thueringen_data_dir(), "kreis_population_th.csv"),
    stringsAsFactors = FALSE,
    fileEncoding = "UTF-8"
  )
}

thueringen_plz_kreis <- function() {
  d <- utils::read.csv(
    file.path(.thueringen_data_dir(), "plz_kreis_th.csv"),
    stringsAsFactors = FALSE,
    fileEncoding = "UTF-8"
  )
  d$plz <- sprintf("%05d", as.integer(d$plz))
  d
}

thueringen_demo_csv <- function(name) {
  utils::read.csv(
    file.path(.thueringen_data_dir(), name),
    stringsAsFactors = FALSE,
    fileEncoding = "UTF-8"
  )
}

sql_active_mastr <- function(active = TRUE) {
  if (!isTRUE(active)) {
    return("")
  }
  "AND EinheitBetriebsstatus = 35"
}

#' Onshore-only wind filter for raw `wind` table (parquet uses WindAnLandOderAufSee codes).
sql_wind_onshore_raw <- function() {
  "AND (WindAnLandOderAufSee IS NULL OR WindAnLandOderAufSee <> 889)"
}

kreis_from_plz <- function(plz_df, plz_kreis = thueringen_plz_kreis(), kreis_meta = thueringen_kreis_meta()) {
  empty <- data.frame(
    kreis = character(), units = numeric(), mw = numeric(),
    einwohner = numeric(), per_1000 = numeric(),
    lat = numeric(), lon = numeric(),
    stringsAsFactors = FALSE
  )
  if (is.null(plz_df) || !nrow(plz_df)) {
    return(empty)
  }
  plz_df$plz <- sprintf("%05d", as.integer(plz_df$plz))
  m <- merge(plz_df, plz_kreis, by = "plz", all.x = TRUE)
  m <- m[!is.na(m$kreis), , drop = FALSE]
  if (!nrow(m)) {
    return(empty)
  }
  agg <- stats::aggregate(cbind(units, mw) ~ kreis, data = m, FUN = function(x) sum(x, na.rm = TRUE))
  out <- merge(agg, kreis_meta, by = "kreis", all.x = TRUE)
  out$per_1000 <- ifelse(
    !is.na(out$einwohner) & out$einwohner > 0,
    out$units / out$einwohner * 1000,
    NA_real_
  )
  out
}

erwicon_banner_ui <- function(quote_text, extra = NULL) {
  tagList(
    tags$style(HTML("
      .erwicon-banner {
        background: linear-gradient(90deg, #6B1D3A 0%, #8B2942 100%);
        color: #fff; border-radius: 8px; padding: 0.65rem 1rem; margin-bottom: 1rem;
      }
    ")),
    div(
      class = "erwicon-banner small",
      tags$strong("Gespr\u00e4chsstarter:"),
      " ", quote_text,
      if (!is.null(extra)) tagList(" ", extra)
    )
  )
}

erwicon_badge <- function(n, total = 7L) {
  invisible(NULL)
}

kreis_leaflet_labels <- function(d, value_col, fmt = "%.1f", suffix = "") {
  paste0(
    d$kreis,
    " \u00b7 ",
    sprintf(fmt, d[[value_col]]),
    suffix
  )
}

kreis_leaflet_label_opts <- function() {
  leaflet::labelOptions(
    style = list("font-weight" = "500", "font-size" = "12px")
  )
}
