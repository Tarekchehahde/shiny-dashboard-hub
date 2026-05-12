# 07_geothermal :: Geothermie / Solarthermie / Grubengas / Druckentspannung

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable); library(leaflet)
})
source("../../R/mastr_data.R"); source("../../R/ui_helpers.R")

ui <- mastr_page(
  title = "Geothermie & Sonstige",
  subtitle = "Tiefe Geothermie, Solarthermie, Grubengas, Klärgas, Druckentspannung.",
  fluid = TRUE,

  layout_column_wrap(1/3,
    uiOutput("kpi_n"), uiOutput("kpi_mw"), uiOutput("kpi_types")),

  layout_column_wrap(1/2, heights_equal = "row",
    card(card_header("Technologie-Mix"),
         plotlyOutput("plot_tech", height = "380px")),
    card(card_header("Standorte"),
         leafletOutput("map", height = "380px"))
  ),

  card(card_header("Alle Einheiten"), reactableOutput("table_all"))
)

server <- function(input, output, session) {
  df <- reactive(mastr_query("
    SELECT EinheitMastrNummer AS mastr_nr,
           TRY_CAST(Bruttoleistung AS DOUBLE) AS kw,
           TRY_CAST(Laengengrad AS DOUBLE) AS lon,
           TRY_CAST(Breitengrad AS DOUBLE) AS lat,
           Bundesland, Gemeinde, ArtDerAnlage
    FROM geothermie"))

  output$kpi_n  <- renderUI(mastr_kpi("Einheiten", fmt_num(nrow(df()))))
  output$kpi_mw <- renderUI(mastr_kpi("Leistung", fmt_num(sum(df()$kw, na.rm=TRUE)/1000, 1, " MW")))
  output$kpi_types <- renderUI(mastr_kpi("Technologien",
                                          length(unique(na.omit(df()$ArtDerAnlage)))))

  output$plot_tech <- renderPlotly({
    d <- as.data.frame(table(ArtDerAnlage = df()$ArtDerAnlage))
    plot_ly(d, labels = ~ArtDerAnlage, values = ~Freq, type = "pie", hole = 0.4)
  })

  output$map <- renderLeaflet({
    d <- df()[!is.na(df()$lat) & !is.na(df()$lon), ]
    leaflet(d) |>
      addProviderTiles("CartoDB.Positron") |>
      addCircleMarkers(~lon, ~lat, radius = 5, color = MASTR_PALETTE$geo,
                       fillOpacity = 0.7, stroke = FALSE,
                       popup = ~sprintf("%s<br>%.0f kW", ArtDerAnlage, kw))
  })

  output$table_all <- renderReactable({
    reactable(df(), compact = TRUE, striped = TRUE, searchable = TRUE,
              defaultPageSize = 10)
  })
}
shinyApp(ui, server)
