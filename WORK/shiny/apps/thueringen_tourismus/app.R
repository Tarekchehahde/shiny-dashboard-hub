# =============================================================================
# thueringen_tourismus — Tourismus & Konsum nach Kreis (Demo-Daten).
# erwicon connect 2026 · Demo 5/7.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(ggplot2)
  library(leaflet)
  library(reactable)
  library(scales)
})

source("../../R/ui_helpers.R")
source("../../R/thueringen_helpers.R")

MONTH_ABBR <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

in_peak_season <- function(saison_peak, month = as.integer(format(Sys.Date(), "%m"))) {
  parts <- strsplit(saison_peak, "-", fixed = TRUE)[[1]]
  if (length(parts) != 2L) {
    return(FALSE)
  }
  start_m <- match(parts[1], MONTH_ABBR)
  end_m <- match(parts[2], MONTH_ABBR)
  if (is.na(start_m) || is.na(end_m)) {
    return(FALSE)
  }
  if (start_m <= end_m) {
    month >= start_m && month <= end_m
  } else {
    month >= start_m || month <= end_m
  }
}

TOURISMUS_RAW <- thueringen_demo_csv("tourismus_demo.csv")
KREIS_META <- thueringen_kreis_meta()

TOURISMUS <- TOURISMUS_RAW |>
  left_join(KREIS_META, by = "kreis") |>
  mutate(
    peak_now = vapply(saison_peak, in_peak_season, logical(1L))
  )

