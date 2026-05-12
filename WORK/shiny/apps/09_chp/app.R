# 09_chp :: Combined Heat and Power (KWK-Anlagen)

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable)
})
source("../../R/mastr_data.R"); source("../../R/ui_helpers.R")

ui <- mastr_page(
  title = "KWK — Kraft-Wärme-Kopplung",
  subtitle = "Elektrische und thermische Nutzleistung der KWK-Anlagen.",
  fluid = TRUE,

  layout_column_wrap(1/3,
    uiOutput("kpi_n"), uiOutput("kpi_el"), uiOutput("kpi_th")),

  layout_column_wrap(1/2, heights_equal = "row",
    card(card_header("Elektrisch vs. Thermisch"),
         plotlyOutput("plot_scatter", height = "420px")),
    card(card_header("Anlagengröße (El. Leistung)"),
         plotlyOutput("plot_hist", height = "420px"))
  ),

  card(card_header("KWK-Anlagen nach Größe"),
       reactableOutput("table"))
)

server <- function(input, output, session) {
  df <- reactive(mastr_query("
    SELECT KwkMastrNummer AS mastr_nr,
           TRY_CAST(ElektrischeKwkLeistung AS DOUBLE) AS el_kw,
           TRY_CAST(ThermischeNutzleistung AS DOUBLE) AS th_kw,
           AusschliesslicheVerwendungBrennstoffe AS brennstoff
    FROM kwk"))

  output$kpi_n  <- renderUI(mastr_kpi("Anlagen", fmt_num(nrow(df()))))
  output$kpi_el <- renderUI(mastr_kpi("Elektrisch", fmt_num(sum(df()$el_kw, na.rm=TRUE)/1000, 0, " MW")))
  output$kpi_th <- renderUI(mastr_kpi("Thermisch", fmt_num(sum(df()$th_kw, na.rm=TRUE)/1000, 0, " MW")))

  output$plot_scatter <- renderPlotly({
    d <- df()[df()$el_kw > 0 & df()$th_kw > 0, ]
    plot_ly(d, x = ~el_kw, y = ~th_kw, type = "scatter", mode = "markers",
            marker = list(opacity = 0.35, color = MASTR_PALETTE$accent)) |>
      layout(xaxis = list(title = "El. Leistung [kW]", type = "log"),
             yaxis = list(title = "Th. Leistung [kW]", type = "log"))
  })

  output$plot_hist <- renderPlotly({
    d <- df()[!is.na(df()$el_kw) & df()$el_kw > 0, ]
    plot_ly(d, x = ~el_kw, type = "histogram", nbinsx = 60,
            marker = list(color = MASTR_PALETTE$accent)) |>
      layout(xaxis = list(title = "El. Leistung [kW]", type = "log"),
             yaxis = list(title = "Anlagen"))
  })

  output$table <- renderReactable({
    d <- df()[order(-df()$el_kw, na.last = TRUE), ][1:50, ]
    reactable(d, compact = TRUE, striped = TRUE, defaultPageSize = 10, searchable = TRUE)
  })
}
shinyApp(ui, server)
