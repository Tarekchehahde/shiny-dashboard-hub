# 08_storage :: Stromspeicher (Batterien + Pumpspeicher)

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable)
})
source("../../R/mastr_data.R"); source("../../R/ui_helpers.R")

# BNetzA ships storage data across TWO XML streams:
#   EinheitenStromSpeicher_*.xml  — the generator (power) side. Has
#       Bruttoleistung, Technologie, Batterietechnologie, Inbetriebnahmedatum.
#   AnlagenStromSpeicher_*.xml    — the storage asset (energy) side. Has
#       NutzbareSpeicherkapazitaet, Pumpspeichertechnologie details, etc.
#
# The current ETL ingests only the first file (that's the `stromspeicher`
# parquet). Until AnlagenStromSpeicher_*.xml is added to config.ENTITIES we
# surface power-side metrics only and note the missing capacity KPI instead
# of crashing on `Referenced column "NutzbareSpeicherkapazitaet" not found`.

ui <- mastr_page(
  title = "Stromspeicher",
  subtitle = "Batterie- und Pumpspeicher-Einheiten, Leistung & Technologie-Mix.",
  fluid = TRUE,

  layout_column_wrap(1/4, heights_equal = "row", fill = FALSE,
    uiOutput("kpi_n"),
    uiOutput("kpi_mw"),
    uiOutput("kpi_avg_kw"),
    uiOutput("kpi_tech")
  ),

  layout_column_wrap(1/2, heights_equal = "row",
    card(full_screen = TRUE,
         card_header("Technologie-Mix (Anteile)"),
         plotlyOutput("plot_tech", height = "400px")),
    card(full_screen = TRUE,
         card_header("Zubau nach Jahr"),
         plotlyOutput("plot_buildout", height = "400px"))
  ),

  card(full_screen = TRUE,
       card_header("Top 30 Einheiten nach Bruttoleistung (kW)"),
       reactableOutput("table_top")),

  card(class = "border-warning",
       card_body(
         class = "text-muted small",
         HTML(paste0(
           "<strong>Hinweis:</strong> Nutzbare Speicherkapazität (MWh) und ",
           "C-Rate werden aus <code>AnlagenStromSpeicher_*.xml</code> gespeist. ",
           "Dieser XML-Datensatz ist im aktuellen Release noch nicht ingestiert; ",
           "sobald <code>WORK/etl/src/mastr_etl/config.py</code> eine Entität ",
           "<code>anlagen_speicher</code> enthält, werden diese KPIs ergänzt."
         ))
       ))
)

server <- function(input, output, session) {

  df <- reactive({
    mastr_query("
      SELECT EinheitMastrNummer AS mastr_nr,
             TRY_CAST(Bruttoleistung AS DOUBLE)              AS kw,
             TRY_CAST(Inbetriebnahmedatum AS DATE)           AS inbetrieb,
             COALESCE(Technologie, Batterietechnologie, 'Unbekannt')
                                                             AS technologie,
             Bundesland
      FROM stromspeicher")
  })

  output$kpi_n     <- renderUI(mastr_kpi("Einheiten", fmt_num(nrow(df()))))
  output$kpi_mw    <- renderUI(mastr_kpi("Installierte Leistung",
                                         fmt_num(sum(df()$kw, na.rm = TRUE) / 1000,
                                                 0, " MW")))
  output$kpi_avg_kw <- renderUI({
    mastr_kpi("Ø Einheit",
              fmt_num(mean(df()$kw[df()$kw > 0], na.rm = TRUE), 1, " kW"))
  })
  output$kpi_tech <- renderUI({
    tbl <- sort(table(df()$technologie), decreasing = TRUE)
    top <- if (length(tbl)) names(tbl)[1] else "—"
    share <- if (length(tbl)) 100 * tbl[[1]] / sum(tbl) else 0
    mastr_kpi("Dominante Technologie", top,
              fmt_num(share, 1, " % aller Einheiten"),
              color = "info")
  })

  output$plot_tech <- renderPlotly({
    d <- as.data.frame(table(df()$technologie))
    names(d) <- c("technologie", "n")
    d <- d[order(-d$n), ]
    plot_ly(d, x = ~reorder(technologie, n), y = ~n, type = "bar",
            marker = list(color = MASTR_PALETTE$storage)) |>
      layout(margin = list(t = 30, r = 20, b = 100, l = 60),
             xaxis = list(title = "", tickangle = -30, automargin = TRUE),
             yaxis = list(title = list(text = "Einheiten", standoff = 10),
                          automargin = TRUE)) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d", "select2d", "autoScale2d"))
  })

  output$plot_buildout <- renderPlotly({
    valid <- !is.na(df()$inbetrieb)
    years <- as.integer(format(df()$inbetrieb[valid], "%Y"))
    kw_by_year <- tapply(df()$kw[valid], years, sum, na.rm = TRUE)
    d <- data.frame(year = as.integer(names(kw_by_year)),
                    mw   = as.numeric(kw_by_year) / 1000)
    d <- d[d$year >= 2000, ]
    plot_ly(d, x = ~year, y = ~mw, type = "bar",
            marker = list(color = MASTR_PALETTE$storage)) |>
      layout(margin = list(t = 30, r = 30, b = 50, l = 60),
             xaxis = list(title = "", dtick = 2, automargin = TRUE),
             yaxis = list(title = list(text = "Zubau MW", standoff = 10),
                          automargin = TRUE)) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d", "select2d", "autoScale2d"))
  })

  output$table_top <- renderReactable({
    d <- df()
    d <- d[order(-d$kw, na.last = TRUE), ][seq_len(min(30, nrow(d))), ]
    d$MW <- round(d$kw / 1000, 3)
    d$Jahr <- format(d$inbetrieb, "%Y")
    d <- d[, c("mastr_nr", "technologie", "Bundesland", "Jahr", "MW")]
    reactable(d, compact = TRUE, striped = TRUE, highlight = TRUE,
              defaultPageSize = 10, searchable = TRUE,
              columns = list(
                mastr_nr    = colDef(name = "MaStR-Nr.", width = 180),
                technologie = colDef(name = "Technologie"),
                Bundesland  = colDef(name = "Bundesland-Code", width = 130),
                Jahr        = colDef(name = "Jahr", width = 90, align = "right"),
                MW          = colDef(name = "MW", align = "right",
                                     format = colFormat(separators = TRUE, digits = 3))
              ))
  })
}

shinyApp(ui, server)
