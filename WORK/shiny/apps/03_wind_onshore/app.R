# 03_wind_onshore :: onshore wind fleet

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable); library(dplyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")

ui <- mastr_page(
  title = "Wind — Onshore",
  subtitle = "Turbinen-Populationen, Nabenhöhen, Rotordurchmesser und Zubau.",
  fluid = TRUE,
  layout_sidebar(
    sidebar = sidebar(
      title = "Filter", width = 260,
      selectInput("bl", "Bundesland", choices = NULL, multiple = TRUE),
      sliderInput("year", "Inbetriebnahme", min = 1990,
                  max = as.integer(format(Sys.Date(), "%Y")),
                  value = c(2000, as.integer(format(Sys.Date(), "%Y"))), sep = ""),
      sliderInput("mw", "Bruttoleistung (MW)", min = 0, max = 15,
                  value = c(0, 15), step = 0.1)
    ),

    layout_column_wrap(1/3,
      uiOutput("kpi_turbines"), uiOutput("kpi_mw"), uiOutput("kpi_avg_mw")),

    layout_column_wrap(1/2, heights_equal = "row",
      card(card_header("Nabenhöhe vs. Rotordurchmesser"),
           plotlyOutput("plot_scatter", height = "420px")),
      card(card_header("Zubau Jahr × Bundesland"),
           plotlyOutput("plot_buildout", height = "420px"))
    ),

    card(card_header("Größte aktive Onshore-Anlagen"),
         reactableOutput("table_top"))
  )
)

server <- function(input, output, session) {
  observe({ updateSelectInput(session, "bl", choices = mastr_bundeslaender()) })

  where_sql <- reactive({
    parts <- c("energietraeger = 'Wind'",
               "(Lage IS NULL OR Lage <> 'WindAufSee')")
    if (length(input$bl))
      parts <- c(parts, sprintf("bundesland_name IN (%s)", mastr_sql_in(input$bl)))
    parts <- c(parts, sprintf(
      "EXTRACT(YEAR FROM inbetriebnahme_datum) BETWEEN %d AND %d",
      input$year[1], input$year[2]))
    parts <- c(parts, sprintf(
      "bruttoleistung_kw BETWEEN %f AND %f",
      input$mw[1] * 1000, input$mw[2] * 1000))
    paste(parts, collapse = " AND ")
  })

  summary_row <- reactive({
    mastr_query(sprintf("
      SELECT COUNT(*) AS t,
             SUM(bruttoleistung_kw)/1000 AS mw,
             AVG(bruttoleistung_kw)/1000 AS avg_mw
      FROM v_units_all
      WHERE %s", where_sql()))
  })

  output$kpi_turbines <- renderUI(mastr_kpi("Turbinen", fmt_num(summary_row()$t[1])))
  output$kpi_mw       <- renderUI(mastr_kpi("Installiert", fmt_num(summary_row()$mw[1], 0, " MW")))
  output$kpi_avg_mw   <- renderUI(mastr_kpi("Ø Turbine", fmt_num(summary_row()$avg_mw[1], 2, " MW")))

  output$plot_scatter <- renderPlotly({
    d <- mastr_query(sprintf("
      SELECT TRY_CAST(Nabenhoehe AS DOUBLE) AS nabenhoehe,
             TRY_CAST(Rotordurchmesser AS DOUBLE) AS rotor,
             TRY_CAST(Bruttoleistung AS DOUBLE)/1000 AS mw,
             Bundesland
      FROM wind
      WHERE TRY_CAST(Nabenhoehe AS DOUBLE) BETWEEN 30 AND 200
        AND TRY_CAST(Rotordurchmesser AS DOUBLE) BETWEEN 20 AND 200
      LIMIT 50000"))
    plot_ly(d, x = ~rotor, y = ~nabenhoehe, size = ~mw, color = ~mw,
            type = "scatter", mode = "markers",
            marker = list(opacity = 0.35, sizemode = "area", sizeref = 0.05)) |>
      layout(xaxis = list(title = "Rotordurchmesser [m]"),
             yaxis = list(title = "Nabenhöhe [m]"))
  })

  output$plot_buildout <- renderPlotly({
    d <- mastr_query(sprintf("
      SELECT EXTRACT(YEAR FROM inbetriebnahme_datum) AS year,
             bundesland_name,
             SUM(bruttoleistung_kw)/1000 AS mw
      FROM v_units_all
      WHERE %s AND inbetriebnahme_datum IS NOT NULL
      GROUP BY 1, 2", where_sql()))
    plot_ly(d, x = ~year, y = ~mw, color = ~bundesland_name, type = "bar") |>
      layout(barmode = "stack", yaxis = list(title = "MW / Jahr"),
             xaxis = list(title = ""))
  })

  output$table_top <- renderReactable({
    d <- mastr_query(sprintf("
      SELECT mastr_nr, bundesland_name, gemeinde,
             ROUND(bruttoleistung_kw/1000, 2) AS mw,
             inbetriebnahme_datum
      FROM v_units_all WHERE %s AND betriebsstatus = 'InBetrieb'
      ORDER BY bruttoleistung_kw DESC LIMIT 50", where_sql()))
    reactable(d, compact = TRUE, striped = TRUE, defaultPageSize = 10,
              searchable = TRUE)
  })
}

shinyApp(ui, server)
