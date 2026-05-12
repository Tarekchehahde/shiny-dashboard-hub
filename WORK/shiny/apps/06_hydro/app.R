# 06_hydro :: Wasserkraft

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable)
})
source("../../R/mastr_data.R"); source("../../R/ui_helpers.R")

ui <- mastr_page(
  title = "Wasserkraft",
  subtitle = "Laufwasser, Speicher- und Pumpspeicherwerke.",
  fluid = TRUE,

  layout_column_wrap(1/3,
    uiOutput("kpi_n"), uiOutput("kpi_mw"), uiOutput("kpi_top")),

  layout_column_wrap(1/2, heights_equal = "row",
    card(card_header("Wasserkraftart"),
         plotlyOutput("plot_type", height = "380px")),
    card(card_header("Leistung nach Bundesland"),
         plotlyOutput("plot_state", height = "380px"))
  ),

  card(card_header("Größte Wasserkraftwerke"),
       reactableOutput("table_top"))
)

server <- function(input, output, session) {
  summ <- reactive(mastr_query("
    SELECT COUNT(*) AS n, SUM(bruttoleistung_kw)/1000 AS mw
    FROM v_units_all WHERE energietraeger='Wasser'"))
  top  <- reactive(mastr_query("
    SELECT MAX(bruttoleistung_kw)/1000 AS top_mw FROM v_units_all WHERE energietraeger='Wasser'"))

  output$kpi_n   <- renderUI(mastr_kpi("Einheiten", fmt_num(summ()$n[1])))
  output$kpi_mw  <- renderUI(mastr_kpi("Leistung",  fmt_num(summ()$mw[1], 0, " MW")))
  output$kpi_top <- renderUI(mastr_kpi("Größte Anlage", fmt_num(top()$top_mw[1], 0, " MW")))

  output$plot_type <- renderPlotly({
    d <- mastr_query("
      SELECT COALESCE(ArtDerWasserkraftanlage, '(unbekannt)') AS art,
             COUNT(*) AS n,
             SUM(TRY_CAST(Bruttoleistung AS DOUBLE))/1000 AS mw
      FROM wasser GROUP BY 1")
    plot_ly(d, labels = ~art, values = ~mw, type = "pie", hole = 0.45) |>
      layout(showlegend = TRUE)
  })

  output$plot_state <- renderPlotly({
    d <- mastr_query("
      SELECT bundesland_name, SUM(bruttoleistung_kw)/1000 AS mw
      FROM v_units_all WHERE energietraeger='Wasser' AND bundesland_name IS NOT NULL
      GROUP BY 1 ORDER BY mw DESC")
    plot_ly(d, x = ~reorder(bundesland_name, mw), y = ~mw, type = "bar",
            marker = list(color = MASTR_PALETTE$water)) |>
      layout(xaxis = list(title = ""), yaxis = list(title = "MW"))
  })

  output$table_top <- renderReactable({
    d <- mastr_query("
      SELECT mastr_nr, bundesland_name, gemeinde,
             ROUND(bruttoleistung_kw/1000, 1) AS mw, inbetriebnahme_datum
      FROM v_units_all WHERE energietraeger='Wasser'
      ORDER BY bruttoleistung_kw DESC NULLS LAST LIMIT 50")
    reactable(d, compact = TRUE, striped = TRUE, defaultPageSize = 10, searchable = TRUE)
  })
}
shinyApp(ui, server)
