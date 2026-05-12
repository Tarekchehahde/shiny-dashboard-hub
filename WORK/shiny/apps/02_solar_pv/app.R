# 02_solar_pv :: German PV fleet

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable); library(dplyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")

ui <- mastr_page(
  title = "Solar — Photovoltaik-Einheiten",
  subtitle = "Größenklassen, Zubau und regionale Verteilung der PV-Anlagen.",
  fluid = TRUE,

  layout_sidebar(
    sidebar = sidebar(
      title = "Filter", width = 290,
      selectizeInput("bl", "Bundesland (Mehrfachauswahl)",
                     choices = NULL, selected = NULL, multiple = TRUE,
                     options = list(
                       placeholder = "Alle Bundesländer",
                       plugins = list("remove_button"))),
      sliderInput("year", "Inbetriebnahme-Jahre",
                  min = 1990, max = as.integer(format(Sys.Date(), "%Y")),
                  value = c(2010, as.integer(format(Sys.Date(), "%Y"))),
                  sep = "", step = 1,
                  ticks = FALSE),
      radioButtons("status", "Betriebsstatus",
                   choices = c("Alle" = "all", "Nur aktive" = "active"),
                   selected = "all"),
      actionButton("refresh", "Daten neu laden", class = "btn-sm btn-outline-primary")
    ),

    layout_column_wrap(
      width = 1/3, heights_equal = "row", fill = FALSE,
      uiOutput("kpi_count"), uiOutput("kpi_mw"), uiOutput("kpi_avg_kw")
    ),

    layout_column_wrap(
      width = 1/2, heights_equal = "row",
      card(full_screen = TRUE,
           card_header("Größenklassen (Bruttoleistung)"),
           plotlyOutput("plot_size_classes", height = "420px")),
      card(full_screen = TRUE,
           card_header("Zubau nach Jahr"),
           plotlyOutput("plot_buildout_year", height = "420px"))
    ),

    card(full_screen = TRUE,
         card_header("Top 30 Postleitzahlen nach installierter Leistung"),
         reactableOutput("table_plz", height = "auto"))
  )
)

server <- function(input, output, session) {

  observe({ updateSelectInput(session, "bl", choices = mastr_bundeslaender()) })

  where_sql <- reactive({
    parts <- c("energietraeger = 'SolareStrahlungsenergie'")
    if (length(input$bl))
      parts <- c(parts, sprintf("bundesland_name IN (%s)", mastr_sql_in(input$bl)))
    parts <- c(parts, sprintf(
      "EXTRACT(YEAR FROM inbetriebnahme_datum) BETWEEN %d AND %d",
      input$year[1], input$year[2]))
    if (input$status == "active")
      parts <- c(parts, "betriebsstatus = 'InBetrieb'")
    paste(parts, collapse = " AND ")
  })

  summary_row <- reactive({
    mastr_query(sprintf("
      SELECT COUNT(*) AS units,
             SUM(bruttoleistung_kw)/1000 AS mw,
             AVG(bruttoleistung_kw)      AS avg_kw
      FROM v_units_all WHERE %s", where_sql()))
  })

  output$kpi_count  <- renderUI(mastr_kpi("PV-Einheiten", fmt_num(summary_row()$units[1])))
  output$kpi_mw     <- renderUI(mastr_kpi("Installierte Leistung",
                                          fmt_num(summary_row()$mw[1], 0, " MW")))
  output$kpi_avg_kw <- renderUI(mastr_kpi("Ø Einheit",
                                          fmt_num(summary_row()$avg_kw[1], 1, " kW")))

  output$plot_size_classes <- renderPlotly({
    d <- mastr_query(sprintf("
      SELECT
        CASE
          WHEN bruttoleistung_kw < 10    THEN '0–10 kW'
          WHEN bruttoleistung_kw < 30    THEN '10–30 kW'
          WHEN bruttoleistung_kw < 100   THEN '30–100 kW'
          WHEN bruttoleistung_kw < 750   THEN '100–750 kW'
          WHEN bruttoleistung_kw < 10000 THEN '0.75–10 MW'
          ELSE '>10 MW' END AS size_class,
        COUNT(*) AS units,
        SUM(bruttoleistung_kw)/1000 AS mw
      FROM v_units_all WHERE %s
      GROUP BY 1", where_sql()))
    d$size_class <- factor(d$size_class,
                           levels = c("0–10 kW","10–30 kW","30–100 kW",
                                      "100–750 kW","0.75–10 MW",">10 MW"))
    plot_ly(d, x = ~size_class, y = ~units, type = "bar",
            marker = list(color = MASTR_PALETTE$solar), name = "Einheiten") |>
      add_trace(y = ~mw, yaxis = "y2", name = "MW",
                marker = list(color = MASTR_PALETTE$primary)) |>
      layout(margin = list(t = 30, r = 60, b = 70, l = 60),
             yaxis  = list(title = list(text = "Einheiten", standoff = 10),
                           automargin = TRUE),
             yaxis2 = list(title = list(text = "MW", standoff = 10),
                           overlaying = "y", side = "right",
                           showgrid = FALSE, automargin = TRUE),
             xaxis  = list(title = "", tickangle = -20, automargin = TRUE),
             legend = list(orientation = "h", y = -0.20, x = 0.5,
                           xanchor = "center")) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  })

  output$plot_buildout_year <- renderPlotly({
    d <- mastr_query(sprintf("
      SELECT EXTRACT(YEAR FROM inbetriebnahme_datum) AS year,
             SUM(bruttoleistung_kw)/1000 AS mw,
             COUNT(*) AS units
      FROM v_units_all
      WHERE %s AND inbetriebnahme_datum IS NOT NULL
      GROUP BY 1 ORDER BY 1", where_sql()))
    plot_ly(d, x = ~year, y = ~mw, type = "bar",
            marker = list(color = MASTR_PALETTE$solar)) |>
      layout(margin = list(t = 30, r = 30, b = 60, l = 60),
             yaxis = list(title = list(text = "Zubau MW", standoff = 10),
                          automargin = TRUE),
             xaxis = list(title = "", dtick = 2, automargin = TRUE)) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  })

  output$table_plz <- renderReactable({
    d <- mastr_query(sprintf("
      SELECT plz, COUNT(*) AS units,
             ROUND(SUM(bruttoleistung_kw)/1000, 1) AS mw
      FROM v_units_all WHERE %s AND plz IS NOT NULL
      GROUP BY 1 ORDER BY mw DESC LIMIT 30", where_sql()))
    reactable(d, compact = TRUE, striped = TRUE, highlight = TRUE,
              defaultPageSize = 10, minRows = 10,
              columns = list(
                plz   = colDef(name = "PLZ", width = 120, align = "left"),
                units = colDef(name = "Einheiten", format = colFormat(separators = TRUE),
                               align = "right"),
                mw    = colDef(name = "MW", format = colFormat(separators = TRUE, digits = 1),
                               align = "right")
              ))
  })
}

shinyApp(ui, server)