ui <- mastr_page(
  title = "Th\u00fcringen Tourismus & Konsum",
  subtitle = "Gastgewerbe-Snapshot nach Kreis \u2014 illustrative Demo-Daten.",
  fluid = TRUE,
  primary = ERWICON_PRIMARY,
  footer = "thueringen_demo",
  hub_back_label = "\u2190 Zur\u00fcck zum Hub",
  creator_qr_lang = "de",
  erwicon_banner_ui(
    "\u201eSaison 2026 \u2014 optimistischer oder vorsichtiger als 2025?\u201c",
    " \u00dcbernachtungen, Bettenkapazit\u00e4t und Saison-Peak im Kreisvergleich."
  ),
  tags$style(HTML(".kreis-map { border-radius: 8px; min-height: 420px; }")),
  layout_sidebar(
    sidebar = sidebar(
      width = 280,
      title = "Filter",
      checkboxInput("only_peak", "Nur Kreise in Peak-Saison (aktueller Monat)", FALSE),
      tags$p(
        class = "small text-muted mb-0",
        "Daten: Demo-CSV \u00b7 keine amtliche Statistik. ",
        format(Sys.Date(), "%d.%m.%Y")
      )
    ),
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      mastr_kpi(
        "\u00dcbernachtungen gesamt",
        textOutput("kpi_total", inline = TRUE),
        subtitle = "Tsd. (Demo 2025)",
        color = "primary"
      ),
      mastr_kpi(
        "Wartburgkreis",
        textOutput("kpi_wartburg", inline = TRUE),
        subtitle = "Tsd. \u00dcbernachtungen",
        color = "success"
      ),
      mastr_kpi(
        "Weimar, Stadt",
        textOutput("kpi_weimar", inline = TRUE),
        subtitle = "Tsd. \u00dcbernachtungen",
        color = "warning"
      ),
      mastr_kpi(
        "Peak-Saison jetzt",
        textOutput("kpi_peak_count", inline = TRUE),
        subtitle = "Kreise im Saison-Peak",
        color = "info"
      )
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        full_screen = TRUE,
        card_header("Top 8 \u2014 \u00dcbernachtungen (Tsd.)"),
        card_body(plotOutput("plot_top8", height = "360px"))
      ),
      card(
        full_screen = TRUE,
        card_header("Kreis-Tabelle"),
        card_body(reactableOutput("tbl_kreise", height = "360px"))
      )
    ),
    card(
      full_screen = TRUE,
      card_header("Karte \u2014 Tourismus-Index nach Kreis"),
      card_body(
        padding = 0,
        div(class = "kreis-map", leafletOutput("map_index", height = "420px"))
      )
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  filtered <- reactive({
    d <- TOURISMUS
    if (isTRUE(input$only_peak)) {
      d <- d[d$peak_now, , drop = FALSE]
    }
    d
  })

  output$kpi_total <- renderText({
    fmt_num(sum(TOURISMUS$uebernachtungen_tausend, na.rm = TRUE), 0)
  })

  output$kpi_wartburg <- renderText({
    row <- TOURISMUS[TOURISMUS$kreis == "Wartburgkreis", , drop = FALSE]
    if (!nrow(row)) "\u2013" else fmt_num(row$uebernachtungen_tausend[1], 0)
  })

  output$kpi_weimar <- renderText({
    row <- TOURISMUS[TOURISMUS$kreis == "Weimar, Stadt", , drop = FALSE]
    if (!nrow(row)) "\u2013" else fmt_num(row$uebernachtungen_tausend[1], 0)
  })

  output$kpi_peak_count <- renderText({
    fmt_num(sum(TOURISMUS$peak_now, na.rm = TRUE), 0)
  })

  output$plot_top8 <- renderPlot({
    d <- filtered() |>
      arrange(desc(uebernachtungen_tausend)) |>
      slice_head(n = 8) |>
      mutate(kreis = factor(kreis, levels = rev(kreis)))
    if (!nrow(d)) {
      return(mastr_empty_plot("Keine Daten"))
    }
    ggplot(d, aes(uebernachtungen_tausend, kreis, fill = tourismus_index)) +
      geom_col(show.legend = FALSE, width = 0.75) +
      scale_fill_gradient(low = "#fde68a", high = ERWICON_PRIMARY) +
      scale_x_continuous(labels = label_number(big.mark = ".", decimal.mark = ",")) +
      labs(x = "Tsd. \u00dcbernachtungen", y = NULL) +
      theme_minimal(base_size = 11) +
      theme(panel.grid.major.y = element_blank())
  })

  output$tbl_kreise <- renderReactable({
    d <- filtered() |>
      arrange(desc(uebernachtungen_tausend)) |>
      transmute(
        Kreis = kreis,
        Uebernachtungen_Tsd = uebernachtungen_tausend,
        Betten = betten,
        Index = tourismus_index,
        Saison_Peak = saison_peak,
        Peak_jetzt = ifelse(peak_now, "Ja", "Nein")
      )
    reactable(
      d,
      defaultPageSize = 12,
      compact = TRUE,
      highlight = TRUE,
      columns = list(
        Uebernachtungen_Tsd = colDef(
          name = "\u00dcbernachtungen (Tsd.)",
          format = colFormat(separators = TRUE, digits = 0)
        ),
        Betten = colDef(format = colFormat(separators = TRUE, digits = 0)),
        Index = colDef(format = colFormat(separators = TRUE, digits = 0))
      )
    )
  })

  output$map_index <- renderLeaflet({
    d <- filtered()
    if (!nrow(d) || !all(c("lat", "lon") %in% names(d))) {
      return(
        leaflet() |>
          addProviderTiles("CartoDB.Positron") |>
          thueringen_set_view() |>
          addControl("Keine Kartendaten", position = "topright")
      )
    }
    d <- d[!is.na(d$lat) & !is.na(d$lon), , drop = FALSE]
    if (!nrow(d)) {
      return(
        leaflet() |>
          addProviderTiles("CartoDB.Positron") |>
          thueringen_set_view() |>
          addControl("Keine Kartendaten", position = "topright")
      )
    }
    pal <- colorNumeric("YlOrRd", d$tourismus_index, na.color = "#94a3b8")
    leaflet(d) |>
      addProviderTiles("CartoDB.Positron") |>
      thueringen_set_view() |>
      addCircleMarkers(
        ~lon, ~lat,
        radius = ~sqrt(uebernachtungen_tausend) * 0.35 + 6,
        stroke = TRUE, weight = 1, color = "#444",
        fillOpacity = 0.75, fillColor = ~pal(tourismus_index),
        label = ~paste0(
          kreis, " \u00b7 Index ", tourismus_index,
          " \u00b7 ", format(uebernachtungen_tausend, big.mark = ".", decimal.mark = ","),
          " Tsd. \u00dcbern."
        ),
        labelOptions = kreis_leaflet_label_opts()
      ) |>
      addLegend("bottomright", pal = pal, values = ~tourismus_index, title = "Index")
  })
}

shinyApp(ui, server)
