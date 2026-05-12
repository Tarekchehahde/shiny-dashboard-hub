# Thesis track — Lithium / Rohstoffe: kein MaStR-Inhalt; Kontext + editierbare CSV + einfache Visualisierung

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(reactable)
  library(plotly)
  library(dplyr)
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

  layout_column_wrap(
    width = 1 / 2,
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
    card_header("Visualisierung (CSV)"),
    layout_column_wrap(
      width = 1 / 2,
      card(
        card_header("Einträge nach Status"),
        plotlyOutput("viz_status", height = "300px")
      ),
      card(
        card_header("Einträge nach Bundesland / Ebene"),
        plotlyOutput("viz_bundesland", height = "300px")
      )
    ),
    p(
      class = "small text-muted",
      "Quelle: ",
      tags$code("data/thesis_static/lithium_projects_de.csv"),
      " — in RStudio CSV bearbeiten, App mit „Stop“ / neu ",
      tags$code("runApp"),
      " neu laden."
    )
  ),

  card(
    card_header("Curated projects — bearbeiten unter thesis_energy_mastr_shiny/data/thesis_static/lithium_projects_de.csv"),
    reactableOutput("proj_table"),
    p(class = "small text-muted mt-2", "Spalten: project_name, region, bundesland, status, year_note, notes, source_url")
  )
)

server <- function(input, output, session) {
  proj_df <- reactive({
    if (!file.exists(csv_path)) {
      return(NULL)
    }
    utils::read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8")
  })

  output$release_box <- renderPrint({
    try(mastr_release_info(), silent = TRUE)
  })

  .lbl <- function(x) {
    x <- trimws(ifelse(is.na(x) | x == "", "—", as.character(x)))
    x
  }

  output$viz_status <- renderPlotly({
    raw <- proj_df()
    if (is.null(raw) || nrow(raw) == 0) {
      return(mastr_plotly_empty("Keine CSV-Zeilen für Status"))
    }
    ct <- raw |>
      transmute(status = .lbl(status)) |>
      count(status, name = "n") |>
      arrange(desc(n))
    plot_ly(
      ct,
      x = ~n,
      y = ~reorder(status, n),
      type = "bar",
      orientation = "h",
      marker = list(color = THESIS_PRIMARY)
    ) |>
      layout(
        xaxis = list(title = "Anzahl"),
        yaxis = list(title = ""),
        margin = list(l = 160, r = 20, t = 20, b = 40),
        showlegend = FALSE
      )
  })

  output$viz_bundesland <- renderPlotly({
    raw <- proj_df()
    if (is.null(raw) || nrow(raw) == 0) {
      return(mastr_plotly_empty("Keine CSV-Zeilen für Bundesland"))
    }
    ct <- raw |>
      transmute(bundesland = .lbl(bundesland)) |>
      count(bundesland, name = "n") |>
      arrange(desc(n))
    plot_ly(
      ct,
      x = ~n,
      y = ~reorder(bundesland, n),
      type = "bar",
      orientation = "h",
      marker = list(color = "#0e7490")
    ) |>
      layout(
        xaxis = list(title = "Anzahl"),
        yaxis = list(title = ""),
        margin = list(l = 160, r = 20, t = 20, b = 40),
        showlegend = FALSE
      )
  })

  output$proj_table <- renderReactable({
    raw <- proj_df()
    if (is.null(raw)) {
      return(reactable(data.frame(
        Hinweis = "CSV fehlt — lege lithium_projects_de.csv unter data/thesis_static/ (Arbeitsverzeichnis thesis_energy_mastr_shiny/) an."
      )))
    }
    if (nrow(raw) == 0) {
      return(reactable(data.frame(Hinweis = "CSV ist leer (außer Header).")))
    }
    reactable(
      raw,
      compact = TRUE,
      striped = TRUE,
      searchable = TRUE,
      resizable = TRUE,
      columns = list(
        source_url = colDef(
          cell = function(value) {
            if (!is.character(value) || !nzchar(value)) return("—")
            url <- value[1]
            htmltools::tags$a(href = url, target = "_blank", "Link")
          },
          html = TRUE,
          minWidth = 80
        )
      )
    )
  })
}

shinyApp(ui, server)
