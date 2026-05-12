# Thesis track — Batteriespeicher (Deutschland), MaStR-only
# Production apps unter apps/08_* bleiben unverändert.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable); library(memoise)
})
source("../../../R/mastr_data.R"); source("../../../R/ui_helpers.R")

THESIS_PRIMARY <- "#0f766e"

# MaStR XML often stores Technologie / Batterietechnologie as numeric enum codes (not 'Batterie' text).
# Defaults match typical registers; override without code changes:
#   Sys.setenv(MASTR_BATTERY_TECH_CODES = "524")
#   Sys.setenv(MASTR_BATTERY_CHEM_CODES = "727,728")   # e.g. Li-Ion family
#   Sys.setenv(MASTR_STORAGE_EXCLUDE_TECH_CODES = "528")  # optional explicit pump/H2 codes to drop
.parse_codes_env <- function(key, default = "") {
  s <- Sys.getenv(key, default)
  if (!nzchar(s)) return(character(0))
  p <- trimws(strsplit(s, ",", fixed = TRUE)[[1]])
  p[nzchar(p)]
}

.sql_in_txt <- function(codes) paste(sprintf("'%s'", codes), collapse = ", ")

# MaStR: top-level Technologie is often 'Batterie' / 'Pumpspeicher'; cell chemistry is Batterietechnologie.
# Remote Parquet may add a NULL Batterietechnologie via mastr_data.R; local DuckDB may omit the column.
.sql_batteries <- memoise::memoise(function() {
  cols <- tryCatch(
    tolower(mastr_query("PRAGMA table_info(stromspeicher)")$name),
    error = function(e) character(0)
  )
  has_bt <- "batterietechnologie" %in% cols
  sel_bt <- if (has_bt) "         Technologie, Batterietechnologie, Bundesland, Gemeinde, Postleitzahl" else
    "         Technologie, Bundesland, Gemeinde, Postleitzahl"

  tech_codes <- .parse_codes_env("MASTR_BATTERY_TECH_CODES", "524")
  chem_codes <- if (has_bt) .parse_codes_env("MASTR_BATTERY_CHEM_CODES", "727") else character(0)
  excl_codes <- .parse_codes_env("MASTR_STORAGE_EXCLUDE_TECH_CODES", "")

  tech_or <- if (length(tech_codes)) {
    sprintf(
      "\n      OR trim(CAST(Technologie AS VARCHAR)) IN (%s)",
      .sql_in_txt(tech_codes)
    )
  } else {
    ""
  }
  chem_or <- if (length(chem_codes)) {
    sprintf(
      "\n      OR trim(CAST(Batterietechnologie AS VARCHAR)) IN (%s)",
      .sql_in_txt(chem_codes)
    )
  } else {
    ""
  }
  excl_sql <- if (length(excl_codes)) {
    sprintf(
      "    AND trim(COALESCE(CAST(Technologie AS VARCHAR), '')) NOT IN (%s)\n",
      .sql_in_txt(excl_codes)
    )
  } else {
    ""
  }

  paste0("
  SELECT EinheitMastrNummer AS mastr_nr,
         TRY_CAST(Bruttoleistung AS DOUBLE) AS kw,
         TRY_CAST(NutzbareSpeicherkapazitaet AS DOUBLE) AS kwh,
         TRY_CAST(Inbetriebnahmedatum AS DATE) AS inbetrieb,
", sel_bt, "
  FROM stromspeicher
  WHERE
    NOT (
      lower(trim(COALESCE(CAST(Technologie AS VARCHAR), ''))) LIKE '%pumpspeicher%'
      OR lower(trim(COALESCE(CAST(Technologie AS VARCHAR), ''))) LIKE '%wasserstoff%'
    )
", excl_sql, "    AND (
      (
        Technologie IS NOT NULL
        AND (
          lower(trim(CAST(Technologie AS VARCHAR))) LIKE '%batterie%'
          OR lower(trim(CAST(Technologie AS VARCHAR))) LIKE '%battery%'
          OR lower(trim(CAST(Technologie AS VARCHAR))) LIKE '%lithium%'
          OR lower(trim(CAST(Technologie AS VARCHAR))) LIKE '%ionspeicher%'
          OR lower(trim(CAST(Technologie AS VARCHAR))) LIKE '%li-ion%'
          OR lower(trim(CAST(Technologie AS VARCHAR))) LIKE '%liion%'
          OR lower(trim(CAST(Technologie AS VARCHAR))) LIKE '%akku%'
        )
      )", tech_or, chem_or, "
    )
")
})

.bundesland_name <- function(code) {
  m <- c(
    `1400` = "Schleswig-Holstein",
    `1401` = "Hamburg",
    `1402` = "Niedersachsen",
    `1403` = "Bremen",
    `1404` = "Nordrhein-Westfalen",
    `1405` = "Hessen",
    `1406` = "Rheinland-Pfalz",
    `1407` = "Baden-Württemberg",
    `1408` = "Bayern",
    `1409` = "Saarland",
    `1410` = "Berlin",
    `1411` = "Brandenburg",
    `1412` = "Mecklenburg-Vorpommern",
    `1413` = "Sachsen",
    `1414` = "Sachsen-Anhalt",
    `1415` = "Thüringen",
    `1416` = "Ausschl. Wirtschaftszone"
  )
  k <- trimws(as.character(code))
  out <- unname(m[k])
  ifelse(is.na(out), k, out)
}

ui <- mastr_page(
  title = "Batteriespeicher (Deutschland)",
  subtitle = "Thesis-Track: gefilterte MaStR-Einheiten (Technologie ≈ Batteriespeicher). Pumpspeicher siehe App „Speicher-Technologien“.",
  primary = THESIS_PRIMARY,

  layout_column_wrap(width = 1 / 4,
    uiOutput("kpi_n"), uiOutput("kpi_mw"), uiOutput("kpi_mwh"), uiOutput("kpi_crate")),

  layout_column_wrap(width = 1 / 2, heights_equal = "row",
    card(card_header("Leistung vs. nutzbare Kapazität"),
         plotlyOutput("plot_scatter", height = "400px")),
    card(card_header("Zubau nach Jahr (Summe Leistung)"),
         plotlyOutput("plot_buildout", height = "400px"))
  ),

  layout_column_wrap(width = 1 / 2,
    card(card_header("Installierte Leistung nach Bundesland"),
         plotlyOutput("plot_land", height = "380px")),
    card(card_header("Größte Einheiten nach Kapazität"),
         reactableOutput("table_top"))
  )
)

server <- function(input, output, session) {
  df <- reactive({
    d <- mastr_query(.sql_batteries())
    d$bundesland_name <- .bundesland_name(d$Bundesland)
    d
  })

  output$kpi_n   <- renderUI(mastr_kpi("Einheiten", fmt_num(nrow(df()))))
  output$kpi_mw  <- renderUI(mastr_kpi("Leistung", fmt_num(sum(df()$kw,  na.rm = TRUE) / 1000, 0, " MW")))
  output$kpi_mwh <- renderUI(mastr_kpi("Kapazität", fmt_num(sum(df()$kwh, na.rm = TRUE) / 1000, 0, " MWh")))
  output$kpi_crate <- renderUI({
    ok <- df()$kw > 0 & df()$kwh > 0
    cr <- if (any(ok, na.rm = TRUE)) {
      mean(df()$kw[ok] / df()$kwh[ok], na.rm = TRUE)
    } else NA
    mastr_kpi("Ø C-Rate", fmt_num(cr, 2, "  (kW/kWh)"))
  })

  output$plot_scatter <- renderPlotly({
    d <- df()[df()$kw > 0 & df()$kwh > 0, , drop = FALSE]
    if (nrow(d) == 0) {
      return(mastr_plotly_empty("Keine Daten (Filter)"))
    }
    plot_ly(d, x = ~kwh / 1000, y = ~kw / 1000, color = ~bundesland_name,
            type = "scatter", mode = "markers", marker = list(opacity = 0.5)) |>
      layout(xaxis = list(title = "Kapazität [MWh]", type = "log"),
             yaxis = list(title = "Leistung [MW]", type = "log"))
  })

  output$plot_buildout <- renderPlotly({
    d <- df()
    if (nrow(d) == 0) return(mastr_plotly_empty("Keine Daten"))
    d$yr <- format(d$inbetrieb, "%Y")
    d <- d[!is.na(d$yr) & d$yr != "NA", , drop = FALSE]
    agg <- aggregate(kw / 1000 ~ yr, data = d, FUN = sum)
    names(agg) <- c("year", "mw")
    plot_ly(agg, x = ~year, y = ~mw, type = "bar",
            marker = list(color = THESIS_PRIMARY))
  })

  output$plot_land <- renderPlotly({
    d <- df()
    if (nrow(d) == 0) return(mastr_plotly_empty("Keine Daten"))
    agg <- aggregate(kw ~ bundesland_name, data = d, FUN = sum)
    agg$mw <- agg$kw / 1000
    agg <- agg[order(-agg$mw), ]
    plot_ly(agg, x = ~reorder(bundesland_name, mw), y = ~mw, type = "bar",
            marker = list(color = THESIS_PRIMARY)) |>
      layout(xaxis = list(title = ""), yaxis = list(title = "MW"))
  })

  output$table_top <- renderReactable({
    d <- df()
    if (nrow(d) == 0) return(reactable(data.frame(Hinweis = "Keine Zeilen — ggf. Technologie-Labels in MaStR prüfen.")))
    d <- d[order(-d$kwh, na.last = TRUE), ][seq_len(min(40, nrow(d))), , drop = FALSE]
    d$kw_mw  <- round(d$kw / 1000, 2)
    d$kwh_mwh <- round(d$kwh / 1000, 2)
    want <- c("mastr_nr", "Technologie", "Batterietechnologie", "bundesland_name", "Gemeinde",
              "kw_mw", "kwh_mwh", "inbetrieb")
    d <- d[, intersect(want, names(d)), drop = FALSE]
    names(d)[names(d) == "bundesland_name"] <- "Bundesland"
    names(d)[names(d) == "kw_mw"] <- "MW"
    names(d)[names(d) == "kwh_mwh"] <- "MWh"
    reactable(d, compact = TRUE, striped = TRUE, defaultPageSize = 10, searchable = TRUE)
  })
}

shinyApp(ui, server)
