# 12_geo_map :: Germany-wide map of MaStR units clustered by PLZ

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(leaflet); library(dplyr)
})
source("../../R/mastr_data.R"); source("../../R/ui_helpers.R")

ui <- mastr_page(
  title = "Geo-Karte",
  subtitle = "Postleitzahlen-geclusterte Karte aller Einheiten (Top 5000).",
  fluid = TRUE,
  layout_sidebar(
    sidebar = sidebar(
      title = "Filter", width = 260,
      selectInput("tech", "Energieträger", choices = NULL, multiple = TRUE),
      sliderInput("min_mw", "Min. Leistung pro PLZ [MW]", min = 0, max = 200,
                  value = 0, step = 1),
      helpText("Daten werden als vorberechnete Aggregation geliefert — optimiert für schnelle Darstellung.")
    ),
    leafletOutput("map", height = "760px")
  )
)

server <- function(input, output, session) {
  choices <- reactive(mastr_energietraeger())
  observe({ updateSelectInput(session, "tech", choices = choices()) })

  df <- reactive({
    sql <- sprintf("
      SELECT plz, energietraeger, units, bruttoleistung_mw AS mw, lat, lon
      FROM agg_capacity_by_plz_top5000
      WHERE bruttoleistung_mw >= %f", input$min_mw)
    if (length(input$tech))
      sql <- paste0(sql, sprintf(" AND energietraeger IN (%s)", mastr_sql_in(input$tech)))
    mastr_query(sql)
  })

  output$map <- renderLeaflet({
    d <- df() %>% filter(!is.na(lat), !is.na(lon))
    pal <- colorFactor("viridis", domain = d$energietraeger)
    leaflet(d) |>
      addProviderTiles("CartoDB.Positron") |>
      setView(lng = 10.4, lat = 51.2, zoom = 6) |>
      addCircleMarkers(
        ~lon, ~lat,
        radius = ~pmax(3, sqrt(mw) * 1.2),
        color = ~pal(energietraeger),
        stroke = FALSE, fillOpacity = 0.7,
        popup = ~sprintf("<b>PLZ %s</b><br>%s<br>%.1f MW · %d Einheiten",
                         plz, energietraeger, mw, units)) |>
      addLegend("bottomright", pal = pal, values = ~energietraeger, opacity = 0.8)
  })
}
shinyApp(ui, server)
