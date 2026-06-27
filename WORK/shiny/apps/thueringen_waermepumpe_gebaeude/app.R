# =============================================================================
# thueringen_waermepumpe_gebaeude — Gebäude-Energie nach Kreis / PLZ (MaStR proxy).
# erwicon connect 2026 · Demo 2/7.
# Proxy: Stromspeicher + Home-PV (<10 kW) + Biomasse (kein WP in MaStR).
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

YEAR_NOW <- as.integer(format(Sys.Date(), "%Y"))

build_plz_detail <- function(speicher_plz, solar_plz, bio_plz) {
  rename_units <- function(df, col) {
    if (!nrow(df)) {
      return(data.frame(plz = character(), units = numeric(), stringsAsFactors = FALSE))
    }
    out <- df[, c("plz", "units"), drop = FALSE]
    names(out)[2] <- col
    out
  }
  all_plz <- unique(c(
    speicher_plz$plz, solar_plz$plz, bio_plz$plz
  ))
  base <- data.frame(plz = all_plz, stringsAsFactors = FALSE)
  out <- base |>
    left_join(rename_units(speicher_plz, "speicher_units"), by = "plz") |>
    left_join(rename_units(solar_plz, "home_pv_units"), by = "plz") |>
    left_join(rename_units(bio_plz, "biomasse_units"), by = "plz") |>
    left_join(thueringen_plz_kreis(), by = "plz")
  for (col in c("speicher_units", "home_pv_units", "biomasse_units")) {
    out[[col]][is.na(out[[col]])] <- 0
  }
  out$units <- out$speicher_units + out$home_pv_units + out$biomasse_units
  out
}

