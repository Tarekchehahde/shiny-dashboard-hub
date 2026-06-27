# =============================================================================
# thueringen_fachkraefte — Regionalwirtschaft nach Kreis (BA STEA/BST).
# erwicon connect 2026 · Demo 3/7 — hidden from hub until event day.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(ggplot2)
  library(leaflet)
  library(reactable)
  library(scales)
  library(jsonlite)
  library(httr2)
})

source("../../R/ui_helpers.R")
source("../../R/thueringen_helpers.R")
source("../../R/ba_labor_data.R")

`%||%` <- function(x, y) if (is.null(x)) y else x

KREIS_META <- thueringen_kreis_meta()
KREIS_CHOICES <- c("Alle" = "all", stats::setNames(KREIS_META$kreis, KREIS_META$kreis))

ui <- mastr_page(
  title = "Th\u00fcringen Regionalwirtschaft",
  subtitle = "Wirtschaftsdynamik nach Kreis \u2014 Besch\u00e4ftigung & Nachfrageindikatoren (BA Statistik).",
  fluid = TRUE,
  primary = ERWICON_PRIMARY,
  footer = "thueringen_fachkraefte",
  hub_back_label = "\u2190 Zur\u00fcck zum Hub",
  creator_qr_lang = "de",
  erwicon_banner_ui(
    "\u201eWo w\u00e4chst die Wirtschaft in Ihrer Region?\u201c",
    " Regionalvergleich f\u00fcr Handwerk & Industrie \u2014 offizielle BA-Kennzahlen nach Kreis."
  ),
  tags$style(HTML("
    .kreis-map { border-radius: 8px; min-height: 420px; }
    .ba-meta { font-size: 0.78rem; color: #64748b; }
  ")),
  layout_sidebar(
    sidebar = sidebar(
      width = 280,
      title = "Filter",
      selectInput("kreis_filter", "Kreis", choices = KREIS_CHOICES, selected = "all"),
      actionButton("refresh_ba", "Daten aktualisieren", class = "btn-sm btn-outline-secondary w-100"),
      tags$p(class = "ba-meta mb-0 mt-2", textOutput("ba_stand", inline = TRUE)),
      tags$p(
        class = "small text-muted mb-0 mt-2",
        "Quelle: Bundesagentur f\u00fcr Arbeit (STEA/BST). ",
        "Regional-Index = Nachfrageindikatoren pro 1.000 Besch\u00e4ftigte."
      )
    ),
    uiOutput("load_banner"),
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      mastr_kpi(
        "Nachfrage gesamt",
        textOutput("kpi_total_stellen", inline = TRUE),
        subtitle = "Th\u00fcringen (STEA)",
        color = "primary"
      ),
      mastr_kpi(
        "Dynamikquote",
        textOutput("kpi_avg_quote", inline = TRUE),
        subtitle = "Nachfrage / Besch\u00e4ftigung",
        color = "warning"
      ),
      mastr_kpi(
        "Top Kreis",
        textOutput("kpi_top_recruit", inline = TRUE),
        subtitle = "H\u00f6chster Regional-Index",
        color = "success"
      ),
      mastr_kpi(
        "Erfurt",
        textOutput("kpi_erfurt", inline = TRUE),
        subtitle = "Nachfrageindikator",
        color = "info"
      )
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        full_screen = TRUE,
        card_header("Top 8 \u2014 Nachfrageindikatoren"),
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
      card_header("Karte \u2014 Regional-Index nach Kreis"),
      card_body(
        padding = 0,
        div(class = "kreis-map", leafletOutput("map_index", height = "420px"))
      )
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  data_state <- reactiveValues(
    kreise = NULL,
    land = NULL,
    meta = NULL,
    error = NULL,
    loading = TRUE
  )

  apply_payload <- function(payload) {
    data_state$kreise <- payload$kreise
    data_state$land <- payload$land
    data_state$meta <- payload$meta
    data_state$error <- NULL
  }

  load_ba_data <- function(force = FALSE) {
    data_state$loading <- TRUE
    data_state$error <- NULL
    tryCatch({
      withProgress(message = "Lade BA-Daten\u2026", value = 0, {
        payload <- ba_cached_fachkraefte(
          force = force,
          progress = function(val, detail = NULL) {
            setProgress(min(0.95, 0.05 + 0.9 * val), detail = detail)
          }
        )
        setProgress(1, detail = "Fertig")
      })
      apply_payload(payload)
    }, error = function(e) {
      data_state$error <- conditionMessage(e)
    }, finally = {
      data_state$loading <- FALSE
    })
  }

  load_ba_data(force = FALSE)
  observeEvent(input$refresh_ba, load_ba_data(force = TRUE), ignoreInit = TRUE)

  output$load_banner <- renderUI({
    if (isTRUE(data_state$loading) && is.null(data_state$kreise)) {
      return(div(class = "alert alert-info py-2 small mb-2", "Lade Daten von der Bundesagentur f\u00fcr Arbeit\u2026"))
    }
    if (!is.null(data_state$error)) {
      return(div(
        class = "alert alert-warning py-2 small mb-2",
        "BA-Daten konnten nicht geladen werden: ", data_state$error
      ))
    }
    NULL
  })

  output$ba_stand <- renderText({
    if (is.null(data_state$meta)) {
      return("Stand: \u2013")
    }
    stea <- data_state$meta$stea_periode %||% "\u2013"
    bst <- data_state$meta$bst_periode %||% "\u2013"
    paste0("Stand Nachfrage: ", stea, " \u00b7 Besch\u00e4ftigung: ", bst)
  })

  filtered <- reactive({
    d <- data_state$kreise
    if (is.null(d)) {
      return(d)
    }
    if (!identical(input$kreis_filter, "all")) {
      d <- d[d$kreis == input$kreis_filter, , drop = FALSE]
    }
    d
  })

  output$kpi_total_stellen <- renderText({
    land <- data_state$land
    if (is.null(land) || is.na(land$offene_stellen)) {
      "\u2013"
    } else {
      fmt_num(land$offene_stellen, 0)
    }
  })

  output$kpi_avg_quote <- renderText({
    land <- data_state$land
    q <- if (!is.null(land)) land$quote_vakanz_pct else NA_real_
    if (is.null(q) || is.na(q)) {
      "\u2013"
    } else {
      paste0(fmt_num(q, 1), " %")
    }
  })

  output$kpi_top_recruit <- renderText({
    d <- data_state$kreise
    if (is.null(d) || !nrow(d)) {
      return("\u2013")
    }
    d <- d[!is.na(d$recruiting_index), , drop = FALSE]
    if (!nrow(d)) {
      return("\u2013")
    }
    top <- d[which.max(d$recruiting_index), , drop = FALSE]
    paste0(top$kreis[1], " \u00b7 ", fmt_num(top$recruiting_index[1], 1))
  })

  output$kpi_erfurt <- renderText({
    d <- data_state$kreise
    if (is.null(d) || !nrow(d)) {
      return("\u2013")
    }
    row <- d[grepl("^Erfurt", d$kreis), , drop = FALSE]
    if (!nrow(row) || is.na(row$offene_stellen[1])) {
      "\u2013"
    } else {
      fmt_num(row$offene_stellen[1], 0)
    }
  })

  output$plot_top8 <- renderPlot({
    d <- filtered()
    if (is.null(d) || !nrow(d)) {
      return(mastr_empty_plot("Keine Daten"))
    }
    d <- d |>
      arrange(desc(offene_stellen)) |>
      slice_head(n = 8) |>
      mutate(kreis = factor(kreis, levels = rev(kreis)))
    ggplot(d, aes(offene_stellen, kreis, fill = recruiting_index)) +
      geom_col(show.legend = FALSE, width = 0.75) +
      scale_fill_gradient(low = "#fde68a", high = ERWICON_PRIMARY) +
      scale_x_continuous(labels = label_number(big.mark = ".", decimal.mark = ",")) +
      labs(x = "Nachfrageindikatoren (STEA)", y = NULL) +
      theme_minimal(base_size = 11) +
      theme(panel.grid.major.y = element_blank())
  })

  output$tbl_kreise <- renderReactable({
    d <- filtered()
    if (is.null(d) || !nrow(d)) {
      return(reactable(data.frame(Hinweis = "Keine Daten"), compact = TRUE))
    }
    d <- d |>
      arrange(desc(recruiting_index)) |>
      transmute(
        Kreis = kreis,
        Beschaeftigte_Tsd = beschaeftigte_tausend,
        Nachfrageindikator = offene_stellen,
        `Dynamik %` = quote_vakanz_pct,
        `Nachfrage YoY %` = stellen_yoy_pct,
        `Regional-Index` = recruiting_index
      )
    reactable(
      d,
      defaultPageSize = 12,
      compact = TRUE,
      highlight = TRUE,
      columns = list(
        Beschaeftigte_Tsd = colDef(format = colFormat(separators = TRUE, digits = 1)),
        Nachfrageindikator = colDef(format = colFormat(separators = TRUE, digits = 0)),
        `Dynamik %` = colDef(format = colFormat(separators = TRUE, digits = 1)),
        `Nachfrage YoY %` = colDef(format = colFormat(separators = TRUE, digits = 0)),
        `Regional-Index` = colDef(format = colFormat(separators = TRUE, digits = 1))
      )
    )
  })

  output$map_index <- renderLeaflet({
    d <- filtered()
    if (is.null(d) || !nrow(d) || !all(c("lat", "lon") %in% names(d))) {
      return(
        leaflet() |>
          addProviderTiles("CartoDB.Positron") |>
          thueringen_set_view() |>
          addControl("Keine Kartendaten", position = "topright")
      )
    }
    d <- d[!is.na(d$lat) & !is.na(d$lon) & !is.na(d$recruiting_index), , drop = FALSE]
    if (!nrow(d)) {
      return(
        leaflet() |>
          addProviderTiles("CartoDB.Positron") |>
          thueringen_set_view() |>
          addControl("Keine Kartendaten", position = "topright")
      )
    }
    pal <- colorNumeric("YlOrRd", d$recruiting_index, na.color = "#94a3b8")
    leaflet(d) |>
      addProviderTiles("CartoDB.Positron") |>
      thueringen_set_view() |>
      addCircleMarkers(
        ~lon, ~lat,
        radius = ~sqrt(pmax(offene_stellen, 1)) * 0.08 + 6,
        stroke = TRUE, weight = 1, color = "#444",
        fillOpacity = 0.75, fillColor = ~pal(recruiting_index),
        label = ~kreis_leaflet_labels(
          data.frame(kreis = kreis, val = recruiting_index),
          "val", "%.1f", " /1.000 Besch."
        ),
        labelOptions = kreis_leaflet_label_opts()
      ) |>
      addLegend(
        "bottomright", pal = pal, values = ~recruiting_index,
        title = "Regional-Index"
      )
  })
}

shinyApp(ui, server)
