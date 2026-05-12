# 15_ee_quote :: Erneuerbare-Energien-Anteil pro Jahr & Bundesland

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(dplyr)
})
source("../../R/mastr_data.R"); source("../../R/ui_helpers.R")

EE <- c("SolareStrahlungsenergie","Wind","Biomasse","Wasser","GeothermieGrubenKlaerschlamm")

ui <- mastr_page(
  title = "EE-Quote",
  subtitle = "Anteil erneuerbarer Leistung am Gesamtzubau — Zeitreihe und Bundesland-Ranking.",
  layout_sidebar(
    sidebar = sidebar(width = 260,
      sliderInput("yr", "Jahre", min = 1990, max = as.integer(format(Sys.Date(), "%Y")),
                  value = c(2000, as.integer(format(Sys.Date(), "%Y"))), sep = "")
    ),
    layout_column_wrap(1/2, heights_equal = "row",
      card(card_header("EE-Anteil pro Jahr"),
           plotlyOutput("plot_year", height = "460px")),
      card(card_header("EE-Anteil pro Bundesland"),
           plotlyOutput("plot_state", height = "460px"))
    )
  )
)

server <- function(input, output, session) {
  output$plot_year <- renderPlotly({
    d <- mastr_query(sprintf("
      SELECT year,
             ee_gw,
             total_gw,
             (ee_gw/NULLIF(total_gw,0))*100 AS ee_share_pct
      FROM agg_ee_quote_by_year
      WHERE year BETWEEN %d AND %d", input$yr[1], input$yr[2]))
    plot_ly(d, x = ~year, y = ~ee_share_pct, type = "scatter", mode = "lines+markers",
            line = list(color = MASTR_PALETTE$accent, width = 3)) |>
      layout(yaxis = list(title = "EE-Anteil am Zubau [%]", range = c(0, 100)),
             xaxis = list(title = ""))
  })

  output$plot_state <- renderPlotly({
    d <- mastr_query(sprintf("
      SELECT bundesland_name,
             SUM(CASE WHEN energietraeger IN ('%s') THEN bruttoleistung_mw ELSE 0 END) AS ee_mw,
             SUM(bruttoleistung_mw) AS total_mw
      FROM agg_capacity_by_state
      GROUP BY 1",
      paste(EE, collapse = "','")))
    d$share <- d$ee_mw / d$total_mw * 100
    plot_ly(d, x = ~share, y = ~reorder(bundesland_name, share),
            type = "bar", orientation = "h",
            marker = list(color = MASTR_PALETTE$accent)) |>
      layout(xaxis = list(title = "EE-Anteil [%]"), yaxis = list(title = ""))
  })
}
shinyApp(ui, server)
