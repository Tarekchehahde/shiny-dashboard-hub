# 05_biomass :: Biomass / biogas / waste-to-energy

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable)
})
source("../../R/mastr_data.R"); source("../../R/ui_helpers.R")

ui <- mastr_page(
  title = "Biomasse & Biogas",
  subtitle = "Anlagen der stofflichen / thermischen Verwertung in Deutschland.",
  fluid = TRUE,

  layout_column_wrap(1/3,
    uiOutput("kpi_n"), uiOutput("kpi_mw"), uiOutput("kpi_avg")),

  layout_column_wrap(1/2, heights_equal = "row",
    card(card_header("Leistung nach Bundesland"),
         plotlyOutput("plot_state", height = "380px")),
    card(card_header("Zubau-Historie"),
         plotlyOutput("plot_buildout", height = "380px"))
  ),

  card(card_header("Hauptbrennstoff / Biomasseart"),
       reactableOutput("table_fuel"))
)

server <- function(input, output, session) {
  summ <- reactive(mastr_query("
    SELECT COUNT(*) AS n, SUM(bruttoleistung_kw)/1000 AS mw, AVG(bruttoleistung_kw) AS avg_kw
    FROM v_units_all WHERE energietraeger = 'Biomasse'"))

  output$kpi_n   <- renderUI(mastr_kpi("Einheiten", fmt_num(summ()$n[1])))
  output$kpi_mw  <- renderUI(mastr_kpi("Leistung",  fmt_num(summ()$mw[1], 0, " MW")))
  output$kpi_avg <- renderUI(mastr_kpi("Ø Leistung", fmt_num(summ()$avg_kw[1], 0, " kW")))

  output$plot_state <- renderPlotly({
    d <- mastr_query("
      SELECT bundesland_name, SUM(bruttoleistung_kw)/1000 AS mw, COUNT(*) AS n
      FROM v_units_all WHERE energietraeger='Biomasse' AND bundesland_name IS NOT NULL
      GROUP BY 1 ORDER BY mw DESC")
    plot_ly(d, x = ~reorder(bundesland_name, mw), y = ~mw, type = "bar",
            marker = list(color = MASTR_PALETTE$biomass)) |>
      layout(xaxis = list(title = ""), yaxis = list(title = "MW"))
  })

  output$plot_buildout <- renderPlotly({
    d <- mastr_query("
      SELECT EXTRACT(YEAR FROM inbetriebnahme_datum) AS year,
             SUM(bruttoleistung_kw)/1000 AS mw
      FROM v_units_all WHERE energietraeger='Biomasse'
        AND inbetriebnahme_datum IS NOT NULL
      GROUP BY 1 ORDER BY 1")
    plot_ly(d, x = ~year, y = ~mw, type = "bar",
            marker = list(color = MASTR_PALETTE$biomass)) |>
      layout(yaxis = list(title = "MW Zubau"))
  })

  output$table_fuel <- renderReactable({
    d <- mastr_query("
      SELECT COALESCE(Hauptbrennstoff, '(unbekannt)') AS brennstoff,
             COUNT(*) AS einheiten,
             ROUND(SUM(TRY_CAST(Bruttoleistung AS DOUBLE))/1000, 1) AS mw
      FROM biomasse
      GROUP BY 1 ORDER BY mw DESC NULLS LAST LIMIT 50")
    reactable(d, compact = TRUE, striped = TRUE, defaultPageSize = 10, searchable = TRUE)
  })
}
shinyApp(ui, server)
