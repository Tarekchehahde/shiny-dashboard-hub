# =============================================================================
# hub/app.R — landing page for all dashboards on this server.
#
# Deployed behind nginx:
#   /              -> this hub (port 3838)
#   /most_visited/ -> flagship Most Visited (port 3839)
#   /dummy_demo/   -> demo / test dashboard (port 3840)
#   /health_wealth_nations/ -> Gapminder-style bubble chart (port 3841)
#   /lebanese_elections/    -> Lebanese elections Tableau replica (port 3842)
#   /my_manager_demo/       -> Executive pitch / manager demo (port 3843)
#   /deutschland_solar_radiation/ -> Live solar GHI map Germany (port 3844)
#   /thueringen_gewerbe_strom/       -> Demo 1 Gewerbe-Strom (port 3847)
#   /thueringen_waermepumpe_gebaeude/ -> Demo 2 (port 3848)
#   /thueringen_fachkraefte/          -> Demo 3 (port 3849)
#   /thueringen_logistik/             -> Demo 4 (port 3850)
#   /thueringen_tourismus/            -> Demo 5 (port 3851)
#   /thueringen_kommunal/             -> Demo 6 (port 3852)
#   /thueringen_mittelstand_digital/  -> Demo 7 (port 3853)
#
# Local RStudio (multi-port mode):
#   Sys.setenv(MASTR_HUB_MODE = "ports")
#   shiny::runApp("hub")
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(htmltools)
})

source("../R/ui_helpers.R")

# Dashboards hidden from the hub (direct URL may also be blocked on VPS).
# Re-enable for erwicon: remove id from HUB_HIDDEN_IDS below + restart hub + fachkraefte service.
`%||%` <- function(x, y) if (is.null(x)) y else x

HUB_HIDDEN_IDS <- c("thueringen_fachkraefte")

DASHBOARDS <- list(
  list(
    id = "my_manager_demo",
    title = "MyManager Demo",
    badge = "Pitch",
    badge_class = "bg-primary",
    desc = "Executive demo: hub navigation, live interactivity, delivery pipeline, and live catalog — for your Monday presentation.",
    highlight = FALSE
  ),
  list(
    id = "dummy_demo",
    title = "Demo Dashboard",
    badge = "Test",
    badge_class = "bg-secondary",
    desc = "Dummy KPIs and charts — use this slot to verify the hub routing.",
    highlight = FALSE
  ),
  list(
    id = "most_visited",
    title = "Most Visited",
    badge = "MaStR",
    badge_class = "bg-warning text-dark",
    desc = "Monatlicher Solar-Zubau (MW) nach Segment + YTD-Vergleichstabelle.",
    highlight = FALSE
  ),
  list(
    id = "deutschland_solar_radiation",
    title = "Solar Radiation — Germany",
    badge = "Live",
    badge_class = "bg-warning text-dark",
    desc = "Live global horizontal irradiance (W/m²) across Germany — Open-Meteo / DWD satellite models, map + hourly chart.",
    highlight = FALSE
  ),
  list(
    id = "health_wealth_nations",
    title = "Health and Wealth of Nations",
    badge = "Gapminder",
    badge_class = "bg-info text-dark",
    desc = "Hans Rosling\u2013style bubble chart: life expectancy vs GDP per capita, animated over time.",
    highlight = FALSE
  ),
  list(
    id = "eu_electricity_live",
    title = "EU Electricity \u2014 Live Prices",
    badge = "Live",
    badge_class = "bg-info text-dark",
    desc = "Day-ahead power prices across European bidding zones \u2014 map, comparison chart, zone table (Energy-Charts / Fraunhofer ISE).",
    highlight = FALSE
  ),
  list(
    id = "lebanese_elections",
    title = "Lebanese Elections",
    badge = "Tableau",
    badge_class = "bg-success",
    desc = "2022 parliamentary election casas: voter density, candidates, and interactive treemap (Tarek Chehade).",
    highlight = FALSE
  ),
  list(
    id = "thueringen_solar_wirtschaft",
    title = "Th\u00fcringen Solar-Wirtschaft",
    badge = "Th\u00fcringen",
    badge_class = "bg-secondary",
    desc = "MaStR Photovoltaik im Freistaat: Kreis-Ranking, Erfurt-Spotlight, monatlicher Zubau \u2014 Demo f\u00fcr erwicon connect (23. Juni 2026, Erfurt).",
    highlight = FALSE
  ),
  list(
    id = "thueringen_gewerbe_strom",
    title = "Th\u00fcringen Gewerbe-Strom",
    badge = "Th\u00fcringen",
    badge_class = "bg-secondary",
    desc = "Demo 1/7: Day-Ahead-Strompreis (DE-LU) + PV Gewerbe/Industrie & Speicher in Th\u00fcringen \u2014 interaktiver Preis-Verlauf.",
    highlight = FALSE
  ),
  list(
    id = "thueringen_waermepumpe_gebaeude",
    title = "Th\u00fcringen W\u00e4rmepumpen & Geb\u00e4ude-Energie",
    badge = "Th\u00fcringen",
    badge_class = "bg-secondary",
    desc = "Demo 2/7: Speicher, Home-PV & Biomasse nach Kreis \u2014 Geb\u00e4ude-Energiewende im Freistaat.",
    highlight = FALSE
  ),
  list(
    id = "thueringen_fachkraefte",
    title = "Th\u00fcringen Regionalwirtschaft",
    badge = "Th\u00fcringen",
    badge_class = "bg-secondary",
    desc = "Demo 3/7: Wirtschaftsdynamik nach Kreis \u2014 Besch\u00e4ftigung & Nachfrageindikatoren (BA Statistik).",
    highlight = FALSE,
    published = FALSE
  ),
  list(
    id = "thueringen_logistik",
    title = "Th\u00fcringen Logistik & Standort",
    badge = "Th\u00fcringen",
    badge_class = "bg-secondary",
    desc = "Demo 4/7: A4/A9/A38-Standort, Pendler & Gewerbe-PV \u2014 Erfurt als Logistikdrehscheibe.",
    highlight = FALSE
  ),
  list(
    id = "thueringen_tourismus",
    title = "Th\u00fcringen Tourismus & Konsum",
    badge = "Th\u00fcringen",
    badge_class = "bg-secondary",
    desc = "Demo 5/7: \u00dcbernachtungen & Saisonst\u00e4rke nach Kreis \u2014 Wartburg, Weimar, Th\u00fcringer Wald.",
    highlight = FALSE
  ),
  list(
    id = "thueringen_kommunal",
    title = "Th\u00fcringen Kommunal & Infrastruktur",
    badge = "Th\u00fcringen",
    badge_class = "bg-secondary",
    desc = "Demo 6/7: Gro\u00dfsolar, Speicher & Wind nach Kreis \u2014 f\u00fcr Stadtwerke, Landkreise, Planer.",
    highlight = FALSE
  ),
  list(
    id = "thueringen_mittelstand_digital",
    title = "Th\u00fcringen Mittelstand-Digital",
    badge = "Th\u00fcringen",
    badge_class = "bg-secondary",
    desc = "Demo 7/7: Live-Daten statt Excel-PDF \u2014 Cockpit-Katalog aller erwicon-Demos + illustrative Wochen-KPIs.",
    highlight = FALSE
  )
)

