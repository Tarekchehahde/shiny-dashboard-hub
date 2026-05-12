# =============================================================================
# ui_helpers.R — shared bslib UI pieces used by every dashboard
# =============================================================================

suppressPackageStartupMessages({
  library(bslib)
  library(shiny)
  library(htmltools)
  library(plotly)
})

# Transtek-friendly palette (can be overridden per app).
MASTR_PALETTE <- list(
  primary = "#0B5ED7",
  accent  = "#10b981",
  warn    = "#f59e0b",
  danger  = "#ef4444",
  solar   = "#F59E0B",
  wind    = "#0EA5E9",
  biomass = "#65A30D",
  water   = "#06B6D4",
  geo     = "#B45309",
  nuclear = "#A855F7",
  fossil  = "#6B7280",
  storage = "#111827"
)

mastr_theme <- function(primary = MASTR_PALETTE$primary) {
  bslib::bs_theme(
    version = 5,
    bootswatch = "flatly",
    primary = primary,
    base_font = bslib::font_google("Inter"),
    heading_font = bslib::font_google("Inter"),
    "font-size-base" = "0.95rem"
  )
}

mastr_page <- function(title, subtitle = NULL, ...,
                       primary = MASTR_PALETTE$primary) {
  bslib::page_fillable(
    title = title,
    theme = mastr_theme(primary),
    tags$style(HTML("
      .mastr-footer { font-size: 0.75rem; color: #6b7280; padding: 0.5rem 0; }
      .mastr-kpi { font-variant-numeric: tabular-nums; }
      .value-box h3 { font-variant-numeric: tabular-nums; }
    ")),
    div(class = "py-2",
        h2(title, class = "mb-0"),
        if (!is.null(subtitle)) p(subtitle, class = "text-muted mb-0")),
    ...,
    mastr_footer()
  )
}

mastr_footer <- function() {
  div(class = "mastr-footer text-center border-top mt-3 pt-2",
      HTML(mastr_attribution()),
      " · ",
      tags$a(href = "https://www.marktstammdatenregister.de/MaStR/Datendownload",
             target = "_blank", "BNetzA MaStR"),
      " · ",
      tags$a(href = "https://github.com/Tarekchehahde/transtek/tree/master/mastr-shiny",
             target = "_blank", "Source"))
}

# Shorthand value_box with tabular-numeric formatting
mastr_kpi <- function(title, value, subtitle = NULL,
                      color = "primary", icon = NULL) {
  bslib::value_box(
    title = title,
    value = span(class = "mastr-kpi", value),
    subtitle,
    theme = color,
    showcase = icon
  )
}

# Format helpers
fmt_num <- function(x, digits = 0, suffix = "") {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("–")
  paste0(formatC(x, big.mark = ".", decimal.mark = ",", format = "f", digits = digits),
         suffix)
}

fmt_mw <- function(kw) fmt_num(kw / 1000, 1, " MW")
fmt_gw <- function(kw) fmt_num(kw / 1e6, 2, " GW")

# Avoid Plotly console warnings from plot_ly() with no traces (empty charts).
mastr_plotly_empty <- function(title) {
  d <- data.frame(x = 1, y = 1)
  plot_ly(d, x = ~x, y = ~y, type = "scatter", mode = "markers",
          marker = list(opacity = 0, size = 1), showlegend = FALSE) |>
    layout(
      title = title,
      xaxis = list(visible = FALSE, fixedrange = TRUE),
      yaxis = list(visible = FALSE, fixedrange = TRUE),
      margin = list(l = 20, r = 20, t = 48, b = 20)
    )
}

# MaStR field `Technologie` on Stromspeicher is a BNetzA enum (numeric in the export). The
# official text table is in the MaStR “Datendefinition” Excel; we map common codes for UI.
# Unknown codes: "Code …" so you can look them up in the Excel.
mastr_label_stromspeicher_technologie <- function(x) {
  x <- trimws(as.character(x))
  # Keys = values seen in live registers; extend when BNetzA adds types.
  map <- c(
    `524`  = "Batteriespeicher (Klein; i. d. R. viele Einheiten)",
    `1537` = "Speichertyp 1537 (i. d. R. wenige, sehr große Anlagen, z. B. Pumpspeicher)",
    `525`  = "Speichertechnologie 525",
    `526`  = "Speichertechnologie 526",
    `3067` = "Speichertechnologie 3067",
    `3087` = "Speichertechnologie 3087"
  )
  out <- unname(map[x])
  miss <- is.na(out)
  out[miss] <- paste0("MaStR-Code ", x[miss])
  out
}
