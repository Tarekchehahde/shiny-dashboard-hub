# =============================================================================
# hub/app.R — landing page for all dashboards on this server.
#
# Deployed behind nginx:
#   /              -> Mission Control (static)
#   /dashboards/   -> this hub (port 3838)
#   /most_visited_forecast/ -> 4-month outlook (port 3856)
#   /eurostat_resettled/    -> Eurostat migr_asyrescra (port 3857)
#   /eurostat_de_gas/       -> Germany natural-gas diversification (port 3858)
#   /transformative-ai/     -> static briefing (nginx alias)
#   /dummy_demo/   -> demo / test dashboard (port 3840)
#   /health_wealth_nations/ -> Gapminder-style bubble chart (port 3841)
#   /lebanese_elections/    -> Lebanese elections Tableau replica (port 3842)
#   /my_manager_demo/       -> Executive pitch / manager demo (port 3843)
#   /demo/igmetall-mitte-factory/ -> static IG Metall Mitte pitch demo (nginx alias)
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
    id = "care_workers_thuringia",
    title = "Care Workers in Th\u00fcringen",
    badge = "Research",
    badge_class = "bg-info text-dark",
    desc = "Qualitative recruitment research \u2014 5 stakeholder interviews, 125 coded extracts, 59 mapped organizations, advanced viz gallery.",
    highlight = TRUE
  ),
  list(
    id = "my_manager_demo",
    title = "MyManager Demo",
    badge = "Pitch",
    badge_class = "bg-primary",
    desc = "Executive demo: hub navigation, live interactivity, delivery pipeline, and live catalog — for your Monday presentation.",
    highlight = FALSE
  ),
  list(
    id = "igmetall_mitte_factory",
    title = "IG Metall Mitte \u2014 Werksgel\u00e4nde",
    badge = "Pitch",
    badge_class = "bg-danger",
    badge_style = "background-color: #e30613 !important;",
    desc = "Isometrische Eagle-Eye-Ansicht: Besch\u00e4ftigte, IG-Metall-Mitglieder und Organisationspotenzial pro Geb\u00e4ude \u2014 Proof-of-Concept f\u00fcr IG Metall Mitte (Tarek Chehade). Fiktive Demo-Daten, \u00f6ffentlich teilbar.",
    highlight = FALSE,
    href = "/demo/igmetall-mitte-factory/"
  ),
  list(
    id = "igmetall_mitte_demographics",
    title = "IG Metall Mitte \u2014 Demografie",
    badge = "Pitch",
    badge_class = "bg-danger",
    badge_style = "background-color: #e30613 !important;",
    desc = "Belegschaftsanalyse: Alter, Position, Betriebszugeh\u00f6rigkeit und Geschlecht nach Abteilung \u2014 interaktive Charts, Proof-of-Concept f\u00fcr IG Metall Mitte (Tarek Chehade). Fiktive Demo-Daten.",
    highlight = FALSE,
    href = "/demo/igmetall-mitte-demographics/"
  ),
  list(
    id = "igmetall_mitte_dfi",
    title = "IG Metall Mitte \u2014 DFI 2026",
    badge = "Pitch",
    badge_class = "bg-danger",
    badge_style = "background-color: #e30613 !important;",
    desc = "Daten Fakten Informationen 2026 digital: Tariferh\u00f6hungen, Laufzeiten, durchsuchbare Abschl\u00fcsse \u2014 Proof-of-Concept f\u00fcr IG Metall Mitte (Tarek Chehade).",
    highlight = FALSE,
    href = "/demo/igmetall-mitte-dfi/"
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
    id = "most_visited_forecast",
    title = "Most Visited — Prognose",
    badge = "MaStR",
    badge_class = "bg-warning text-dark",
    desc = "4-Monats-Prognose des Solar-Zubaus je Segment (Home, C&I, Large Scale, Total) aus den MaStR-Jahresmustern.",
    highlight = FALSE
  ),
  list(
    id = "eurostat_resettled",
    title = "Eurostat — Resettled persons",
    badge = "Eurostat",
    badge_class = "bg-primary",
    desc = "Resettled persons (migr_asyrescra): receiving country, citizenship, previous residence, age \u00d7 sex. Auto-refreshes when Eurostat updates the cube.",
    highlight = FALSE
  ),
  list(
    id = "eurostat_de_gas",
    title = "Germany — Natural gas diversification",
    badge = "Eurostat",
    badge_class = "bg-primary",
    desc = "German gas imports by partner (annual origin + monthly transit), LNG share, import dependency, storage, supply, and prices. Auto-refreshes when Eurostat updates any cube.",
    highlight = FALSE
  ),
  list(
    id = "transformative_ai",
    title = "Transformative AI — Europe",
    badge = "Briefing",
    badge_class = "bg-dark",
    desc = "One-screen public explainer of the September 2026 independent Transformative AI Strategy for Europe — five urgent moves, three pillars.",
    highlight = FALSE,
    href = "/transformative-ai/"
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
      care_workers_thuringia = 3855L,
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
      most_visited_forecast = 3856L,
      eurostat_resettled = 3857L,
      eurostat_de_gas = 3858L,
      health_wealth_nations = 3841L,
      lebanese_elections = 3842L,
      dummy_demo = 3840L
    )
    sprintf("http://localhost:%s/", ports[[id]])
  } else {
    sprintf("/%s/", id)
  }
}