hub_dashboards <- function() {
  Filter(function(d) {
    isTRUE(d$published %||% TRUE) && !(d$id %in% HUB_HIDDEN_IDS)
  }, DASHBOARDS)
}

.app_href <- function(id) {
  if (identical(Sys.getenv("MASTR_HUB_MODE", "paths"), "ports")) {
    ports <- c(
      thueringen_mittelstand_digital = 3853L,
      thueringen_kommunal = 3852L,
      thueringen_tourismus = 3851L,
      thueringen_logistik = 3850L,
      thueringen_fachkraefte = 3849L,
      thueringen_waermepumpe_gebaeude = 3848L,
      thueringen_gewerbe_strom = 3847L,
      eu_electricity_live = 3846L,
      thueringen_solar_wirtschaft = 3845L,
      my_manager_demo = 3843L,
      deutschland_solar_radiation = 3844L,
      most_visited = 3839L,
      health_wealth_nations = 3841L,
      lebanese_elections = 3842L,
      dummy_demo = 3840L
    )
    sprintf("http://localhost:%s/", ports[[id]])
  } else {
    sprintf("/%s/", id)
  }
}

.card_for <- function(d) {
  cls <- "h-100"
  if (isTRUE(d$highlight)) cls <- paste(cls, "border-warning border-3 shadow-sm")
  badge <- tags$span(class = paste("badge me-2", d$badge_class), d$badge)
  if (!is.null(d$badge_style)) {
    badge$attribs$style <- d$badge_style
  }
  card(
    class = cls,
    card_header(
      badge,
      d$title
    ),
    p(class = "text-muted mb-3", d$desc),
    tags$a(
      class = if (isTRUE(d$highlight)) "btn btn-warning" else "btn btn-primary",
      href = .app_href(d$id),
      target = "_self",
      "Open dashboard"
    )
  )
}

ui <- page_fluid(
  title = "Dashboard Hub",
  theme = mastr_theme(),
  mastr_responsive_css(),
  mastr_creator_qr_head(),
  mastr_creator_qr_styles(),
  tags$style(HTML("
    .hub-card-grid .card { min-width: 0; }
    @media (max-width: 991.98px) {
      .hub-card-grid {
        display: flex !important;
        flex-direction: column !important;
      }
      .hub-card-grid > * { width: 100% !important; max-width: 100% !important; }
    }
  ")),
  div(
    class = "container py-4",
    div(
      class = "mb-4",
      h2("Dashboard Hub"),
      p(
        class = "text-muted",
        "Select a dashboard below. ",
        tags$a(href = "/portal/", class = "text-decoration-none", "Mission Control"),
        " — Grafana, Netdata, RStudio, ",
        tags$a(href = "/portal/docs/", class = "text-decoration-none", "documentation"),
        "."
      ),
      p(
        class = "text-muted small mb-0",
        "Add new entries in ",
        code("hub/app.R"), " and register the app path in nginx/systemd."
      )
    ),
    div(
      class = "hub-card-grid",
      layout_column_wrap(
      width = 1/2,
      gap = "1rem",
      !!!lapply(hub_dashboards(), .card_for)
      )
    ),
    hr(),
    mastr_creator_qr_ui("de"),
    p(
      class = "mastr-footer",
      "Server: ", Sys.info()[["nodename"]],
      " · hub mode: ", Sys.getenv("MASTR_HUB_MODE", "paths")
    )
  )
)

server <- function(input, output, session) {}

shinyApp(ui, server)
