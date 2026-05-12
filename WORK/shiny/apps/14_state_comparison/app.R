# 14_state_comparison :: Bundesländer-Liga und Pro-Kopf-Rang

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable); library(dplyr)
})
source("../../R/mastr_data.R"); source("../../R/ui_helpers.R")

# Bevölkerung (2024, Destatis Stand) — eingebettet, um offline zu funktionieren.
POP <- data.frame(
  bundesland_name = c(
    "Schleswig-Holstein","Hamburg","Niedersachsen","Bremen",
    "Nordrhein-Westfalen","Hessen","Rheinland-Pfalz","Baden-Württemberg",
    "Bayern","Saarland","Berlin","Brandenburg","Mecklenburg-Vorpommern",
    "Sachsen","Sachsen-Anhalt","Thüringen"),
  einwohner_mio = c(2.97, 1.89, 8.14, 0.68, 18.14, 6.39, 4.16, 11.34,
                   13.45, 0.99, 3.80, 2.60, 1.61, 4.00, 2.13, 2.10)
)

ui <- mastr_page(
  title = "Bundesländer-Vergleich",
  subtitle = "Installierte Leistung absolut und pro Kopf.",
  fluid = TRUE,
  layout_sidebar(
    sidebar = sidebar(width = 260,
      selectInput("tech", "Energieträger",
                  choices = NULL, multiple = FALSE,
                  selected = "SolareStrahlungsenergie"),
      radioButtons("metric", "Metrik",
                   choices = c("Absolut (MW)" = "abs", "Pro Kopf (W/EW)" = "pc"),
                   selected = "abs")
    ),

    card(card_header("Liga-Tabelle"), plotlyOutput("plot_league", height = "460px")),
    card(card_header("Details"), reactableOutput("table"))
  )
)

server <- function(input, output, session) {
  observe({ updateSelectInput(session, "tech", choices = mastr_energietraeger()) })

  df <- reactive({
    d <- mastr_query(sprintf("
      SELECT bundesland_name,
             SUM(bruttoleistung_kw)/1000 AS mw,
             COUNT(*) AS units
      FROM v_units_all
      WHERE energietraeger = '%s' AND bundesland_name IS NOT NULL
      GROUP BY 1", input$tech))
    d <- left_join(d, POP, by = "bundesland_name")
    d$watt_per_capita <- d$mw * 1000 / (d$einwohner_mio * 1e6) * 1e6  # W/Person
    d
  })

  output$plot_league <- renderPlotly({
    d <- df()
    d$value <- if (input$metric == "abs") d$mw else d$watt_per_capita
    ylab <- if (input$metric == "abs") "MW installiert" else "W pro Einwohner"
    plot_ly(d, x = ~value, y = ~reorder(bundesland_name, value),
            type = "bar", orientation = "h",
            marker = list(color = MASTR_PALETTE$primary)) |>
      layout(xaxis = list(title = ylab), yaxis = list(title = ""))
  })

  output$table <- renderReactable({
    d <- df()
    d$mw <- round(d$mw, 1)
    d$watt_per_capita <- round(d$watt_per_capita, 1)
    reactable(d, compact = TRUE, striped = TRUE, defaultPageSize = 16,
              columns = list(
                bundesland_name = colDef(name = "Bundesland"),
                mw             = colDef(name = "MW"),
                units          = colDef(name = "Einheiten"),
                einwohner_mio  = colDef(name = "Einwohner [Mio]"),
                watt_per_capita= colDef(name = "W / Einwohner")
              ))
  })
}
shinyApp(ui, server)
