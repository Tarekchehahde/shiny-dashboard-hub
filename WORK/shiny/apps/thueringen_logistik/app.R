# =============================================================================
# thueringen_logistik — Logistik & Standort (Demo-CSV + MaStR C&I-Solar).
# erwicon connect 2026 · Demo 4/7.
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

source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")
source("../../R/thueringen_helpers.R")

LOGISTIK_RAW <- thueringen_demo_csv("logistik_demo.csv")
KREIS_META <- thueringen_kreis_meta()

# Approximate Autobahn segments through Thüringen (lat, lon).
HIGHWAY_CORRIDORS <- list(
  A4 = matrix(c(
    50.98, 10.32,
    50.98, 11.03,
    50.93, 11.59,
    50.88, 12.08
  ), ncol = 2, byrow = TRUE),
  A9 = matrix(c(
    50.35, 11.85,
    50.65, 11.65,
    50.98, 11.75,
    51.45, 11.95
  ), ncol = 2, byrow = TRUE),
  A38 = matrix(c(
    51.35, 10.45,
    51.05, 11.05,
    50.85, 11.55,
    50.65, 12.05
  ), ncol = 2, byrow = TRUE)
)

ui <- mastr_page(
  title = "Th\u00fcringen Logistik & Standort",
  subtitle = "Logistik-Index, Pendler & Gewerbe-PV (C&I) nach Kreis.",
  fluid = TRUE,
  primary = ERWICON_PRIMARY,
  footer = "thueringen",
  hub_back_label = "\u2190 Zur\u00fcck zum Hub",
  creator_qr_lang = "de",
  erwicon_banner_ui(
    "\u201eStandort vs. Personal vs. Energie \u2014 was wiegt bei Ihnen am meisten?\u201c",
    " A4 / A9 / A38 als Referenzkorridore \u2014 Demo-Standortdaten + MaStR Hallendach-PV."
  ),
  tags$style(HTML(".kreis-map { border-radius: 8px; min-height: 420px; }")),
  layout_sidebar(
    sidebar = sidebar(
      width = 280,
      title = "Filter",
      checkboxInput("only_active", "Nur aktive MaStR-Einheiten", TRUE),
      checkboxInput("show_highways", "Autobahn-Korridore (A4/A9/A38)", TRUE),
      hr(),
      uiOutput("load_status"),
      tags$p(
        class = "small text-muted mb-0",
        "Logistik: Demo-CSV. Solar: MaStR C&amp;I (10 kW\u2013&lt;1 MW), BL 1415."
      )
    ),
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      mastr_kpi(
        "Erfurt Index",
        textOutput("kpi_erfurt_idx", inline = TRUE),
        subtitle = "Logistik-Index (Demo)",
        color = "primary"
      ),
      mastr_kpi(
        "Bester Kreis",
        textOutput("kpi_best", inline = TRUE),
        subtitle = "H\u00f6chster Logistik-Index",
        color = "success"
      ),
      mastr_kpi(
        "\u00d8 Pendler",
        textOutput("kpi_pendler", inline = TRUE),
        subtitle = "Antwort \u201ePendler\u201c (Demo %)",
        color = "warning"
      ),
      mastr_kpi(
        "C&I-Solar",
        textOutput("kpi_solar_mw", inline = TRUE),
        subtitle = "MW installiert (MaStR)",
        color = "info"
      )
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        full_screen = TRUE,
        card_header("Logistik-Index vs. Gewerbe-PV (MW)"),
        card_body(plotOutput("plot_scatter", height = "360px"))
      ),
      card(
        full_screen = TRUE,
        card_header("Kreis-Tabelle"),
        card_body(reactableOutput("tbl_kreise", height = "360px"))
      )
    ),
    card(
      full_screen = TRUE,
      card_header("Karte \u2014 Logistik-Index & Autobahn-Korridore"),
      card_body(
        padding = 0,
        div(class = "kreis-map", leafletOutput("map_logistik", height = "420px"))
      )
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  data_loading <- reactiveVal(TRUE)
  data_err <- reactiveVal(NULL)
  merged_data <- reactiveVal(NULL)

  load_all <- function() {
    data_loading(TRUE)
    data_err(NULL)
    active <- sql_active_mastr(input$only_active)
    out <- tryCatch({
      withProgress(message = "Lade Daten\u2026", value = 0, {
        incProgress(0.4, detail = "MaStR C&I-Solar")
        solar_plz <- mastr_query(sprintf("
          SELECT LPAD(CAST(Postleitzahl AS VARCHAR), 5, '0') AS plz,
            COUNT(*) AS units, SUM(Bruttoleistung) / 1000.0 AS mw
          FROM solar
          WHERE Bundesland = '1415'
            AND Bruttoleistung >= 10
            AND Bruttoleistung < 1000
            AND Postleitzahl IS NOT NULL %s
          GROUP BY 1", active))
        solar_k <- kreis_from_plz(solar_plz)
        incProgress(1, detail = "Merge")
        LOGISTIK_RAW |>
          left_join(
            solar_k |> select(kreis, solar_mw = mw, solar_units = units),
            by = "kreis"
          ) |>
          left_join(KREIS_META, by = "kreis") |>
          mutate(
            solar_mw = coalesce(solar_mw, 0),
            solar_units = coalesce(solar_units, 0L)
          )
      })
    }, error = function(e) {
      data_err(conditionMessage(e))
      NULL
    })
    merged_data(out)
    data_loading(FALSE)
  }

  observeEvent(input$only_active, load_all(), ignoreInit = FALSE)

  output$load_status <- renderUI({
    if (isTRUE(data_loading())) {
      return(tags$span(class = "text-muted small", "Lade Daten \u2026"))
    }
    err <- data_err()
    if (!is.null(err)) {
      return(tags$span(class = "text-danger small", "Fehler: ", err))
    }
    tag <- tryCatch(mastr_release_info()$tag, error = function(e) "?")
    tags$span(class = "text-muted small", "MaStR: ", tags$code(tag))
  })

  output$kpi_erfurt_idx <- renderText({
    if (isTRUE(data_loading()) || is.null(merged_data())) return("\u2026")
    row <- merged_data()[grepl("^Erfurt", merged_data()$kreis), , drop = FALSE]
    if (!nrow(row)) "\u2013" else as.character(row$logistik_index[1])
  })

  output$kpi_best <- renderText({
    if (isTRUE(data_loading()) || is.null(merged_data())) return("\u2026")
    d <- merged_data()
    if (!nrow(d)) return("\u2013")
    top <- d[which.max(d$logistik_index), , drop = FALSE]
    paste0(top$kreis[1], " \u00b7 ", top$logistik_index[1])
  })

  output$kpi_pendler <- renderText({
    if (isTRUE(data_loading()) || is.null(merged_data())) return("\u2026")
    p <- mean(merged_data()$pendler_antwort_pct, na.rm = TRUE)
    if (is.na(p)) "\u2013" else paste0(fmt_num(p, 1), " %")
  })

  output$kpi_solar_mw <- renderText({
    if (isTRUE(data_loading()) || is.null(merged_data())) return("\u2026")
    mw <- sum(merged_data()$solar_mw, na.rm = TRUE)
    paste0(fmt_num(mw, 1), " MW")
  })

  output$plot_scatter <- renderPlot({
    if (isTRUE(data_loading()) || is.null(merged_data())) {
      return(mastr_empty_plot("Lade\u2026"))
    }
    d <- merged_data()
    if (!nrow(d)) {
      return(mastr_empty_plot("Keine Daten"))
    }
    ggplot(d, aes(logistik_index, solar_mw, label = kreis)) +
      geom_point(color = ERWICON_PRIMARY, size = 3, alpha = 0.85) +
      geom_smooth(method = "lm", se = FALSE, color = "#94a3b8", linewidth = 0.7, linetype = "dashed") +
      geom_text(check_overlap = TRUE, size = 2.5, hjust = -0.1, vjust = 0.5, color = "#374151") +
      scale_y_continuous(labels = label_number(decimal.mark = ",", big.mark = ".")) +
      labs(
        x = "Logistik-Index (Demo)",
        y = "C&I-Solar MW (MaStR)",
        caption = "Jeder Punkt = ein Kreis"
      ) +
      theme_minimal(base_size = 11)
  })

  output$tbl_kreise <- renderReactable({
    if (isTRUE(data_loading()) || is.null(merged_data())) {
      return(reactable(data.frame(Info = "Lade\u2026")))
    }
    d <- merged_data() |>
      arrange(desc(logistik_index)) |>
      transmute(
        Kreis = kreis,
        `Logistik-Index` = logistik_index,
        `Pendler %` = pendler_antwort_pct,
        `A4 km` = dist_a4_km,
        `A9 km` = dist_a9_km,
        `A38 km` = dist_a38_km,
        `Solar MW` = round(solar_mw, 1)
      )
    reactable(
      d,
      defaultPageSize = 12,
      compact = TRUE,
      highlight = TRUE,
      columns = list(
        `Logistik-Index` = colDef(format = colFormat(separators = TRUE, digits = 0)),
        `Pendler %` = colDef(format = colFormat(separators = TRUE, digits = 1)),
        `Solar MW` = colDef(format = colFormat(separators = TRUE, digits = 1))
      )
    )
  })

  output$map_logistik <- renderLeaflet({
    base <- leaflet() |>
      addProviderTiles("CartoDB.Positron") |>
      thueringen_set_view()

    if (isTRUE(input$show_highways)) {
      hw_cols <- c(A4 = "#2563eb", A9 = "#16a34a", A38 = "#9333ea")
      for (nm in names(HIGHWAY_CORRIDORS)) {
        coords <- HIGHWAY_CORRIDORS[[nm]]
        base <- base |>
          addPolylines(
            lng = coords[, 2],
            lat = coords[, 1],
            color = hw_cols[[nm]],
            weight = 4,
            opacity = 0.65,
            dashArray = "8, 6",
            label = nm
          )
      }
    }

    if (isTRUE(data_loading()) || is.null(merged_data())) {
      return(base |> addControl("Lade Kartendaten\u2026", position = "topright"))
    }

    d <- merged_data()
    d <- d[!is.na(d$lat) & !is.na(d$lon) & !is.na(d$logistik_index), , drop = FALSE]
    if (!nrow(d)) {
      return(base |> addControl("Keine Kreisdaten", position = "topright"))
    }

    pal <- colorNumeric("YlOrRd", d$logistik_index, na.color = "#94a3b8")
    base |>
      addCircleMarkers(
        data = d,
        lng = ~lon, lat = ~lat,
        radius = ~sqrt(logistik_index) * 0.35 + 6,
        stroke = TRUE, weight = 1, color = "#444",
        fillOpacity = 0.75, fillColor = ~pal(logistik_index),
        label = ~kreis_leaflet_labels(
          data.frame(kreis = kreis, val = logistik_index),
          "val", "%.0f", " Index"
        ),
        labelOptions = kreis_leaflet_label_opts()
      ) |>
      addLegend("bottomright", pal = pal, values = d$logistik_index, title = "Index")
  })
}

shinyApp(ui, server)
