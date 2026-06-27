# =============================================================================
# thueringen_kommunal — Kommunal & Infrastruktur (MaStR Großsolar, Speicher, Wind).
# erwicon connect 2026 · Demo 6/7.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(leaflet)
  library(reactable)
  library(scales)
})

source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")
source("../../R/thueringen_helpers.R")

merge_kreis_assets <- function(solar_k, storage_k, wind_k, meta = thueringen_kreis_meta()) {
  all_k <- unique(c(
    solar_k$kreis, storage_k$kreis, wind_k$kreis, meta$kreis
  ))
  base <- data.frame(kreis = all_k, stringsAsFactors = FALSE)
  pick <- function(df, prefix) {
    ucol <- paste0(prefix, "_units")
    mcol <- paste0(prefix, "_mw")
    if (!nrow(df)) {
      return(data.frame(
        kreis = character(),
        units = numeric(),
        mw = numeric(),
        stringsAsFactors = FALSE
      ))
    }
    out <- data.frame(
      kreis = df$kreis,
      units = df$units,
      mw = df$mw,
      stringsAsFactors = FALSE
    )
    names(out)[2:3] <- c(ucol, mcol)
    out
  }
  s <- pick(solar_k, "solar")
  st <- pick(storage_k, "storage")
  w <- pick(wind_k, "wind")
  out <- base |>
    left_join(s, by = "kreis") |>
    left_join(st, by = "kreis") |>
    left_join(w, by = "kreis") |>
    left_join(meta, by = "kreis")
  for (col in c("solar_units", "solar_mw", "storage_units", "storage_mw",
                "wind_units", "wind_mw")) {
    if (!col %in% names(out)) {
      out[[col]] <- 0
    }
    out[[col]][is.na(out[[col]])] <- 0
  }
  out$total_mw <- out$solar_mw + out$storage_mw + out$wind_mw
  out$total_units <- out$solar_units + out$storage_units + out$wind_units
  out
}