merge_gebaeude_kreise <- function(plz_detail, meta = thueringen_kreis_meta()) {
  if (!nrow(plz_detail)) {
    return(data.frame(
      kreis = character(), speicher_units = numeric(), home_pv_units = numeric(),
      biomasse_units = numeric(), units = numeric(), einwohner = numeric(),
      per_1000 = numeric(), lat = numeric(), lon = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  agg <- plz_detail |>
    filter(!is.na(kreis)) |>
    group_by(kreis) |>
    summarise(
      speicher_units = sum(speicher_units, na.rm = TRUE),
      home_pv_units = sum(home_pv_units, na.rm = TRUE),
      biomasse_units = sum(biomasse_units, na.rm = TRUE),
      units = sum(units, na.rm = TRUE),
      .groups = "drop"
    ) |>
    left_join(meta, by = "kreis")
  agg$per_1000 <- ifelse(
    !is.na(agg$einwohner) & agg$einwohner > 0,
    agg$units / agg$einwohner * 1000,
    NA_real_
  )
  as.data.frame(agg)
}

apply_asset_filter <- function(df, types) {
  if (!nrow(df)) {
    return(df)
  }
  out <- df
  if (!"speicher" %in% types) {
    out$speicher_units <- 0
  }
  if (!"home_pv" %in% types) {
    out$home_pv_units <- 0
  }
  if (!"biomasse" %in% types) {
    out$biomasse_units <- 0
  }
  out$units <- out$speicher_units + out$home_pv_units + out$biomasse_units
  out
}

plz_choice_labels <- function(plz, kreis) {
  paste0(plz, " \u2014 ", kreis)
}

ui <- mastr_page(
  title = "Th\u00fcringen W\u00e4rmepumpen & Geb\u00e4ude-Energie",
  subtitle = "Geb\u00e4ude-Energie-Proxy nach Kreis & PLZ \u2014 Speicher, Home-PV & Biomasse (MaStR).",
  fluid = TRUE,
  primary = ERWICON_PRIMARY,
  footer = "thueringen",
  hub_back_label = "\u2190 Zur\u00fcck zum Hub",
  creator_qr_lang = "de",
  erwicon_banner_ui(
    "\u201eIn Ihrem Kreis \u2014 Nachfrage oder noch Beratungsl\u00fccke?\u201c",
    " Geben Sie PLZ oder Kreis ein \u2014 live aus dem Marktstammdatenregister."
  ),
  tags$style(HTML(".kreis-map { border-radius: 8px; min-height: 420px; }")),
  layout_sidebar(
    sidebar = sidebar(
      width = 300,
      title = "Filter",
      selectInput(
        "filter_kreis",
        "Kreis",
        choices = c("Alle Kreise" = ""),
        selected = ""
      ),
      selectizeInput(
        "filter_plz",
        "PLZ",
        choices = c("Alle PLZ" = ""),
        selected = "",
        options = list(
          placeholder = "PLZ suchen \u2026",
          maxOptions = 500
        )
      ),
      checkboxGroupInput(
        "asset_types",
        "Anlagen-Typen",
        choices = c(
          "Speicher" = "speicher",
          "Home-PV (<10 kW)" = "home_pv",
          "Biomasse" = "biomasse"
        ),
        selected = c("speicher", "home_pv", "biomasse")
      ),
      checkboxInput("only_active", "Nur aktive MaStR-Einheiten", TRUE),
      actionButton("reset_filters", "Filter zur\u00fccksetzen", class = "btn-sm btn-outline-secondary w-100 mt-1"),
      hr(),
      uiOutput("filter_summary"),
      hr(),
      uiOutput("load_status"),
      tags$p(
        class = "small text-muted mb-0",
        "Proxy statt W\u00e4rmepumpen: Batteriespeicher, PV &lt; 10 kW, Biomasse.",
        " Kreis-Zuordnung \u00fcber PLZ."
      )
    ),
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      mastr_kpi(
        "Speicher",
        textOutput("kpi_speicher", inline = TRUE),
        subtitle = textOutput("kpi_scope", inline = TRUE),
        color = "primary"
      ),
      mastr_kpi(
        "Home-PV",
        textOutput("kpi_home", inline = TRUE),
        subtitle = "Photovoltaik &lt; 10 kW",
        color = "warning"
      ),
      mastr_kpi(
        "Biomasse",
        textOutput("kpi_bio", inline = TRUE),
        subtitle = "Biomasse-Anlagen",
        color = "success"
      ),
      mastr_kpi(
        "Top-Kreis",
        textOutput("kpi_top", inline = TRUE),
        subtitle = "Anlagen / 1.000 EW",
        color = "info"
      )
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        full_screen = TRUE,
        card_header(textOutput("plot_top10_title", inline = TRUE)),
        card_body(plotOutput("plot_top10", height = "320px"))
      ),
      card(
        full_screen = TRUE,
        card_header("Monatlicher Speicher-Zubau (Th\u00fcringen gesamt)"),
        card_body(plotOutput("plot_zubau", height = "320px"))
      )
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        full_screen = TRUE,
        card_header("Karte \u2014 Proxy-Dichte / 1.000 EW"),
        card_body(
          padding = 0,
          div(class = "kreis-map", leafletOutput("map_kreise", height = "420px"))
        )
      ),
      card(
        full_screen = TRUE,
        card_header("Kreis-Tabelle"),
        card_body(reactableOutput("tbl_kreise", height = "420px"))
      )
    ),
    card(
      class = "mt-3",
      full_screen = TRUE,
      card_header(textOutput("tbl_plz_title", inline = TRUE)),
      card_body(reactableOutput("tbl_plz", height = "360px"))
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  data_loading <- reactiveVal(TRUE)
  data_err <- reactiveVal(NULL)
  th_data <- reactiveVal(NULL)

  load_mastr <- function() {
    data_loading(TRUE)
    data_err(NULL)
    active <- sql_active_mastr(input$only_active)
    out <- tryCatch({
      withProgress(message = "Lade MaStR Th\u00fcringen\u2026", value = 0, {
        incProgress(0.15, detail = "Speicher PLZ")
        speicher_plz <- mastr_query(sprintf("
          SELECT LPAD(CAST(Postleitzahl AS VARCHAR), 5, '0') AS plz,
            COUNT(*) AS units, 0.0 AS mw
          FROM stromspeicher
          WHERE Bundesland = '1415'
            AND Postleitzahl IS NOT NULL %s
          GROUP BY 1", active))
        incProgress(0.35, detail = "Home-PV PLZ")
        solar_plz <- mastr_query(sprintf("
          SELECT LPAD(CAST(Postleitzahl AS VARCHAR), 5, '0') AS plz,
            COUNT(*) AS units, SUM(Bruttoleistung) / 1000.0 AS mw
          FROM solar
          WHERE Bundesland = '1415'
            AND Bruttoleistung < 10
            AND Bruttoleistung IS NOT NULL
            AND Postleitzahl IS NOT NULL %s
          GROUP BY 1", active))
        incProgress(0.55, detail = "Biomasse PLZ")
        bio_plz <- mastr_query(sprintf("
          SELECT LPAD(CAST(Postleitzahl AS VARCHAR), 5, '0') AS plz,
            COUNT(*) AS units, SUM(Bruttoleistung) / 1000.0 AS mw
          FROM biomasse
          WHERE Bundesland = '1415'
            AND Postleitzahl IS NOT NULL %s
          GROUP BY 1", active))
        incProgress(0.75, detail = "Monats-Zubau Speicher")
        reg_col <- sql_reg_date("Registrierungsdatum")
        monthly <- mastr_query(sprintf("
          SELECT
            CAST(EXTRACT(YEAR FROM COALESCE(%1$s, Inbetriebnahmedatum)) AS INTEGER) AS year,
            CAST(EXTRACT(MONTH FROM COALESCE(%1$s, Inbetriebnahmedatum)) AS INTEGER) AS month,
            COUNT(*) AS units
          FROM stromspeicher
          WHERE Bundesland = '1415'
            AND COALESCE(%1$s, Inbetriebnahmedatum) IS NOT NULL
            AND EXTRACT(YEAR FROM COALESCE(%1$s, Inbetriebnahmedatum)) >= %2$d
            AND EXTRACT(YEAR FROM COALESCE(%1$s, Inbetriebnahmedatum)) <= %3$d
            %4$s
          GROUP BY 1, 2
          ORDER BY 1, 2",
          reg_col, YEAR_NOW - 4L, YEAR_NOW, active))
        incProgress(1, detail = "Fertig")
        plz_detail <- build_plz_detail(speicher_plz, solar_plz, bio_plz)
        list(
          plz_detail = plz_detail,
          kreis = merge_gebaeude_kreise(plz_detail),
          monthly = monthly
        )
      })
    }, error = function(e) {
      data_err(conditionMessage(e))
      NULL
    })
    th_data(out)
    data_loading(FALSE)
  }

  observeEvent(input$only_active, load_mastr(), ignoreInit = FALSE)

  observeEvent(input$reset_filters, {
    updateSelectInput(session, "filter_kreis", selected = "")
    updateSelectizeInput(session, "filter_plz", selected = "")
    updateCheckboxGroupInput(
      session, "asset_types",
      selected = c("speicher", "home_pv", "biomasse")
    )
  }, ignoreInit = TRUE)

  observe({
    req(d <- th_data())
    kreise <- sort(unique(d$plz_detail$kreis))
    kreise <- kreise[!is.na(kreise)]
    updateSelectInput(
      session, "filter_kreis",
      choices = c("Alle Kreise" = "", stats::setNames(kreise, kreise))
    )
  })

  observe({
    req(d <- th_data())
    pk <- d$plz_detail
    if (nzchar(input$filter_kreis)) {
      pk <- pk[pk$kreis == input$filter_kreis, , drop = FALSE]
    }
    pk <- pk[order(-pk$units, pk$plz), , drop = FALSE]
    plz_vals <- unique(pk$plz)
    if (!length(plz_vals)) {
      updateSelectizeInput(session, "filter_plz", choices = c("Alle PLZ" = ""), selected = "")
      return()
    }
    labels <- plz_choice_labels(pk$plz, pk$kreis)
    names(plz_vals) <- labels[match(plz_vals, pk$plz)]
    selected <- input$filter_plz
    if (!nzchar(selected) || !selected %in% plz_vals) {
      selected <- ""
    }
    updateSelectizeInput(
      session, "filter_plz",
      choices = c("Alle PLZ" = "", stats::setNames(plz_vals, names(plz_vals))),
      selected = selected
    )
  })

  observeEvent(input$filter_kreis, {
    req(th_data())
    if (!nzchar(input$filter_plz)) {
      return()
    }
    pk <- th_data()$plz_detail
    row <- pk[pk$plz == input$filter_plz, , drop = FALSE]
    if (!nrow(row) || (nzchar(input$filter_kreis) && row$kreis[1] != input$filter_kreis)) {
      updateSelectizeInput(session, "filter_plz", selected = "")
    }
  }, ignoreInit = TRUE)

  filtered_plz <- reactive({
    req(d <- th_data())
    types <- input$asset_types
    if (!length(types)) {
      types <- c("speicher", "home_pv", "biomasse")
    }
    plz <- apply_asset_filter(d$plz_detail, types)
    if (nzchar(input$filter_kreis)) {
      plz <- plz[plz$kreis == input$filter_kreis, , drop = FALSE]
    }
    if (nzchar(input$filter_plz)) {
      plz <- plz[plz$plz == input$filter_plz, , drop = FALSE]
    }
    plz
  })

  filtered_kreis <- reactive({
    merge_gebaeude_kreise(filtered_plz())
  })

  filter_scope_label <- reactive({
    if (nzchar(input$filter_plz)) {
      pk <- filtered_plz()
      if (nrow(pk)) {
        return(paste0("PLZ ", pk$plz[1], " \u00b7 ", pk$kreis[1]))
      }
    }
    if (nzchar(input$filter_kreis)) {
      return(input$filter_kreis)
    }
    "Th\u00fcringen gesamt"
  })

  output$filter_summary <- renderUI({
    tags$div(
      class = "small",
      tags$p(class = "mb-1 text-muted", "Aktiver Ausschnitt:"),
      tags$p(class = "mb-1 fw-semibold", filter_scope_label()),
      tags$p(class = "mb-0 text-muted", nrow(filtered_plz()), " PLZ im Filter")
    )
  })

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

  output$kpi_scope <- renderText({
    if (isTRUE(data_loading())) {
      return("\u2026")
    }
    filter_scope_label()
  })

  output$kpi_speicher <- renderText({
    if (isTRUE(data_loading()) || is.null(th_data())) {
      return("\u2026")
    }
    fmt_num(sum(filtered_plz()$speicher_units, na.rm = TRUE), 0)
  })

  output$kpi_home <- renderText({
    if (isTRUE(data_loading()) || is.null(th_data())) {
      return("\u2026")
    }
    fmt_num(sum(filtered_plz()$home_pv_units, na.rm = TRUE), 0)
  })

  output$kpi_bio <- renderText({
    if (isTRUE(data_loading()) || is.null(th_data())) {
      return("\u2026")
    }
    fmt_num(sum(filtered_plz()$biomasse_units, na.rm = TRUE), 0)
  })

  output$kpi_top <- renderText({
    if (isTRUE(data_loading()) || is.null(th_data())) {
      return("\u2026")
    }
    d <- filtered_kreis() |> filter(!is.na(per_1000), units > 0)
    if (!nrow(d)) {
      return("\u2013")
    }
    top <- d[which.max(d$per_1000), , drop = FALSE]
    paste0(top$kreis[1], " \u00b7 ", fmt_num(top$per_1000[1], 1))
  })

  output$plot_top10_title <- renderText({
    scope <- filter_scope_label()
    paste("Top 10 Kreise \u2014 Geb\u00e4ude-Energie / 1.000 EW", if (scope != "Th\u00fcringen gesamt") paste0("(", scope, ")"))
  })

  output$plot_top10 <- renderPlot({
    if (isTRUE(data_loading()) || is.null(th_data())) {
      return(mastr_empty_plot("Lade\u2026"))
    }
    d <- filtered_kreis() |>
      filter(!is.na(per_1000), units > 0) |>
      arrange(desc(per_1000)) |>
      slice_head(n = 10) |>
      mutate(kreis = factor(kreis, levels = rev(kreis)))
    if (!nrow(d)) {
      return(mastr_empty_plot("Keine Daten"))
    }
    ggplot(d, aes(per_1000, kreis, fill = per_1000)) +
      geom_col(show.legend = FALSE, width = 0.75) +
      scale_fill_gradient(low = "#fde68a", high = ERWICON_PRIMARY) +
      scale_x_continuous(labels = label_number(decimal.mark = ",", big.mark = ".")) +
      labs(x = "Proxy-Anlagen / 1.000 EW", y = NULL) +
      theme_minimal(base_size = 11) +
      theme(panel.grid.major.y = element_blank())
  })

  output$plot_zubau <- renderPlot({
    if (isTRUE(data_loading()) || is.null(th_data())) {
      return(mastr_empty_plot("Lade\u2026"))
    }
    d <- th_data()$monthly
    if (!nrow(d)) {
      return(mastr_empty_plot("Keine Daten"))
    }
    d <- d |>
      mutate(date = as.Date(sprintf("%04d-%02d-01", year, month)))
    ggplot(d, aes(date, units)) +
      geom_line(color = ERWICON_PRIMARY, linewidth = 0.9) +
      geom_point(color = ERWICON_PRIMARY, size = 1.8) +
      scale_x_date(date_labels = "%m.%Y", date_breaks = "6 months") +
      scale_y_continuous(labels = label_number(big.mark = ".", decimal.mark = ",")) +
      labs(
        x = NULL, y = "Neue Speicher (Anzahl)",
        caption = "Immer Th\u00fcringen gesamt \u2014 PLZ/Kreis-Filter gilt f\u00fcr KPIs & Karte"
      ) +
      theme_minimal(base_size = 11) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
  })

  output$tbl_kreise <- renderReactable({
    if (isTRUE(data_loading()) || is.null(th_data())) {
      return(reactable(data.frame(Info = "Lade\u2026")))
    }
    d <- filtered_kreis() |>
      filter(units > 0) |>
      arrange(desc(per_1000)) |>
      transmute(
        Kreis = kreis,
        Speicher = speicher_units,
        `Home-PV` = home_pv_units,
        Biomasse = biomasse_units,
        Gesamt = units,
        `/1.000 EW` = round(per_1000, 1)
      )
    reactable(
      d,
      defaultPageSize = 12,
      compact = TRUE,
      highlight = TRUE,
      columns = list(
        Speicher = colDef(format = colFormat(separators = TRUE, digits = 0)),
        `Home-PV` = colDef(format = colFormat(separators = TRUE, digits = 0)),
        Biomasse = colDef(format = colFormat(separators = TRUE, digits = 0)),
        Gesamt = colDef(format = colFormat(separators = TRUE, digits = 0)),
        `/1.000 EW` = colDef(format = colFormat(separators = TRUE, digits = 1))
      )
    )
  })

  output$tbl_plz_title <- renderText({
    n <- nrow(filtered_plz())
    paste0("PLZ-Detail (", n, " Postleitzahlen \u2014 sortiert nach Gesamt-Anlagen)")
  })

  output$tbl_plz <- renderReactable({
    if (isTRUE(data_loading()) || is.null(th_data())) {
      return(reactable(data.frame(Info = "Lade\u2026")))
    }
    d <- filtered_plz() |>
      filter(units > 0) |>
      arrange(desc(units), plz) |>
      transmute(
        PLZ = plz,
        Kreis = kreis,
        Speicher = speicher_units,
        `Home-PV` = home_pv_units,
        Biomasse = biomasse_units,
        Gesamt = units
      )
    if (!nrow(d)) {
      return(reactable(data.frame(Hinweis = "Keine Anlagen im gew\u00e4hlten Filter")))
    }
    reactable(
      d,
      defaultPageSize = 15,
      compact = TRUE,
      highlight = TRUE,
      searchable = TRUE,
      columns = list(
        PLZ = colDef(minWidth = 80),
        Speicher = colDef(format = colFormat(separators = TRUE, digits = 0)),
        `Home-PV` = colDef(format = colFormat(separators = TRUE, digits = 0)),
        Biomasse = colDef(format = colFormat(separators = TRUE, digits = 0)),
        Gesamt = colDef(format = colFormat(separators = TRUE, digits = 0))
      )
    )
  })

  output$map_kreise <- renderLeaflet({
    if (isTRUE(data_loading()) || is.null(th_data())) {
      return(
        leaflet() |>
          addProviderTiles("CartoDB.Positron") |>
          thueringen_set_view() |>
          addControl("Lade Kartendaten\u2026", position = "topright")
      )
    }
    d <- filtered_kreis()
    d <- d[!is.na(d$lat) & !is.na(d$lon) & !is.na(d$per_1000) & d$units > 0, , drop = FALSE]
    if (!nrow(d)) {
      return(
        leaflet() |>
          addProviderTiles("CartoDB.Positron") |>
          thueringen_set_view() |>
          addControl("Keine Kartendaten", position = "topright")
      )
    }
    pal <- colorNumeric("YlOrRd", d$per_1000, na.color = "#94a3b8")
    mp <- leaflet(d) |>
      addProviderTiles("CartoDB.Positron") |>
      thueringen_set_view() |>
      addCircleMarkers(
        ~lon, ~lat,
        radius = ~sqrt(units) * 0.4 + 6,
        stroke = TRUE, weight = 1, color = "#444",
        fillOpacity = 0.75, fillColor = ~pal(per_1000),
        label = ~kreis_leaflet_labels(
          data.frame(kreis = kreis, val = per_1000),
          "val", "%.1f", " /1.000 EW"
        ),
        labelOptions = kreis_leaflet_label_opts()
      ) |>
      addLegend("bottomright", pal = pal, values = ~per_1000, title = "/1.000 EW")
    if (nrow(d) == 1L) {
      mp <- mp |>
        setView(d$lon[1], d$lat[1], zoom = 10)
    } else if (nzchar(input$filter_kreis) && nrow(d) <= 3L) {
      mp <- mp |>
        fitBounds(
          lng1 = min(d$lon) - 0.15, lat1 = min(d$lat) - 0.1,
          lng2 = max(d$lon) + 0.15, lat2 = max(d$lat) + 0.1
        )
    }
    mp
  })
}

shinyApp(ui, server)
