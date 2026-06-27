# =============================================================================
# app.R — single entry point that shows a picker and launches the chosen
# dashboard. Open this file in RStudio and click "Run App", or call
#   shiny::runApp("WORK/shiny")               # from the repo root
#   shiny::runGitHub("shiny-dashboard-hub", "Tarekchehahde", subdir = "WORK/shiny",
#                    ref = "main", launch.browser = TRUE)
#
# Tip: to launch a single dashboard directly, run
#   shiny::runApp("apps/02_solar_pv")
# =============================================================================

suppressPackageStartupMessages({
  library(shiny); library(bslib)
})

# Each list() is a dashboard. `group` determines the visual section shown
# on the launcher:
#   "flagship" -> the single big comparable-to-Candida card at the top.
#   "core"     -> the original MaStR-wide Shiny dashboards we built.
#   "tableau"  -> the Tableau-parity pack (one app per Tableau sheet in the
#                 in-house "Deutsche Marktentwicklung" workbook).
APPS <- list(
  list(id = "most_visited",      title = "Most Visited",
       group = "flagship",
       desc = "Monatlicher Solar-Zubau (MW) nach Segment + YTD-Vergleichstabelle \u2014 Nachbau des internen Tableau-Referenzpanels.",
       highlight = TRUE),

  list(id = "01_overview",       title = "MaStR — Überblick",
       group = "core",
       desc = "KPIs: Einheiten, installierte Leistung, EE-Anteil"),
  list(id = "02_solar_pv",       title = "Solar PV",
       group = "core",
       desc = "PV-Fleet nach Größenklasse und Bundesland"),
  list(id = "03_wind_onshore",   title = "Wind Onshore",
       group = "core",
       desc = "Turbinen, Nabenhöhen, Rotordurchmesser"),
  list(id = "04_wind_offshore",  title = "Wind Offshore",
       group = "core",
       desc = "Offshore-Parks, Wassertiefe, Küstenentfernung"),
  list(id = "05_biomass",        title = "Biomasse",
       group = "core",
       desc = "Biogas- und Biomasseanlagen"),
  list(id = "06_hydro",          title = "Wasserkraft",
       group = "core",
       desc = "Laufwasser, Speicher, Pumpspeicher"),
  list(id = "07_geothermal",     title = "Geothermie & Sonstige",
       group = "core",
       desc = "Tiefe Geothermie, Solarthermie, Grubengas"),
  list(id = "08_storage",        title = "Stromspeicher",
       group = "core",
       desc = "Batterie + Pumpspeicher, Leistung und Kapazität"),
  list(id = "09_chp",            title = "KWK",
       group = "core",
       desc = "Kraft-Wärme-Kopplung: el/th Nutzleistung"),
  list(id = "10_grid_operators", title = "Netzbetreiber",
       group = "core",
       desc = "Netzanschlusspunkte je Betreiber + Spannungsebene"),
  list(id = "11_market_actors",  title = "Marktakteure",
       group = "core",
       desc = "Betreiber, Händler, Netzbetreiber, …"),
  list(id = "12_geo_map",        title = "Geo-Karte",
       group = "core",
       desc = "PLZ-geclusterte Karte aller Einheiten"),
  list(id = "13_capacity_trends",title = "Zubau-Trends",
       group = "core",
       desc = "Monatlicher / kumulativer Zubau nach Technologie"),
  list(id = "14_state_comparison",title = "Bundesländer-Vergleich",
       group = "core",
       desc = "Absolut + pro Kopf Ranking"),
  list(id = "15_ee_quote",       title = "EE-Quote",
       group = "core",
       desc = "EE-Anteil pro Jahr und Bundesland"),

  list(id = "16_ibn_stacked_area", title = "Inbetriebnahmen (2)",
       group = "tableau",
       desc = "Gestapelter Flächen-Chart: Monatlicher Solar-Zubau nach Größenklasse."),
  list(id = "17_anlagen_leistung", title = "Überblick — Anlagen & Leistung",
       group = "tableau",
       desc = "Summary-Tabelle je Bucket + 3 Deutschland-Maps + Quartals-Zeitreihe."),
  list(id = "18_ibn_tabelle",      title = "Inbetriebnahmen MaStR — Tabelle",
       group = "tableau",
       desc = "IBN-Differenzen zum Vorzeitraum nach Jahr/Quartal/Monat."),
  list(id = "19_ibn_bars",         title = "Inbetriebnahmen MaStR — Balken",
       group = "tableau",
       desc = "4 Quartalsbalken: Solaranlagen und Bruttoleistung MW (abs + Δ)."),
  list(id = "20_ibn_speicher_bars", title = "Inbetriebnahmen Speicher — Balken",
       group = "tableau",
       desc = "Storage-Pendant zu 19 — Quartalsbalken, Δ und absolut."),
  list(id = "21_ibn_speicher_tabelle", title = "Inbetriebnahmen Speicher — Tabelle",
       group = "tableau",
       desc = "Storage-Pendant zu 18 — Tabelle mit Jahr/Quartal/Monat + Δ."),
  list(id = "22_batteriekapazitaet", title = "Histogramm Batteriekapazität",
       group = "tableau",
       desc = "Histogramm-Panels für Stromspeicher (Kapazitäts-Spalte folgt nach ETL-Erweiterung)."),
  list(id = "23_registrierungsverhalten", title = "Registrierungsverhalten",
       group = "tableau",
       desc = "Tage zwischen IBN und Registrierung — Median, Box und Histogramm."),
  list(id = "24_registrierungsverhalten_vergleich", title = "Registrierungsverhalten im Vergleich",
       group = "tableau",
       desc = "Heatmaps Registrierungszeit vs. Inbetriebnahmezeit + Nachmeldungs-Matrix.")
)

