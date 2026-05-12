# 21_ibn_speicher_tabelle :: Tableau "Inbetriebnahmen Speicher MaStR - Tabelle" parity
# Full IBN table for storage — same layout as 18_ibn_tabelle but source table is stromspeicher.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(reactable); library(dplyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")

YEAR_NOW <- as.integer(format(Sys.Date(), "%Y"))

ui <- mastr_page(
  title = "Inbetriebnahmen Speicher MaStR \u2014 Tabelle",
  subtitle = "IBN-Zeitpunkt des Speichers, kann von IBN der Anlage abweichen.",
  fluid = TRUE,

  tableau_parity_banner("Inbetriebnahmen Speicher MaStR - Tabelle"),

  layout_sidebar(
    sidebar = sidebar(
      title = "Filter", width = 290,
      sliderInput("yr", "IBN-Jahre",
                  min = 2010, max = YEAR_NOW,
                  value = c(2017, YEAR_NOW),
                  sep = "", step = 1, ticks = FALSE),
      radioButtons("grain", "Zeitgranularit\u00e4t",
                   choices = c("Quartal" = "quarter", "Jahr" = "year", "Monat" = "month"),
                   selected = "quarter"),
      checkboxInput("only_active", "Nur aktive Einheiten", value = FALSE),
      selectizeInput("tech", "Batterietechnologie", choices = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button")))
    ),

    card(full_screen = TRUE,
         card_header("IBN Speicher \u2014 Werte und Differenzen"),
         reactableOutput("tbl", height = "auto")),

    div(class = "alert alert-warning py-2 mt-2",
        tags$b("Hinweis: "),
        "Die Spalte \u201EN\u00FCtzbare Speicherkapazit\u00e4t MWh\u201C ist aktuell nicht verf\u00fcgbar, ",
        "weil das ETL nur ", code("EinheitenStromSpeicher_*.xml"), " einliest \u2014 die Kapazit\u00e4tsdaten ",
        "stehen im separaten ", code("AnlagenStromSpeicher_*.xml"), ".")
  )
)

server <- function(input, output, session) {

  observe({
    t <- tryCatch(mastr_query(
      "SELECT DISTINCT Batterietechnologie FROM stromspeicher
       WHERE Batterietechnologie IS NOT NULL ORDER BY 1")[[1]],
      error = function(e) character())
    updateSelectizeInput(session, "tech", choices = t, selected = NULL)
  })

  where_sql <- reactive({
    p <- c("Inbetriebnahmedatum IS NOT NULL",
           sprintf("%s BETWEEN %d AND %d",
                   sql_ibn_year("Inbetriebnahmedatum"), input$yr[1], input$yr[2]))
    if (input$only_active) p <- c(p, "EinheitBetriebsstatus = 'InBetrieb'")
    if (length(input$tech))
      p <- c(p, sprintf("CAST(Batterietechnologie AS VARCHAR) IN (%s)",
                        mastr_sql_in(input$tech)))
    paste(p, collapse = " AND ")
  })

  grouped <- reactive({
    bucket_sql <- switch(input$grain,
                         "month"   = "DATE_TRUNC('month', Inbetriebnahmedatum)",
                         "quarter" = "DATE_TRUNC('quarter', Inbetriebnahmedatum)",
                         "year"    = "DATE_TRUNC('year', Inbetriebnahmedatum)")
    d <- mastr_query(sprintf("
      SELECT %s AS bucket,
             COUNT(*)                     AS speicher,
             SUM(Bruttoleistung)/1000.0   AS brutto_mw,
             SUM(Nettonennleistung)/1000.0 AS netto_mw
      FROM stromspeicher WHERE %s
      GROUP BY 1 ORDER BY 1 DESC",
      bucket_sql, where_sql()))
    if (!nrow(d)) return(d)
    d$bucket <- as.Date(d$bucket)
    d$d_speicher  <- c(NA, diff(d$speicher))  * -1
    d$d_brutto_mw <- c(NA, diff(d$brutto_mw)) * -1
    d$d_netto_mw  <- c(NA, diff(d$netto_mw))  * -1
    d
  })

  output$tbl <- renderReactable({
    d <- grouped()
    if (!nrow(d)) return(reactable(data.frame()))

    fmt_int <- function(v) formatC(v, big.mark = ".", decimal.mark = ",", format = "f", digits = 0)
    fmt_d1  <- function(v) formatC(v, big.mark = ".", decimal.mark = ",", format = "f", digits = 1)
    colour_delta <- function(value) {
      if (is.na(value) || !is.numeric(value)) return(NULL)
      if (value >= 0) list(color = "#15803d") else list(color = "#b91c1c")
    }

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
                 "speicher","d_speicher",
                 "brutto_mw","d_brutto_mw",
                 "netto_mw","d_netto_mw")]

    reactable(
      out, compact = TRUE, striped = TRUE, highlight = TRUE,
      defaultPageSize = 30, searchable = TRUE,
      columns = c(
        setNames(lapply(cols, function(c) colDef(name = c, sticky = "left", minWidth = 85)), cols),
        list(
          speicher    = colDef(name = "Speicher",     align = "right",
                               cell = function(v) fmt_int(v)),
          d_speicher  = colDef(name = "\u0394 Speicher", align = "right", style = colour_delta,
                               cell = function(v) fmt_int(v)),
          brutto_mw   = colDef(name = "Brutto MW Speicher",  align = "right",
                               cell = function(v) fmt_d1(v)),
          d_brutto_mw = colDef(name = "\u0394 Brutto MW",    align = "right", style = colour_delta,
                               cell = function(v) fmt_d1(v)),
          netto_mw    = colDef(name = "Netto MW Speicher",   align = "right",
                               cell = function(v) fmt_d1(v)),
          d_netto_mw  = colDef(name = "\u0394 Netto MW",     align = "right", style = colour_delta,
                               cell = function(v) fmt_d1(v))
        )
      )
    )
  })
}

shinyApp(ui, server)
