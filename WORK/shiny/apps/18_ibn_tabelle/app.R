# 18_ibn_tabelle :: Tableau "Inbetriebnahmen MaStR - Tabelle" parity
# Jahr x Quartal x Monat with Solaranlagen / Bruttoleistung MW / Nettonennleistung MW
# and the "Differenz zum Vorzeitraum" deltas that Tableau computes.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(reactable); library(dplyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")

YEAR_NOW <- as.integer(format(Sys.Date(), "%Y"))

ui <- mastr_page(
  title = "Inbetriebnahmen MaStR \u2014 Tabelle",
  subtitle = "IBN-Differenzen zum Vorzeitraum nach Jahr, Quartal und Monat (Tableau-Parit\u00e4t).",
  fluid = TRUE,

  tableau_parity_banner("Inbetriebnahmen MaStR - Tabelle"),

  layout_sidebar(
    sidebar = sidebar(
      title = "Filter", width = 290,
      sliderInput("yr", "IBN-Jahre",
                  min = 2010, max = YEAR_NOW,
                  value = c(max(YEAR_NOW - 4, 2018), YEAR_NOW),
                  sep = "", step = 1, ticks = FALSE),
      radioButtons("grain", "Zeitgranularit\u00e4t",
                   choices = c("Monat" = "month",
                               "Quartal" = "quarter",
                               "Jahr" = "year"),
                   selected = "month"),
      checkboxInput("only_active", "Nur aktive Einheiten", value = FALSE),
      selectizeInput("bl", "Bundesland", choices = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button"))),
      selectizeInput("nu", "Nutzungsbereich", choices = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button")))
    ),

    card(full_screen = TRUE,
         card_header("IBN der Solaranlagen \u2014 Werte und Differenzen"),
         reactableOutput("tbl", height = "auto"))
  )
)

server <- function(input, output, session) {

  observe({ updateSelectInput(session, "bl", choices = mastr_bundeslaender()) })
  observe({
    nu <- tryCatch(mastr_query(
      "SELECT DISTINCT Nutzungsbereich FROM solar WHERE Nutzungsbereich IS NOT NULL ORDER BY 1")[[1]],
      error = function(e) character())
    updateSelectizeInput(session, "nu", choices = nu, selected = NULL)
  })

  where_sql <- reactive({
    parts <- c(
      "Inbetriebnahmedatum IS NOT NULL",
      sprintf("%s BETWEEN %d AND %d",
              sql_ibn_year("Inbetriebnahmedatum"), input$yr[1], input$yr[2]))
    if (input$only_active)
      parts <- c(parts, "EinheitBetriebsstatus = 'InBetrieb'")
    if (length(input$bl)) {
      codes <- names(.BUNDESLAND)[.BUNDESLAND %in% input$bl]
      if (length(codes))
        parts <- c(parts, sprintf("CAST(Bundesland AS VARCHAR) IN (%s)",
                                  mastr_sql_in(codes)))
    }
    if (length(input$nu))
      parts <- c(parts, sprintf("CAST(Nutzungsbereich AS VARCHAR) IN (%s)",
                                mastr_sql_in(input$nu)))
    paste(parts, collapse = " AND ")
  })

  grouped <- reactive({
    grains <- switch(input$grain,
      "month" = list(bucket = "DATE_TRUNC('month', Inbetriebnahmedatum)"),
      "quarter" = list(bucket = "DATE_TRUNC('quarter', Inbetriebnahmedatum)"),
      "year" = list(bucket = "DATE_TRUNC('year', Inbetriebnahmedatum)"))
    sql <- sprintf("
      SELECT %s AS bucket,
             COUNT(*)                  AS solaranlagen,
             SUM(Bruttoleistung)/1000  AS bruttoleistung_mw,
             SUM(Nettonennleistung)/1000 AS nettonennleistung_mw
      FROM solar WHERE %s
      GROUP BY 1 ORDER BY 1 DESC",
      grains$bucket, where_sql())
    d <- mastr_query(sql)
    if (!nrow(d)) return(d)
    d$bucket <- as.Date(d$bucket)

    d <- d |> arrange(desc(bucket))
    # Differences to previous period (lag)
    d$delta_solaranlagen_abs  <- c(NA, diff(d$solaranlagen))       * -1  # higher row = newer, prev is row below
    d$delta_solaranlagen_pct  <- c(NA, diff(d$solaranlagen))       * -1 / c(NA, tail(d$solaranlagen, -1))
    d$delta_brutto_abs        <- c(NA, diff(d$bruttoleistung_mw))  * -1
    d$delta_brutto_pct        <- c(NA, diff(d$bruttoleistung_mw))  * -1 / c(NA, tail(d$bruttoleistung_mw, -1))
    d$delta_netto_abs         <- c(NA, diff(d$nettonennleistung_mw)) * -1
    d$delta_netto_pct         <- c(NA, diff(d$nettonennleistung_mw)) * -1 / c(NA, tail(d$nettonennleistung_mw, -1))
    d
  })

  output$tbl <- renderReactable({
    d <- grouped()
    if (!nrow(d)) return(reactable(data.frame()))

    fmt_int <- function(v) formatC(v, big.mark = ".", decimal.mark = ",",
                                   format = "f", digits = 0)
    fmt_d1  <- function(v) formatC(v, big.mark = ".", decimal.mark = ",",
                                   format = "f", digits = 1)
    fmt_pct <- function(v) ifelse(is.na(v), "",
                                  paste0(formatC(v * 100, format = "f", digits = 2,
                                                 big.mark = ".", decimal.mark = ","), "%"))

    if (input$grain == "month") {
      d$Jahr    <- format(d$bucket, "%Y")
      d$Quartal <- paste0("Q", ((as.integer(format(d$bucket, "%m")) - 1) %/% 3) + 1)
      d$Monat   <- MONTHS_DE[as.integer(format(d$bucket, "%m"))]
      cols <- c("Jahr","Quartal","Monat")
    } else if (input$grain == "quarter") {
      d$Jahr    <- format(d$bucket, "%Y")
      d$Quartal <- paste0("Q", ((as.integer(format(d$bucket, "%m")) - 1) %/% 3) + 1)
      cols <- c("Jahr","Quartal")
    } else {
      d$Jahr <- format(d$bucket, "%Y")
      cols <- c("Jahr")
    }

    out <- d[, c(cols,
                 "solaranlagen", "delta_solaranlagen_pct", "delta_solaranlagen_abs",
                 "bruttoleistung_mw", "delta_brutto_pct", "delta_brutto_abs",
                 "nettonennleistung_mw", "delta_netto_pct", "delta_netto_abs")]

    colour_delta <- function(value) {
      if (is.na(value)) return(NULL)
      if (!is.numeric(value)) return(NULL)
      if (value >= 0) list(color = "#15803d") else list(color = "#b91c1c")
    }

    reactable(
      out, compact = TRUE, striped = TRUE, highlight = TRUE,
      defaultPageSize = 30, searchable = TRUE, bordered = FALSE,
      columns = c(
        setNames(lapply(cols, function(c) colDef(name = c, sticky = "left",
                                                 minWidth = 85)), cols),
        list(
          solaranlagen            = colDef(name = "Solaranlagen", align = "right",
                                           cell = function(v) fmt_int(v)),
          delta_solaranlagen_pct  = colDef(name = "% Diff. Solaranlagen zu Vorzeitraum",
                                           align = "right", style = colour_delta,
                                           cell = function(v) fmt_pct(v)),
          delta_solaranlagen_abs  = colDef(name = "Diff. Solaranlagen zu Vorzeitraum",
                                           align = "right", style = colour_delta,
                                           cell = function(v) fmt_int(v)),
          bruttoleistung_mw       = colDef(name = "Bruttoleistung MW", align = "right",
                                           cell = function(v) fmt_d1(v)),
          delta_brutto_pct        = colDef(name = "% Diff. Bruttoleistung zu Vorzeitraum",
                                           align = "right", style = colour_delta,
                                           cell = function(v) fmt_pct(v)),
          delta_brutto_abs        = colDef(name = "Diff. Bruttoleistung MW zu Vorzeitraum",
                                           align = "right", style = colour_delta,
                                           cell = function(v) fmt_d1(v)),
          nettonennleistung_mw    = colDef(name = "Nettonennleistung MW", align = "right",
                                           cell = function(v) fmt_d1(v)),
          delta_netto_pct         = colDef(name = "% Diff. Nettonennleistung zu Vorzeitraum",
                                           align = "right", style = colour_delta,
                                           cell = function(v) fmt_pct(v)),
          delta_netto_abs         = colDef(name = "Diff. Nettonennleistung MW zu Vorzeitraum",
                                           align = "right", style = colour_delta,
                                           cell = function(v) fmt_d1(v))
        )
      )
    )
  })
}

shinyApp(ui, server)
