# Shared thesis launcher UI + server (used by app.R and run_app_thesis_energy.R)
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
      # run_app_thesis_energy.R sets options(thesis.menu.return_path = TRUE) so the
      # outer script can runApp(menu) then runApp(child). shiny::runGitHub only runs
      # one outer runApp — without this branch the session ends and the child never starts.
      if (isTRUE(getOption("thesis.menu.return_path", FALSE))) {
        stopApp(returnValue = path)
      } else {
        apath <- normalizePath(file.path(getwd(), path), mustWork = FALSE)
        session$onSessionEnded(function() {
          if (!dir.exists(apath)) {
            warning("Thesis app folder not found: ", apath)
            return()
          }
          shiny::runApp(apath, launch.browser = TRUE)
        })
        stopApp()
      }
    })
  })
}
