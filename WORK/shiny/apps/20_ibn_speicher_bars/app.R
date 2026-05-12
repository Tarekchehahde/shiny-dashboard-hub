# 20_ibn_speicher_bars :: Tableau "Inbetriebnahmen Speicher MaStR" parity
# Quarterly bar panels for storage units and storage power (MW Speicher).
# NOTE: Nutzbare Speicherkapazität MWh is NOT yet in our parquet (see
# etl/AnlagenStromSpeicher_*.xml, which is not ingested yet) — that sheet
# is displayed as "pending" below.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(dplyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")

YEAR_NOW <- as.integer(format(Sys.Date(), "%Y"))

ui <- mastr_page(
  title = "Inbetriebnahmen Speicher MaStR \u2014 Quartalsbalken",
  subtitle = "IBN-Zeitpunkt des Speichers, kann von IBN der Anlage abweichen.",
  fluid = TRUE,

  tableau_parity_banner("Inbetriebnahmen Speicher MaStR"),

  layout_sidebar(
    sidebar = sidebar(
      title = "Filter", width = 290,
      sliderInput("yr", "IBN-Jahre",
                  min = 2008, max = YEAR_NOW,
                  value = c(2012, YEAR_NOW),
                  sep = "", step = 1, ticks = FALSE),
      selectizeInput("bl", "Bundesland", choices = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button"))),
      selectizeInput("tech", "Batterietechnologie", choices = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button"))),
      checkboxInput("only_active", "Nur aktive Einheiten", value = FALSE)
    ),

    card(full_screen = TRUE, height = "760px",
         card_header("Quartalsweise: Speicher und Bruttoleistung MW (+ Differenzen)"),
         plotlyOutput("plot_bars", height = "700px")),

    div(class = "alert alert-warning py-2 mt-2",
        tags$b("Hinweis: "),
        "Nutzbare Speicherkapazit\u00e4t MWh ist derzeit nicht Teil der ingesten ",
        "Parquet-Tabelle. Die Daten stehen in ",
        code("AnlagenStromSpeicher_*.xml"),
        " (separates BNetzA-Dataset). Das ETL ingestiert aktuell nur ",
        code("EinheitenStromSpeicher_*.xml"),
        " \u2014 um die Kapazit\u00e4ts-Tabelle freizuschalten, ",
        code("anlagen_speicher"),
        " als neuen Entity-Eintrag in ",
        code("WORK/etl/src/mastr_etl/config.py"),
        " erg\u00e4nzen und einen Nightly-Run ausl\u00f6sen.")
  )
)

server <- function(input, output, session) {

  observe({ updateSelectInput(session, "bl", choices = mastr_bundeslaender()) })
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
    if (length(input$bl)) {
      codes <- names(.BUNDESLAND)[.BUNDESLAND %in% input$bl]
      if (length(codes))
        p <- c(p, sprintf("CAST(Bundesland AS VARCHAR) IN (%s)",
                          mastr_sql_in(codes)))
    }
    if (length(input$tech))
      p <- c(p, sprintf("CAST(Batterietechnologie AS VARCHAR) IN (%s)",
                        mastr_sql_in(input$tech)))
    paste(p, collapse = " AND ")
  })

  quarterly <- reactive({
    d <- mastr_query(sprintf("
      SELECT DATE_TRUNC('quarter', Inbetriebnahmedatum) AS q,
             COUNT(*) AS speicher,
             SUM(Bruttoleistung)/1000.0 AS mw
      FROM stromspeicher WHERE %s
      GROUP BY 1 ORDER BY 1", where_sql()))
    if (!nrow(d)) return(d)
    d$q <- as.Date(d$q)
    d$qlabel <- sprintf("%s Q%s", format(d$q, "%Y"),
                        ((as.integer(format(d$q, "%m")) - 1) %/% 3) + 1)
    d$d_speicher <- c(NA, diff(d$speicher))
    d$d_mw       <- c(NA, diff(d$mw))
    d
  })

  output$plot_bars <- renderPlotly({
    d <- quarterly()
    if (!nrow(d)) return(plotly_empty())

    col_sp <- MASTR_PALETTE$primary
    col_mw <- MASTR_PALETTE$storage

    mk <- function(y, col, ytitle) {
      plot_ly(d, x = ~qlabel, y = y, type = "bar",
              marker = list(color = col),
              hovertemplate = paste0("%{x}<br>", ytitle, ": %{y:,.1f}<extra></extra>")) |>
        layout(yaxis = list(title = list(text = ytitle, standoff = 8),
                            automargin = TRUE),
               xaxis = list(title = "", tickangle = -30))
    }

    p1 <- mk(d$d_speicher, col_sp, "\u0394 Speicher")
    p2 <- mk(d$speicher,   col_sp, "Speicher")
    p3 <- mk(d$d_mw,       col_mw, "\u0394 Brutto MW")
    p4 <- mk(d$mw,         col_mw, "Brutto MW Speicher")

    subplot(p1, p2, p3, p4, nrows = 4, shareX = TRUE, titleY = FALSE, margin = 0.015) |>
      layout(showlegend = FALSE,
             margin = list(t = 10, r = 10, b = 70, l = 60)) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  })
}

shinyApp(ui, server)