ui <- mastr_page(
  title = "Th\u00fcringen Kommunal & Infrastruktur",
  subtitle = "Gro\u00dfsolar (\u2265100 kW), Speicher & Wind nach Kreis \u2014 MaStR live.",
  fluid = TRUE,
  primary = ERWICON_PRIMARY,
  footer = "thueringen",
  hub_back_label = "\u2190 Zur\u00fcck zum Hub",
  creator_qr_lang = "de",
  erwicon_banner_ui(
    "\u201eWas ist Ihr n\u00e4chstes sichtbares Energie-Projekt in der Region?\u201c",
    " Kommunale Skala ab 100 kW PV, Batteriespeicher und Wind per PLZ\u2192Kreis."
  ),
  tags$style(HTML(".kreis-map { border-radius: 8px; min-height: 420px; }")),
  layout_sidebar(
    sidebar = sidebar(
      width = 280,
      title = "Filter",
      checkboxInput("only_active", "Nur aktive MaStR-Einheiten", TRUE),
      hr(),
      uiOutput("load_status")
    ),
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      mastr_kpi(
        "Gro\u00dfsolar",
        textOutput("kpi_solar_mw", inline = TRUE),
        subtitle = "\u2265 100 kW installiert",
        color = "warning"
      ),
      mastr_kpi(
        "Speicher",
        textOutput("kpi_storage", inline = TRUE),
        subtitle = "Anlagen (Stromspeicher)",
        color = "success"
      ),
      mastr_kpi(
        "Wind",
        textOutput("kpi_wind", inline = TRUE),
        subtitle = "Anlagen Onshore",
        color = "info"
      ),
      mastr_kpi(
        "Top-Kreis",
        textOutput("kpi_top_kreis", inline = TRUE),
        subtitle = "MW gesamt (alle Technologien)",
        color = "primary"
      )
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        full_screen = TRUE,
        card_header("Top 10 Kreise \u2014 Anlagen nach Technologie"),
        card_body(plotOutput("plot_stacked", height = "360px"))
      ),
      card(
        full_screen = TRUE,
        card_header("Kreis-Tabelle"),
        card_body(reactableOutput("tbl_kreise", height = "360px"))
      )
    ),
    card(
      full_screen = TRUE,
      card_header("Karte \u2014 installierte Leistung (MW) nach Kreis"),
      card_body(
        padding = 0,
        div(class = "kreis-map", leafletOutput("map_mw", height = "420px"))
      )
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  data_loading <- reactiveVal(TRUE)
  data_err <- reactiveVal(NULL)
  kreis_data <- reactiveVal(NULL)

  load_mastr <- function() {
    data_loading(TRUE)
    data_err(NULL)
    active <- sql_active_mastr(input$only_active)
    out <- tryCatch({
      withProgress(message = "Lade MaStR Th\u00fcringen\u2026", value = 0, {
        incProgress(0.15, detail = "Gro\u00dfsolar")
        solar_plz <- mastr_query(sprintf("
          SELECT LPAD(CAST(Postleitzahl AS VARCHAR), 5, '0') AS plz,
            COUNT(*) AS units, SUM(Bruttoleistung) / 1000.0 AS mw
          FROM solar
          WHERE Bundesland = '1415'
            AND Bruttoleistung >= 100
            AND Postleitzahl IS NOT NULL %s
          GROUP BY 1", active))
        incProgress(0.45, detail = "Speicher")
        storage_plz <- mastr_query(sprintf("
          SELECT LPAD(CAST(Postleitzahl AS VARCHAR), 5, '0') AS plz,
            COUNT(*) AS units,
            SUM(TRY_CAST(Bruttoleistung AS DOUBLE)) / 1000.0 AS mw
          FROM stromspeicher
          WHERE Bundesland = '1415'
            AND Postleitzahl IS NOT NULL %s
          GROUP BY 1", active))
        incProgress(0.75, detail = "Wind")
        wind_plz <- mastr_query(sprintf("
          SELECT LPAD(CAST(Postleitzahl AS VARCHAR), 5, '0') AS plz,
            COUNT(*) AS units, SUM(Bruttoleistung) / 1000.0 AS mw
          FROM wind
          WHERE Bundesland = '1415'
            AND Postleitzahl IS NOT NULL
            %s %s
          GROUP BY 1", sql_wind_onshore_raw(), active))
        incProgress(1, detail = "Fertig")
        merge_kreis_assets(
          kreis_from_plz(solar_plz),
          kreis_from_plz(storage_plz),
          kreis_from_plz(wind_plz)
        )
      })
    }, error = function(e) {
      data_err(conditionMessage(e))
      NULL
    })
    kreis_data(out)
    data_loading(FALSE)
  }

  observeEvent(input$only_active, load_mastr(), ignoreInit = FALSE)

  output$load_status <- renderUI({
    if (isTRUE(data_loading())) {
      return(tags$span(class = "text-muted small", "Lade MaStR-Daten \u2026"))
    }
    err <- data_err()
    if (!is.null(err)) {
      return(tags$span(class = "text-danger small", "Fehler: ", err))
    }
    tag <- tryCatch(mastr_release_info()$tag, error = function(e) "?")
    tags$span(class = "text-muted small", "MaStR Release: ", tags$code(tag))
  })

  output$kpi_solar_mw <- renderText({
    if (isTRUE(data_loading()) || is.null(kreis_data())) return("\u2026")
    mw <- sum(kreis_data()$solar_mw, na.rm = TRUE)
    paste0(fmt_num(mw, 1), " MW")
  })

  output$kpi_storage <- renderText({
    if (isTRUE(data_loading()) || is.null(kreis_data())) return("\u2026")
    fmt_num(sum(kreis_data()$storage_units, na.rm = TRUE), 0)
  })

  output$kpi_wind <- renderText({
    if (isTRUE(data_loading()) || is.null(kreis_data())) return("\u2026")
    fmt_num(sum(kreis_data()$wind_units, na.rm = TRUE), 0)
  })

  output$kpi_top_kreis <- renderText({
    if (isTRUE(data_loading()) || is.null(kreis_data())) return("\u2026")
    d <- kreis_data()
    if (!nrow(d) || max(d$total_mw, na.rm = TRUE) <= 0) return("\u2013")
    top <- d[which.max(d$total_mw), , drop = FALSE]
    paste0(top$kreis[1], " \u00b7 ", fmt_num(top$total_mw[1], 1), " MW")
  })

  output$plot_stacked <- renderPlot({
    err <- data_err()
    if (!is.null(err)) {
      return(mastr_empty_plot("Fehler beim Laden"))
    }
    if (isTRUE(data_loading()) || is.null(kreis_data())) {
      return(mastr_empty_plot("Lade\u2026"))
    }
    d <- kreis_data() |>
      arrange(desc(total_units)) |>
      slice_head(n = 10) |>
      mutate(kreis = factor(kreis, levels = rev(kreis)))
    if (!nrow(d)) {
      return(mastr_empty_plot("Keine Daten"))
    }
    long <- d |>
      transmute(
        kreis,
        Solar = solar_units,
        Speicher = storage_units,
        Wind = wind_units
      ) |>
      pivot_longer(-kreis, names_to = "tech", values_to = "units")
    ggplot(long, aes(units, kreis, fill = tech)) +
      geom_col(position = "stack", width = 0.75) +
      scale_fill_manual(
        values = c("Solar" = "#f59e0b", "Speicher" = ERWICON_PRIMARY, "Wind" = "#0ea5e9")
      ) +
      scale_x_continuous(labels = label_number(big.mark = ".", decimal.mark = ",")) +
      labs(x = "Anlagen", y = NULL, fill = NULL) +
      theme_minimal(base_size = 11) +
      theme(panel.grid.major.y = element_blank(), legend.position = "top")
  })

  output$tbl_kreise <- renderReactable({
    err <- data_err()
    if (!is.null(err)) {
      return(reactable(data.frame(Info = paste0("Fehler: ", err))))
    }
    if (isTRUE(data_loading()) || is.null(kreis_data())) {
      return(reactable(data.frame(Info = "Lade\u2026")))
    }
    d <- kreis_data() |>
      arrange(desc(total_mw)) |>
      transmute(
        Kreis = kreis,
        `Solar MW` = round(solar_mw, 1),
        `Speicher` = storage_units,
        `Wind` = wind_units,
        `MW gesamt` = round(total_mw, 1)
      )
    reactable(
      d,
      defaultPageSize = 12,
      compact = TRUE,
      highlight = TRUE,
      columns = list(
        `Solar MW` = colDef(format = colFormat(separators = TRUE, digits = 1)),
        Speicher = colDef(format = colFormat(separators = TRUE, digits = 0)),
        Wind = colDef(format = colFormat(separators = TRUE, digits = 0)),
        `MW gesamt` = colDef(format = colFormat(separators = TRUE, digits = 1))
      )
    )
  })

  output$map_mw <- renderLeaflet({
    err <- data_err()
    if (!is.null(err)) {
      return(
        leaflet() |>
          addProviderTiles("CartoDB.Positron") |>
          thueringen_set_view() |>
          addControl(paste0("Fehler: ", err), position = "topright")
      )
    }
    if (isTRUE(data_loading()) || is.null(kreis_data())) {
      return(
        leaflet() |>
          addProviderTiles("CartoDB.Positron") |>
          thueringen_set_view() |>
          addControl("Lade Kartendaten\u2026", position = "topright")
      )
    }
    d <- kreis_data()
    d <- d[!is.na(d$lat) & !is.na(d$lon) & d$total_mw > 0, , drop = FALSE]
    if (!nrow(d)) {
      return(
        leaflet() |>
          addProviderTiles("CartoDB.Positron") |>
          thueringen_set_view() |>
          addControl("Keine Kartendaten", position = "topright")
      )
    }
    pal <- colorNumeric("YlOrRd", d$total_mw, na.color = "#94a3b8")
    leaflet(d) |>
      addProviderTiles("CartoDB.Positron") |>
      thueringen_set_view() |>
      addCircleMarkers(
        ~lon, ~lat,
        radius = ~sqrt(total_mw) * 2.5,
        stroke = TRUE, weight = 1, color = "#444",
        fillOpacity = 0.75, fillColor = ~pal(total_mw),
        label = ~paste0(
          kreis, " \u00b7 ",
          format(round(total_mw, 1), decimal.mark = ","), " MW gesamt"
        ),
        labelOptions = kreis_leaflet_label_opts()
      ) |>
      addLegend("bottomright", pal = pal, values = ~total_mw, title = "MW")
  })
}

shinyApp(ui, server)
