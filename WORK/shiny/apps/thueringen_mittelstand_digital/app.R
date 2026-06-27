# =============================================================================
# thueringen_mittelstand_digital — Mittelstand-Digitalisierung & Demo-Katalog.
# erwicon connect 2026 · Demo 7/7. No heavy data load — hub showcase + KPI mock.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(htmltools)
  library(plotly)
  library(dplyr)
  library(tibble)
})

source("../../R/ui_helpers.R")
source("../../R/thueringen_helpers.R")

`%||%` <- function(x, y) if (is.null(x)) y else x

.app_href <- function(id) {
  if (identical(Sys.getenv("MASTR_HUB_MODE", "ports"), "ports")) {
    ports <- c(
      thueringen_gewerbe_strom = 3847L,
      thueringen_waermepumpe_gebaeude = 3848L,
      thueringen_fachkraefte = 3849L,
      thueringen_logistik = 3850L,
      thueringen_tourismus = 3851L,
      thueringen_kommunal = 3852L
    )
    port <- ports[[id]]
    if (is.null(port)) sprintf("/%s/", id) else sprintf("http://localhost:%s/", port)
  } else {
    sprintf("/%s/", id)
  }
}

ERWICON_DEMOS_HIDDEN <- c("thueringen_fachkraefte")

ERWICON_DEMOS <- list(
  list(
    id = "thueringen_gewerbe_strom",
    n = 1L,
    title = "Th\u00fcringen Gewerbe-Strom",
    pitch = "Strompreis live + Gewerbe-PV & Speicher \u2014 Gespr\u00e4chsstarter f\u00fcr Energiekosten."
  ),
  list(
    id = "thueringen_waermepumpe_gebaeude",
    n = 2L,
    title = "W\u00e4rmepumpen & Geb\u00e4ude-Energie",
    pitch = "Geb\u00e4ude-Energie-Proxy nach Kreis: Speicher, Home-PV, Biomasse."
  ),
  list(
    id = "thueringen_fachkraefte",
    n = 3L,
    title = "Regionalwirtschaft & Standort",
    pitch = "Wirtschaftsdynamik nach Kreis \u2014 Besch\u00e4ftigung & Nachfrageindikatoren (BA).",
    published = FALSE
  ),
  list(
    id = "thueringen_logistik",
    n = 4L,
    title = "Logistik & Standort",
    pitch = "Logistik-Index vs. C&I-Solar \u2014 Standort, Pendler, Energie im Blick."
  ),
  list(
    id = "thueringen_tourismus",
    n = 5L,
    title = "Tourismus & Konsum",
    pitch = "\u00dcbernachtungen, Bettenkapazit\u00e4t und Saison-Peak pro Kreis."
  ),
  list(
    id = "thueringen_kommunal",
    n = 6L,
    title = "Kommunal & Infrastruktur",
    pitch = "Gro\u00dfsolar ab 100 kW, Speicher und Wind \u2014 MaStR nach Kreis."
  )
)

erwicon_demos_visible <- function() {
  Filter(function(d) {
    isTRUE(d$published %||% TRUE) && !(d$id %in% ERWICON_DEMOS_HIDDEN)
  }, ERWICON_DEMOS)
}

demo_card <- function(d) {
  card(
    class = "h-100",
    card_header(d$title),
    p(class = "text-muted mb-3", d$pitch),
    tags$a(
      class = "btn btn-sm",
      style = "background:#6B1D3A; color:#fff;",
      href = .app_href(d$id),
      target = "_self",
      "Öffnen"
    )
  )
}

WEEKS <- tibble(
  week = 1:12,
  excel_delay = c(5.2, 4.8, 4.5, 4.1, 3.9, 3.6, 3.4, 3.2, 3.0, 2.8, 2.6, 2.4),
  live_dashboard = c(0.3, 0.2, 0.2, 0.1, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
)

ui <- mastr_page(
  title = "Th\u00fcringen Mittelstand-Digitalisierung",
  subtitle = "Live-Dashboard statt Excel-Export \u2014 Demo-Katalog & KPI-Tracker.",
  fluid = TRUE,
  primary = ERWICON_PRIMARY,
  footer = "thueringen_demo",
  hub_back_label = "\u2190 Zur\u00fcck zum Hub",
  creator_qr_lang = "de",
  erwicon_banner_ui(
    "\u201eWelche Zahl schauen Sie jede Woche \u2014 und wo kommt sie her?\u201c",
    " Ein Hub, f\u00fcnf Fach-Demos \u2014 plus illustrativer Wochen-KPI-Tracker."
  ),
  tags$style(HTML("
    .demo-grid .card { border-color: #e5e7eb; }
    .illustrativ-note { font-size: 0.78rem; color: #6b7280; }
  ")),
  h4(class = "mb-3", "Th\u00fcringen \u2014 Demo-Katalog"),
  div(
    class = "demo-grid",
    layout_column_wrap(
      width = 1/3,
      gap = "1rem",
      !!!lapply(erwicon_demos_visible(), demo_card)
    )
  ),
  hr(),
  h4(class = "mb-2", "Wochen-KPI-Tracker"),
  p(class = "illustrativ-note mb-3", "illustrativ \u2014 keine Live-Anbindung"),
  layout_columns(
    col_widths = c(3, 3, 3, 3),
    mastr_kpi(
      "Auftr\u00e4ge (Woche)",
      tags$span(class = "mastr-kpi", "142"),
      subtitle = "illustrativ",
      color = "primary"
    ),
    mastr_kpi(
      "Energiekosten (EUR)",
      tags$span(class = "mastr-kpi", "18.420"),
      subtitle = "illustrativ",
      color = "warning"
    ),
    mastr_kpi(
      "Fuhrpark (km)",
      tags$span(class = "mastr-kpi", "4.860"),
      subtitle = "illustrativ",
      color = "success"
    ),
    mastr_kpi(
      "Offene Tickets",
      tags$span(class = "mastr-kpi", "23"),
      subtitle = "illustrativ",
      color = "danger"
    )
  ),
  card(
    full_screen = TRUE,
    class = "mt-3",
    card_header("Datenfrische \u2014 Excel-Export vs. Live-Dashboard (illustrativ)"),
    card_body(
      plotlyOutput("plot_freshness", height = "320px"),
      p(class = "illustrativ-note mb-0 mt-2",
        "Verz\u00f6gerung in Tagen bis KPIs im Reporting verf\u00fcgbar sind \u2014 Demo-Verlauf \u00fcber 12 Wochen.")
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  output$plot_freshness <- renderPlotly({
    plot_ly(WEEKS, x = ~week, type = "scatter", mode = "lines+markers") |>
      add_trace(
        y = ~excel_delay,
        name = "Excel-Export",
        line = list(color = "#94a3b8", width = 2),
        marker = list(color = "#94a3b8", size = 6)
      ) |>
      add_trace(
        y = ~live_dashboard,
        name = "Live-Dashboard",
        line = list(color = ERWICON_PRIMARY, width = 2.5),
        marker = list(color = ERWICON_PRIMARY, size = 6)
      ) |>
      layout(
        xaxis = list(title = "Woche", dtick = 1),
        yaxis = list(title = "Verz\u00f6gerung (Tage)", zeroline = TRUE),
        hovermode = "x unified",
        legend = list(orientation = "h", y = 1.12),
        margin = list(t = 40)
      ) |>
      config(displayModeBar = FALSE, displaylogo = FALSE)
  })
}

shinyApp(ui, server)