.dashboard_href <- function(d) {
  d$href %||% .app_href(d$id)
}

.card_for <- function(d, idx = 1) {
  cls <- "h-100 hub-card"
  if (isTRUE(d$highlight)) cls <- paste(cls, "hub-card-highlight")
  badge <- tags$span(class = paste("badge me-2", d$badge_class), d$badge)
  if (!is.null(d$badge_style)) {
    badge$attribs$style <- d$badge_style
  }
  card(
    class = cls,
    style = sprintf("--hub-delay: %sms;", (idx - 1) * 70),
    card_header(
      badge,
      d$title
    ),
    p(class = "text-muted mb-3", d$desc),
    tags$a(
      class = if (isTRUE(d$highlight)) "btn btn-warning hub-btn" else "btn btn-primary hub-btn",
      href = .dashboard_href(d),
      target = "_self",
      "Open dashboard ",
      tags$span(class = "hub-btn-arrow", HTML("&rarr;"))
    )
  )
}

.hub_cards <- function() {
  ds <- hub_dashboards()
  Map(function(d, i) .card_for(d, i), ds, seq_along(ds))
}

hub_motion_css <- function() {
  tags$style(HTML("
    /* ---------- Hero ---------- */
    .hub-hero {
      position: relative; overflow: hidden;
      border-radius: 18px;
      padding: 2.6rem 2rem 2.2rem;
      margin-bottom: 1.75rem;
      color: #e2e8f0;
      background: linear-gradient(115deg, #0f172a, #1e2a4a 45%, #14233c 70%, #0f172a);
      background-size: 260% 260%;
      animation: hubGradientShift 16s ease infinite;
    }
    @keyframes hubGradientShift {
      0%   { background-position: 0% 50%; }
      50%  { background-position: 100% 50%; }
      100% { background-position: 0% 50%; }
    }
    .hub-hero h2 {
      font-weight: 700; letter-spacing: -0.02em; margin-bottom: .4rem;
      background: linear-gradient(90deg, #ffffff, #93c5fd, #6ee7b7, #ffffff);
      background-size: 300% auto;
      -webkit-background-clip: text; background-clip: text;
      -webkit-text-fill-color: transparent; color: transparent;
      animation: hubTextShimmer 7s linear infinite;
    }
    @keyframes hubTextShimmer {
      0% { background-position: 0% center; }
      100% { background-position: 300% center; }
    }
    .hub-hero .hub-hero-sub { color: #94a3b8; max-width: 46rem; }
    .hub-hero .hub-hero-sub a { color: #7dd3fc; }
    .hub-hero .hub-hero-hint { color: #64748b; font-size: .8rem; margin-bottom: 0; }
    .hub-hero .hub-hero-hint code { color: #93c5fd; background: rgba(148,163,184,.12);
                                    padding: 1px 5px; border-radius: 4px; }
    /* Floating aurora blobs */
    .hub-blob {
      position: absolute; border-radius: 50%;
      filter: blur(46px); opacity: .5; pointer-events: none;
      will-change: transform;
    }
    .hub-blob-1 { width: 300px; height: 300px; top: -120px; right: -60px;
      background: radial-gradient(circle, rgba(59,130,246,.55), transparent 65%);
      animation: hubFloat1 13s ease-in-out infinite; }
    .hub-blob-2 { width: 240px; height: 240px; bottom: -110px; left: 12%;
      background: radial-gradient(circle, rgba(16,185,129,.45), transparent 65%);
      animation: hubFloat2 17s ease-in-out infinite; }
    .hub-blob-3 { width: 190px; height: 190px; top: 10%; left: 55%;
      background: radial-gradient(circle, rgba(245,158,11,.35), transparent 65%);
      animation: hubFloat3 21s ease-in-out infinite; }
    @keyframes hubFloat1 { 0%,100% { transform: translate(0,0) scale(1); }
      50% { transform: translate(-45px, 35px) scale(1.12); } }
    @keyframes hubFloat2 { 0%,100% { transform: translate(0,0) scale(1); }
      50% { transform: translate(55px, -30px) scale(.92); } }
    @keyframes hubFloat3 { 0%,100% { transform: translate(0,0); }
      33% { transform: translate(-35px, 25px); }
      66% { transform: translate(30px, -20px); } }
    /* Drifting particle dots */
    .hub-particle {
      position: absolute; bottom: -8px; border-radius: 50%;
      background: rgba(148, 197, 253, .5); pointer-events: none;
      animation: hubRise linear infinite;
    }
    @keyframes hubRise {
      0%   { transform: translateY(0) translateX(0); opacity: 0; }
      12%  { opacity: .7; }
      88%  { opacity: .5; }
      100% { transform: translateY(-320px) translateX(28px); opacity: 0; }
    }
    /* ---------- Cards ---------- */
    .hub-card {
      opacity: 0;
      animation: hubCardIn .6s cubic-bezier(.22,1,.36,1) forwards;
      animation-delay: var(--hub-delay, 0ms);
      transition: transform .28s cubic-bezier(.22,1,.36,1), box-shadow .28s ease;
      position: relative; overflow: hidden;
      border: 1px solid rgba(15,23,42,.08);
    }
    @keyframes hubCardIn {
      from { opacity: 0; transform: translateY(22px) scale(.985); }
      to   { opacity: 1; transform: translateY(0) scale(1); }
    }
    .hub-card::before {
      content: ''; position: absolute; top: 0; left: 0; right: 0; height: 3px;
      background: linear-gradient(90deg, #0B5ED7, #10b981, #f59e0b, #0B5ED7);
      background-size: 300% auto;
      transform: scaleX(0); transform-origin: left;
      transition: transform .35s cubic-bezier(.22,1,.36,1);
      animation: hubTextShimmer 5s linear infinite;
      z-index: 2;
    }
    .hub-card:hover {
      transform: translateY(-6px);
      box-shadow: 0 18px 40px -14px rgba(15, 23, 42, .28);
    }
    .hub-card:hover::before { transform: scaleX(1); }
    /* Shine sweep on hover */
    .hub-card::after {
      content: ''; position: absolute; top: 0; bottom: 0; width: 55%;
      left: -80%; transform: skewX(-18deg);
      background: linear-gradient(90deg, transparent,
                  rgba(255,255,255,.35), transparent);
      transition: left .65s ease; pointer-events: none; z-index: 1;
    }
    .hub-card:hover::after { left: 130%; }
    .hub-card-highlight {
      border: 2px solid rgba(245,158,11,.75);
      box-shadow: 0 6px 22px -8px rgba(245,158,11,.35);
      animation: hubCardIn .6s cubic-bezier(.22,1,.36,1) forwards,
                 hubGlowPulse 3.2s ease-in-out infinite 1s;
    }
    @keyframes hubGlowPulse {
      0%,100% { box-shadow: 0 6px 22px -8px rgba(245,158,11,.30); }
      50%     { box-shadow: 0 6px 30px -6px rgba(245,158,11,.55); }
    }
    .hub-card .badge { transition: transform .25s ease; }
    .hub-card:hover .badge { transform: scale(1.08); }
    /* Button arrow nudge */
    .hub-btn .hub-btn-arrow { display: inline-block;
      transition: transform .25s cubic-bezier(.22,1,.36,1); }
    .hub-btn:hover .hub-btn-arrow { transform: translateX(5px); }
    /* ---------- Accessibility ---------- */
    @media (prefers-reduced-motion: reduce) {
      .hub-hero, .hub-hero h2, .hub-blob, .hub-particle,
      .hub-card, .hub-card::before, .hub-card-highlight {
        animation: none !important;
      }
      .hub-card { opacity: 1; }
      .hub-card, .hub-btn .hub-btn-arrow { transition: none; }
    }
  "))
}

hub_hero <- function() {
  particles <- lapply(1:9, function(i) {
    tags$span(
      class = "hub-particle",
      style = sprintf(
        "left: %s%%; width: %spx; height: %spx; animation-duration: %ss; animation-delay: %ss;",
        c(6, 16, 27, 38, 50, 61, 72, 84, 93)[i],
        c(5, 3, 6, 4, 3, 5, 4, 6, 3)[i],
        c(5, 3, 6, 4, 3, 5, 4, 6, 3)[i],
        c(9, 13, 8, 15, 11, 10, 14, 9, 12)[i],
        c(0, 2.5, 1, 4, 0.5, 3, 1.8, 5, 2)[i]
      )
    )
  })
  div(
    class = "hub-hero",
    div(class = "hub-blob hub-blob-1"),
    div(class = "hub-blob hub-blob-2"),
    div(class = "hub-blob hub-blob-3"),
    particles,
    h2("Dashboard Hub"),
    p(
      class = "hub-hero-sub",
      "Live data dashboards \u2014 select one below. ",
      tags$a(href = "/", class = "text-decoration-none", "Mission Control"),
      " \u00b7 ",
      tags$a(href = "/about/", class = "text-decoration-none", "About"),
      ", Grafana, docs."
    ),
    p(
      class = "hub-hero-hint",
      "Add new entries in ", code("hub/app.R"),
      " and register the app path in nginx/systemd."
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
  hub_motion_css(),
  div(
    class = "container py-4",
    hub_hero(),
    div(
      class = "hub-card-grid",
      layout_column_wrap(
      width = 1/2,
      gap = "1rem",
      !!!.hub_cards()
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
