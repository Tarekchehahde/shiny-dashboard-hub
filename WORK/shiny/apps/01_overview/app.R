# 01_overview :: top-level MaStR KPIs
# Run: shiny::runApp(".") from this folder, or shiny::runApp("apps/01_overview")

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(dplyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")

ui <- mastr_page(
  title = "MaStR — Deutschland Überblick",
  subtitle = "Alle Einheiten im Marktstammdatenregister, nächtlich aktualisiert.",

  layout_column_wrap(
    width = 1/4, heights_equal = "row", fill = FALSE,
    uiOutput("kpi_units"),
    uiOutput("kpi_capacity"),
    uiOutput("kpi_ee_units"),
    uiOutput("kpi_ee_capacity")
  ),

  layout_column_wrap(
    width = 1/2, heights_equal = "row", fill = FALSE,
    card(card_header("Installierte Leistung nach Energieträger"),
         plotlyOutput("plot_capacity_by_tech", height = "380px")),
    card(card_header("Zubau pro Monat (letzte 10 Jahre)"),
         plotlyOutput("plot_buildout", height = "380px"))
  ),

  card(card_header("Bundesländer — Einheiten & installierte Leistung"),
       plotlyOutput("plot_states", height = "420px"))
)

server <- function(input, output, session) {

  kpi <- reactive({ mastr_table("agg_kpi_overview") })

  output$kpi_units <- renderUI({
    k <- kpi()
    mastr_kpi("Einheiten gesamt", fmt_num(k$units_total[1]),
              "Alle Energieträger", color = "primary")
  })
  output$kpi_capacity <- renderUI({
    k <- kpi()
    mastr_kpi("Installierte Leistung", fmt_num(k$capacity_gw[1], 1, " GW"),
              "Bruttoleistung", color = "info")
  })
  output$kpi_ee_units <- renderUI({
    k <- kpi()
    mastr_kpi("EE-Einheiten", fmt_num(k$ee_units[1]),
              "Solar, Wind, Biomasse, Wasser, Geothermie", color = "success")
  })
  output$kpi_ee_capacity <- renderUI({
    k <- kpi()
    mastr_kpi("EE-Leistung", fmt_num(k$ee_capacity_gw[1], 1, " GW"),
              sprintf("Stand: %s", k$as_of[1]), color = "success")
  })

  output$plot_capacity_by_tech <- renderPlotly({
    d <- mastr_query("
      SELECT energietraeger, SUM(bruttoleistung_mw) AS mw
      FROM agg_capacity_by_state
      GROUP BY 1 ORDER BY 2 DESC
    ")
    plot_ly(d, x = ~reorder(energietraeger, mw), y = ~mw, type = "bar",
            marker = list(color = MASTR_PALETTE$primary)) |>
      layout(xaxis = list(title = ""), yaxis = list(title = "MW"),
             margin = list(t = 20))
  })

  output$plot_buildout <- renderPlotly({
    d <- mastr_query("
      SELECT month, energietraeger, new_capacity_mw
      FROM agg_buildout_monthly
      WHERE month >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL 10 YEAR)
    ")
    plot_ly(d, x = ~month, y = ~new_capacity_mw, color = ~energietraeger,
            type = "scatter", mode = "lines", stackgroup = "one") |>
      layout(xaxis = list(title = ""), yaxis = list(title = "MW Zubau / Monat"),
             legend = list(orientation = "h", y = -0.2))
  })

  output$plot_states <- renderPlotly({
    d <- mastr_query("
      SELECT bundesland_name, energietraeger,
             SUM(bruttoleistung_mw) AS mw,
             SUM(units) AS units
      FROM agg_capacity_by_state
      GROUP BY 1, 2
    ")
    plot_ly(d, x = ~bundesland_name, y = ~mw, color = ~energietraeger,
            type = "bar") |>
      layout(barmode = "stack",
             xaxis = list(title = "", categoryorder = "total descending"),
             yaxis = list(title = "MW"))
  })
}

shinyApp(ui, server)