.app_card <- function(a) {
  cls <- "h-100"
  if (isTRUE(a$highlight)) cls <- paste(cls, "border-warning border-3 shadow")
  card(
    class = cls,
    card_header(if (isTRUE(a$highlight))
                  span(tags$span(class = "badge bg-warning text-dark me-2", "FLAGSHIP"), a$title)
                else a$title),
    p(a$desc),
    actionButton(paste0("go_", a$id), "Start",
                 class = if (isTRUE(a$highlight)) "btn-warning" else "btn-primary")
  )
}

.apps_in <- function(group) Filter(function(a) a$group == group, APPS)

ui <- page_fluid(
  title = "MaStR Shiny — Launcher",
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  div(class = "container py-3",
      h2("MaStR Shiny Dashboards"),
      p(class = "text-muted",
        "Daten werden live aus dem neuesten GitHub-Release gelesen (kein XML nötig)."),

      h4(class = "mt-4", "Flagship \u2014 Tableau-Referenz (Solar-Zubau)"),
      p(class = "text-muted small",
        "R-Shiny-Nachbau des internen Tableau-Blatts: Zubauleistung pro Segment und Vorjahresvergleich."),
      layout_column_wrap(width = 1, gap = "1rem",
        !!!lapply(.apps_in("flagship"), .app_card)),

      h4(class = "mt-4", "Kern-Dashboards"),
      p(class = "text-muted small",
        "MaStR-weite Dashboards (nicht Tableau-parity, sondern frei gebaut)."),
      layout_column_wrap(width = 1/3, gap = "1rem",
        !!!lapply(.apps_in("core"), .app_card)),

      h4(class = "mt-4", "Tableau-Vergleich (Nachbau der BNetzA/MaStR-Tableau-Mappe)"),
      p(class = "text-muted small",
        "Jeder Eintrag hier ist ein 1:1 R-Nachbau eines Tableau-Blatts aus unserer internen ",
        tags$em("Deutsche Marktentwicklung"), "-Mappe."),
      layout_column_wrap(width = 1/3, gap = "1rem",
        !!!lapply(.apps_in("tableau"), .app_card))
  )
)

server <- function(input, output, session) {
  for (a in APPS) local({
    id <- a$id
    observeEvent(input[[paste0("go_", id)]], {
      path <- file.path("apps", id)
      session$sendCustomMessage(
        "jsCode",
        list(code = sprintf(
          "window.alert('Starting %s… Close this window, then run:\\nshiny::runApp(\"%s\")');",
          id, path))
      )
      # If running as a normal Shiny app (not hosted), we can also stop and
      # relaunch. In RStudio the common pattern is: stopApp then runApp.
      stopApp(returnValue = path)
    })
  })
}

launched <- shinyApp(ui, server)
# When run via Rscript, honor the returned value:
if (interactive()) {
  picked <- runApp(launched)
  if (is.character(picked) && nzchar(picked)) {
    message(sprintf(">> launching %s", picked))
    shiny::runApp(picked)
  }
} else {
  launched
}
