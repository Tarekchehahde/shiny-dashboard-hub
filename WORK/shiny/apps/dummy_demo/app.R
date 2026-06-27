# =============================================================================
# dummy_demo — placeholder dashboard for hub routing tests.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(ggplot2)
  library(dplyr)
})

source("../../R/ui_helpers.R")

set.seed(42)
dummy_df <- tibble(
  month = factor(month.abb, levels = month.abb),
  series_a = cumsum(rnorm(12, 8, 3)),
  series_b = cumsum(rnorm(12, 5, 2))
)

ui <- mastr_page(
  title = "Demo Dashboard",
  subtitle = "Dummy KPIs and charts — replace with a real app when ready.",
  fluid = TRUE,
  footer = "demo",
  layout_sidebar(
    sidebar = sidebar(
      title = "Filters",
      sliderInput("scale", "Scale factor", min = 0.5, max = 2, value = 1, step = 0.1),
      checkboxInput("show_b", "Show series B", TRUE)
    ),
    layout_column_wrap(
      width = 1/3,
      value_box(
        title = "Total A (YTD)",
        value = textOutput("kpi_a", inline = TRUE)
      ),
      value_box(
        title = "Total B (YTD)",
        value = textOutput("kpi_b", inline = TRUE)
      ),
      value_box(
        title = "A / B ratio",
        value = textOutput("kpi_ratio", inline = TRUE)
      )
    ),
    card(
      card_header("Monthly trend (dummy data)"),
      plotOutput("trend", height = "360px")
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  scaled <- reactive({
    df <- dummy_df
    df$series_a <- df$series_a * input$scale
    df$series_b <- df$series_b * input$scale
    df
  })

  output$kpi_a <- renderText({
    format(round(sum(scaled()$series_a)), big.mark = ".")
  })
  output$kpi_b <- renderText({
    format(round(sum(scaled()$series_b)), big.mark = ".")
  })
  output$kpi_ratio <- renderText({
    b <- sum(scaled()$series_b)
    if (b <= 0) return("—")
    sprintf("%.2f", sum(scaled()$series_a) / b)
  })

  output$trend <- renderPlot({
    df <- scaled()
    p <- ggplot(df, aes(x = month, y = series_a, group = 1, colour = "Series A")) +
      geom_line(linewidth = 1.1) +
      geom_point(size = 2.5) +
      labs(x = NULL, y = "MW (dummy)", colour = NULL) +
      theme_minimal(base_size = 13)
    if (isTRUE(input$show_b)) {
      p <- p +
        geom_line(aes(y = series_b, colour = "Series B"), linewidth = 1.1) +
        geom_point(aes(y = series_b, colour = "Series B"), size = 2.5)
    }
    print(p)
  })
}

shinyApp(ui, server)
