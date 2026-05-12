# 10_grid_operators :: Netzbetreiber und Netzanschlusspunkte

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable)
})
source("../../R/mastr_data.R"); source("../../R/ui_helpers.R")

ui <- mastr_page(
  title = "Netzbetreiber",
  subtitle = "Netzanschlusspunkte je Betreiber und Spannungsebene.",
  fluid = TRUE,

  layout_column_wrap(1/3,
    uiOutput("kpi_ops"), uiOutput("kpi_conn"), uiOutput("kpi_voltage_levels")),

  layout_column_wrap(1/2, heights_equal = "row",
    card(card_header("Top-20 Netzbetreiber nach Anschlusspunkten"),
         plotlyOutput("plot_top", height = "440px")),
    card(card_header("Verteilung Spannungsebenen"),
         plotlyOutput("plot_voltage", height = "440px"))
  ),

  card(card_header("Netzanschlusspunkte (Stichprobe)"),
       reactableOutput("table"))
)

server <- function(input, output, session) {
  ops <- reactive(mastr_query("
    SELECT MastrNummer, Firmenname, MarktakteurHauptTyp
    FROM marktakteure
    WHERE MarktakteurHauptTyp IN ('Netzbetreiber','Uebertragungsnetzbetreiber')"))

  conn <- reactive(mastr_query("
    SELECT Netzbetreiber, Spannungsebene, COUNT(*) AS n
    FROM netzanschlusspunkte
    GROUP BY 1, 2"))

  output$kpi_ops <- renderUI(mastr_kpi("Netzbetreiber", fmt_num(nrow(ops()))))
  output$kpi_conn <- renderUI({
    total <- sum(conn()$n)
    mastr_kpi("Anschlusspunkte", fmt_num(total))
  })
  output$kpi_voltage_levels <- renderUI({
    mastr_kpi("Spannungsebenen", length(unique(na.omit(conn()$Spannungsebene))))
  })

  output$plot_top <- renderPlotly({
    d <- aggregate(n ~ Netzbetreiber, data = conn(), sum)
    d <- d[order(-d$n), ][1:20, ]
    plot_ly(d, x = ~n, y = ~reorder(Netzbetreiber, n), type = "bar",
            orientation = "h",
            marker = list(color = MASTR_PALETTE$primary)) |>
      layout(yaxis = list(title = ""), xaxis = list(title = "Anschlusspunkte"))
  })

  output$plot_voltage <- renderPlotly({
    d <- aggregate(n ~ Spannungsebene, data = conn(), sum)
    plot_ly(d, labels = ~Spannungsebene, values = ~n, type = "pie", hole = 0.4)
  })

  output$table <- renderReactable({
    d <- mastr_query("
      SELECT NetzanschlusspunktMastrNummer AS mastr_nr,
             Netzbetreiber, Spannungsebene, Bundesland, Gemeinde
      FROM netzanschlusspunkte LIMIT 1000")
    reactable(d, compact = TRUE, striped = TRUE, defaultPageSize = 15, searchable = TRUE)
  })
}
shinyApp(ui, server)
