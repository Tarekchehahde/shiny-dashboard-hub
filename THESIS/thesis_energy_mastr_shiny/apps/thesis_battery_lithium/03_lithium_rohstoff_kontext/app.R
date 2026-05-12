# Thesis track — Lithium / Rohstoffe: kein MaStR-Inhalt; Kontext + editierbare CSV

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(reactable)
})
source("../../../R/mastr_data.R") # für Footer / ggf. Release-Info
source("../../../R/ui_helpers.R")

THESIS_PRIMARY <- "#0f766e"

csv_path <- normalizePath("../../../data/thesis_static/lithium_projects_de.csv", mustWork = FALSE)

ui <- mastr_page(
  title = "Lithium & Rohstoffe (Deutschland) — Kontext",
  subtitle = "MaStR listet Netzinfrastruktur und Stromspeicher, keine Bergbauprojekte. Diese Seite ergänzt die quantitative Speicher-Analyse mit Rohstoff-/Projektbezug.",
  primary = THESIS_PRIMARY,

  card(
    card_header("Abgrenzung"),
    p(
      "Der ",
      tags$a(href = "https://www.marktstammdatenregister.de/", target = "_blank", "Marktstammdatenregister"),
      " deckt u. a. registrierte Stromspeicher ab — ",
      strong("nicht"),
      " geologische Lithiumvorkommen oder Gewinnungsgenehmigungen. Für „weißes Gold“ / Extraktion nutzen Sie externe Quellen (z. B. Landesbehörden, BGR, Projektmitteilungen) und pflegen Sie die Tabelle unten im Repo."
    )
  ),

  layout_column_wrap(width = 1 / 2,
    card(
      card_header("Referenz (extern)"),
      tags$ul(
        tags$li(tags$a(href = "https://www.bgr.bund.de/", target = "_blank", "BGR — Bundesanstalt für Geowissenschaften und Rohstoffe")),
        tags$li(tags$a(href = "https://www.deutsche-rohstoffagentur.de/", target = "_blank", "Deutsche Rohstoffagentur (DERA)")),
        tags$li("Projektbezogene Literatur: siehe Euer Thesis-Repo unter Literatur/Policy.")
      )
    ),
    card(
      card_header("Release (gleiche Pipeline wie alle Dashboards)"),
      verbatimTextOutput("release_box")
    )
  ),

  card(
    card_header("Curated projects — bearbeiten unter thesis_energy_mastr_shiny/data/thesis_static/lithium_projects_de.csv"),
    reactableOutput("proj_table"),
    p(class = "small text-muted mt-2", "Spalten: project_name, region, bundesland, status, year_note, notes, source_url")
  )
)

server <- function(input, output, session) {
  output$release_box <- renderPrint({
    try(mastr_release_info(), silent = TRUE)
  })

  output$proj_table <- renderReactable({
    if (!file.exists(csv_path)) {
      return(reactable(data.frame(
        Hinweis = "CSV fehlt — lege lithium_projects_de.csv unter data/thesis_static/ (Arbeitsverzeichnis thesis_energy_mastr_shiny/) an."
      )))
    }
    raw <- utils::read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE)
    if (nrow(raw) == 0) {
      return(reactable(data.frame(Hinweis = "CSV ist leer (außer Header).")))
    }
    reactable(raw, compact = TRUE, striped = TRUE, searchable = TRUE, resizable = TRUE)
  })
}

shinyApp(ui, server)
