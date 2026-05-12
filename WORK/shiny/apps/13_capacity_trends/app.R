# 13_capacity_trends :: cumulative + monthly capacity build-out

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(dplyr)
})
source("../../R/mastr_data.R"); source("../../R/ui_helpers.R")

ui <- mastr_page(
  title = "Zubau-Trends",
  subtitle = "Monatlicher und kumulierter Ausbau nach Energieträger.",
  layout_sidebar(
    sidebar = sidebar(width = 260,
      selectInput("tech", "Energieträger", choices = NULL, multiple = TRUE,
                  selected = c("SolareStrahlungsenergie","Wind","Biomasse")),
      sliderInput("yr", "Jahre", min = 1990, max = as.integer(format(Sys.Date(), "%Y")),
                  value = c(2000, as.integer(format(Sys.Date(), "%Y"))), sep = ""),
      radioButtons("mode", "Ansicht",
                   choices = c("Monat" = "m", "Kumuliert" = "c"), selected = "c")
    ),
    layout_column_wrap(1/2, heights_equal = "row",
      card(card_header("Entwicklung"), plotlyOutput("plot_trend", height = "460px")),
      card(card_header("Share pro Jahr"), plotlyOutput("plot_share", height = "460px"))
    )
  )
)

server <- function(input, output, session) {
  observe({ updateSelectInput(session, "tech", choices = mastr_energietraeger()) })

  d_monthly <- reactive({
    parts <- c(sprintf("EXTRACT(YEAR FROM month) BETWEEN %d AND %d",
                       input$yr[1], input$yr[2]))
    if (length(input$tech))
      parts <- c(parts, sprintf("energietraeger IN (%s)", mastr_sql_in(input$tech)))
    mastr_query(sprintf("
      SELECT month, energietraeger,
             new_capacity_mw,
             SUM(new_capacity_mw) OVER (PARTITION BY energietraeger ORDER BY month) AS cum_mw
      FROM agg_buildout_monthly
      WHERE %s", paste(parts, collapse = " AND ")))
  })

  output$plot_trend <- renderPlotly({
    d <- d_monthly()
    y <- if (input$mode == "c") d$cum_mw else d$new_capacity_mw
    ylab <- if (input$mode == "c") "Kumuliert [MW]" else "Zubau [MW]"
    plot_ly(d, x = ~month, y = y, color = ~energietraeger,
            type = "scatter", mode = "lines", stackgroup = "one") |>
      layout(xaxis = list(title = ""), yaxis = list(title = ylab),
             legend = list(orientation = "h", y = -0.2))
  })

  output$plot_share <- renderPlotly({
    d <- mastr_query(sprintf("
      SELECT year, energietraeger, ee_gw, total_gw
      FROM agg_ee_quote_by_year WHERE year BETWEEN %d AND %d",
      input$yr[1], input$yr[2]))
    # agg_ee_quote_by_year is one-row-per-year (total vs ee). For stacked view we
    # instead query the view by energietraeger:
    d2 <- mastr_query(sprintf("
      SELECT EXTRACT(YEAR FROM month) AS year, energietraeger,
             SUM(new_capacity_mw) AS mw
      FROM agg_buildout_monthly
      WHERE EXTRACT(YEAR FROM month) BETWEEN %d AND %d
      GROUP BY 1, 2", input$yr[1], input$yr[2]))
    plot_ly(d2, x = ~year, y = ~mw, color = ~energietraeger, type = "bar") |>
      layout(barmode = "stack", yaxis = list(title = "Zubau [MW]"))
  })
}
shinyApp(ui, server)
