# =============================================================================
# run_app_thesis_energy.R — SEPARATE launcher for thesis / research dashboards
# (battery tech, storage focus, lithium raw-materials context). Does not modify
# or reference production run_app.R or apps/01_* … 15_*.
#
# Usage (from THESIS/thesis_energy_mastr_shiny/ inside clone of Tarekchehahde/mastr-shiny):
#   shiny::runApp("run_app_thesis_energy.R")
# =============================================================================

suppressPackageStartupMessages({
  library(shiny); library(bslib)
})

THESIS_PRIMARY <- "#0f766e"

APPS <- list(
  list(id = "apps/thesis_battery_lithium/01_batteries_deutschland",
       title = "Batteriespeicher Deutschland",
       desc = "MaStR Stromspeicher mit Fokus auf Batteriespeicher: Leistung, Kapazität, Zubau."),
  list(id = "apps/thesis_battery_lithium/02_speicher_technologie_mix",
       title = "Speicher-Technologien",
       desc = "Mix Batteriespeicher vs. Pumpspeicher u. a. — gleiche Datenbasis, andere Schnitte."),
  list(id = "apps/thesis_battery_lithium/03_lithium_rohstoff_kontext",
       title = "Lithium & Rohstoffe (Kontext)",
       desc = "Kein MaStR-Thema: Kurzüberblick + editierbare Projekttabelle (CSV), ergänzend zur Analyse.")
)

ui <- page_fillable(
  title = "MaStR — Thesis track (Energie)",
  theme = bs_theme(version = 5, bootswatch = "flatly", primary = THESIS_PRIMARY),
  div(class = "container py-3",
      h2("Thesis / Forschung — Batterie, Speicher, Lithium"),
      p(class = "text-muted",
        "Separater Einstieg: Production-Dashboards (`WORK/shiny/app.R`) bleiben unverändert."),
      p(class = "small text-muted",
        "Daten: gleiche GitHub-Release-Pipeline wie alle anderen Shiny-Apps (kein ETL-Change)."),
      layout_column_wrap(
        width = 1/3,
        !!!lapply(APPS, function(a) {
          card(
            card_header(a$title),
            p(a$desc),
            actionButton(paste0("go_", gsub("[^a-zA-Z0-9_]", "_", a$id)), "Start",
                         class = "btn-primary")
          )
        })
      )
  )
)

server <- function(input, output, session) {
  for (a in APPS) local({
    slug <- gsub("[^a-zA-Z0-9_]", "_", a$id)
    path <- a$id
    observeEvent(input[[paste0("go_", slug)]], {
      message(">> thesis track: launching ", path)
      stopApp(returnValue = path)
    })
  })
}

launched <- shinyApp(ui, server)
if (interactive()) {
  picked <- runApp(launched)
  if (is.character(picked) && nzchar(picked)) {
    app_full <- file.path(getwd(), picked)
    if (!dir.exists(app_full)) {
      stop(
        "App not found at:\n  ", app_full,
        "\nSet working directory to THESIS/thesis_energy_mastr_shiny/ (repo mastr-shiny) then run:\n",
        "  shiny::runApp(\"run_app_thesis_energy.R\")",
        call. = FALSE
      )
    }
    message(sprintf(">> launching %s", picked))
    shiny::runApp(app_full)
  }
} else {
  launched
}
