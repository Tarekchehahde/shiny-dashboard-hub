# 04_wind_offshore :: offshore wind parks (Nord- und Ostsee)

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(leaflet); library(dplyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")

ui <- mastr_page(
  title = "Wind — Offshore",
  subtitle = "Offshore-Windparks in Nord- und Ostsee.",
  fluid = TRUE,

  layout_column_wrap(1/3,
    uiOutput("kpi_turbines"), uiOutput("kpi_capacity"), uiOutput("kpi_parks")),

  layout_column_wrap(1/2, heights_equal = "row",
    card(card_header("Wassertiefe vs. Entfernung zur Küste"),
         plotlyOutput("plot_depth", height = "420px")),
    card(card_header("Leistung pro Turbine über die Zeit"),
         plotlyOutput("plot_rating", height = "420px"))
  ),

  card(card_header("Karte der Offshore-Anlagen"),
       leafletOutput("map", height = "520px"))
)

server <- function(input, output, session) {
  df <- reactive({
    mastr_query("
      SELECT EinheitMastrNummer AS mastr_nr,
             TRY_CAST(Bruttoleistung AS DOUBLE) AS kw,
             TRY_CAST(Laengengrad AS DOUBLE) AS lon,
             TRY_CAST(Breitengrad AS DOUBLE) AS lat,
             TRY_CAST(Wassertiefe AS DOUBLE) AS wassertiefe,
             TRY_CAST(KuestenEntfernung AS DOUBLE) AS kuestenentfernung,
             TRY_CAST(Inbetriebnahmedatum AS DATE) AS inbetrieb,
             NameWindpark,
             Seelage
      FROM wind
      WHERE Lage = 'WindAufSee' OR Seelage IS NOT NULL")
  })

  output$kpi_turbines <- renderUI(mastr_kpi("Turbinen", fmt_num(nrow(df()))))
  output$kpi_capacity <- renderUI(mastr_kpi("Leistung",
                                            fmt_num(sum(df()$kw, na.rm=TRUE)/1000, 0, " MW")))
  output$kpi_parks <- renderUI({
    n <- length(unique(df()$NameWindpark))
    mastr_kpi("Windparks", fmt_num(n))
  })

  output$plot_depth <- renderPlotly({
    d <- df() %>% filter(!is.na(wassertiefe), !is.na(kuestenentfernung))
    plot_ly(d, x = ~kuestenentfernung, y = ~wassertiefe,
            size = ~kw, color = ~Seelage,
            type = "scatter", mode = "markers",
            marker = list(opacity = 0.6, sizemode = "area", sizeref = 500)) |>
      layout(xaxis = list(title = "Entfernung zur Küste [km]"),
             yaxis = list(title = "Wassertiefe [m]", autorange = "reversed"))
  })

  output$plot_rating <- renderPlotly({
    d <- df() %>% filter(!is.na(inbetrieb))
    plot_ly(d, x = ~inbetrieb, y = ~kw/1000, color = ~Seelage,
            type = "scatter", mode = "markers", marker = list(opacity = 0.6)) |>
      layout(xaxis = list(title = "Inbetriebnahme"),
             yaxis = list(title = "MW pro Turbine"))
  })

  output$map <- renderLeaflet({
    d <- df() %>% filter(!is.na(lat), !is.na(lon))
    leaflet(d) |>
      addProviderTiles("CartoDB.Positron") |>
      setView(lng = 7, lat = 54.5, zoom = 6) |>
      addCircleMarkers(
        ~lon, ~lat,
        radius = ~sqrt(pmax(kw, 1))/30,
        color = MASTR_PALETTE$wind,
        stroke = FALSE, fillOpacity = 0.6,
        popup = ~sprintf("<b>%s</b><br>%.1f MW<br>%s",
                         mastr_nr %||% "", kw/1000, NameWindpark %||% "")
      )
  })
}

`%||%` <- function(a, b) if (is.null(a) || is.na(a)) b else a
shinyApp(ui, server)
