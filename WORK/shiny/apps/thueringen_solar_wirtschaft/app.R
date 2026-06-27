# =============================================================================
# thueringen_solar_wirtschaft — MaStR solar snapshot for Thüringen (Bundesland
# 1415). Built for erwicon connect 2026 (23 June, Erfurt): Kreis ranking,
# Erfurt spotlight, monthly Zubau, segment split.
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

YEAR_NOW  <- as.integer(format(Sys.Date(), "%Y"))
MONTH_NOW <- as.integer(format(Sys.Date(), "%m"))
TH_POP    <- 2120000L  # Destatis ~2024 (Land)

ERWICON_PRIMARY <- "#6B1D3A"

PLZ_KREIS <- utils::read.csv(
  "data/plz_kreis_th.csv",
  stringsAsFactors = FALSE,
  fileEncoding = "UTF-8"
) |>
  mutate(plz = sprintf("%05d", as.integer(plz)))

KREIS_META <- utils::read.csv(
  "data/kreis_population_th.csv",
  stringsAsFactors = FALSE,
  fileEncoding = "UTF-8"
)

.kreis_rank_df <- function(plz_df) {
  empty <- tibble(
    kreis = character(), units = integer(), mw = numeric(),
    einwohner = numeric(), per_1000 = numeric(),
    lat = numeric(), lon = numeric()
  )
  if (!nrow(plz_df)) {
    return(empty)
  }
  plz_df |>
    mutate(plz = sprintf("%05d", as.integer(plz))) |>
    left_join(PLZ_KREIS, by = "plz") |>
    filter(!is.na(kreis)) |>
    group_by(kreis) |>
    summarise(
      units = sum(units, na.rm = TRUE),
      mw = sum(mw, na.rm = TRUE),
      .groups = "drop"
    ) |>
    left_join(KREIS_META, by = "kreis") |>
    mutate(
      einwohner = coalesce(einwohner, NA_real_),
      per_1000 = if_else(
        !is.na(einwohner) & einwohner > 0,
        units / einwohner * 1000,
        NA_real_
      )
    )
}

ui <- mastr_page(
  title = "Th\u00fcringen Solar-Wirtschaft",
  subtitle = "Live MaStR \u2014 Photovoltaik nach Kreis.",
  fluid = TRUE,
  primary = ERWICON_PRIMARY,
  footer = "thueringen",
  hub_back_label = "\u2190 Zur\u00fcck zum Hub",
  creator_qr_lang = "de",
  tags$style(HTML("
    .erwicon-banner {
      background: linear-gradient(90deg, #6B1D3A 0%, #8B2942 100%);
      color: #fff; border-radius: 8px; padding: 0.65rem 1rem; margin-bottom: 1rem;
    }
    .erwicon-banner a { color: #fde68a; }
    .kreis-map { border-radius: 8px; min-height: 420px; }
  ")),
  div(
    class = "erwicon-banner small",
    tags$strong("Wirtschaft weiterdenken."),
    " Photovoltaik-Ausbau im Freistaat \u2014 frischer als statische Atlanten, direkt aus dem Marktstammdatenregister."
  ),
  layout_sidebar(
    sidebar = sidebar(
      width = 280,
      title = "Filter",
      checkboxInput("only_active", "Nur aktive Einheiten (InBetrieb)", value = TRUE),
      sliderInput(
        "yr_from", "Zubau-Vergleich ab Jahr",
        min = 2018, max = YEAR_NOW - 1,
        value = max(2020, YEAR_NOW - 5),
        sep = "", step = 1
      ),
      tags$hr(),
      uiOutput("load_status")
    ),
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      mastr_kpi(
        "PV-Anlagen",
        textOutput("kpi_units", inline = TRUE),
        subtitle = "Th\u00fcringen gesamt",
        color = "primary"
      ),
      mastr_kpi(
        "Installierte Leistung",
        textOutput("kpi_mw", inline = TRUE),
        subtitle = "Brutto/DC",
        color = "success"
      ),
      mastr_kpi(
        sprintf("Zubau %d YTD", YEAR_NOW),
        textOutput("kpi_ytd", inline = TRUE),
        subtitle = sprintf("Jan\u2013%s", MONTHS_DE[MONTH_NOW]),
        color = "warning"
      ),
      mastr_kpi(
        "Anlagen / 1.000 EW",
        textOutput("kpi_density", inline = TRUE),
        subtitle = "~2,12 Mio. Einwohner",
        color = "info"
      )
    ),
    layout_columns(
      col_widths = c(4, 8),
      card(
        full_screen = TRUE,
        card_header("Erfurt \u2014 Landeshauptstadt"),
        card_body(uiOutput("erfurt_card"))
      ),
      card(
        full_screen = TRUE,
        card_header("Kreis-Ranking \u2014 Anlagen pro 1.000 Einwohner"),
        card_body(
          plotOutput("plot_kreis_rank", height = "320px"),
          p(class = "small text-muted mb-0",
            "Kreis-Zuordnung \u00fcber PLZ (GeoNames). Einwohner: Destatis / Kreis-Sch\u00e4tzung 2023.")
        )
      )
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        full_screen = TRUE,
        card_header("Monatlicher Zubau Th\u00fcringen (MW)"),
        card_body(
          uiOutput("zubau_header"),
          plotOutput("plot_zubau", height = "300px")
        )
      ),
      card(
        full_screen = TRUE,
        card_header("Segmente & Kreis-Tabelle"),
        card_body(
          plotOutput("plot_segments", height = "140px"),
          reactableOutput("tbl_kreise", height = "220px")
        )
      )
    ),
    card(
      full_screen = TRUE,
      card_header("Karte \u2014 installierte Leistung (MW) nach Kreis"),
      card_body(
        padding = 0,
        div(class = "kreis-map", leafletOutput("map_kreise", height = "420px"))
      )
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  data_loading <- reactiveVal(TRUE)
  data_err <- reactiveVal(NULL)
  th_data <- reactiveVal(NULL)

  load_thueringen <- function() {
    data_loading(TRUE)
    data_err(NULL)
    active <- if (isTRUE(input$only_active)) {
      "AND EinheitBetriebsstatus = 35"
    } else {
      ""
    }
    yr <- input$yr_from
    out <- tryCatch({
      withProgress(message = "Lade MaStR Th\u00fcringen\u2026", value = 0, {
        incProgress(0.1, detail = "KPIs")
        kpi <- mastr_query(sprintf("
          SELECT COUNT(*) AS units, SUM(Bruttoleistung) / 1000.0 AS mw
          FROM solar WHERE Bundesland = '1415' %s", active))
        incProgress(0.2, detail = "YTD")
        ytd <- mastr_query(sprintf("
          SELECT COUNT(*) AS units, SUM(Bruttoleistung) / 1000.0 AS mw
          FROM solar WHERE Bundesland = '1415'
            AND Inbetriebnahmedatum IS NOT NULL
            AND %s = %d AND %s <= %d %s",
          sql_ibn_year("Inbetriebnahmedatum"), YEAR_NOW,
          sql_ibn_month("Inbetriebnahmedatum"), MONTH_NOW, active))
        incProgress(0.4, detail = "PLZ / Kreise")
        plz <- mastr_query(sprintf("
          SELECT LPAD(CAST(Postleitzahl AS VARCHAR), 5, '0') AS plz,
            COUNT(*) AS units, SUM(Bruttoleistung) / 1000.0 AS mw
          FROM solar WHERE Bundesland = '1415' AND Postleitzahl IS NOT NULL %s
          GROUP BY 1", active))
        incProgress(0.6, detail = "Monats-Zubau")
        monthly <- mastr_query(sprintf("
          SELECT CAST(%s AS INTEGER) AS year, CAST(%s AS INTEGER) AS month,
            SUM(Bruttoleistung) / 1000.0 AS mw
          FROM solar WHERE Bundesland = '1415'
            AND Inbetriebnahmedatum IS NOT NULL AND Bruttoleistung IS NOT NULL
            AND %s >= %d AND %s <= %d %s
          GROUP BY 1, 2 ORDER BY 1, 2",
          sql_ibn_year("Inbetriebnahmedatum"),
          sql_ibn_month("Inbetriebnahmedatum"),
          sql_ibn_year("Inbetriebnahmedatum"), yr,
          sql_ibn_year("Inbetriebnahmedatum"), YEAR_NOW, active))
        incProgress(0.8, detail = "Segmente")
        segments <- mastr_query(sprintf("
          SELECT %s AS segment, COUNT(*) AS units,
            SUM(Bruttoleistung) / 1000.0 AS mw
          FROM solar WHERE Bundesland = '1415' %s
          GROUP BY 1 ORDER BY units DESC",
          sql_segment_3("Bruttoleistung"), active))
        incProgress(1, detail = "Fertig")
        list(
          kpi = kpi, ytd = ytd, plz = plz, monthly = monthly,
          segments = segments, kreis = .kreis_rank_df(plz)
        )
      })
    }, error = function(e) {
      data_err(conditionMessage(e))
      NULL
    })
    th_data(out)
    data_loading(FALSE)
  }

  observeEvent(list(input$only_active, input$yr_from), load_thueringen(), ignoreInit = FALSE)

  data_kpi <- reactive({
    req(d <- th_data())
    d$kpi
  })
  data_ytd <- reactive({ req(d <- th_data()); d$ytd })
  data_kreis <- reactive({ req(d <- th_data()); d$kreis })
  data_monthly <- reactive({ req(d <- th_data()); d$monthly })
  data_segments <- reactive({ req(d <- th_data()); d$segments })

  output$load_status <- renderUI({
    if (isTRUE(data_loading())) {
      return(tags$span(class = "text-muted small", "Lade MaStR-Daten \u2026"))
    }
    err <- data_err()
    if (!is.null(err)) {
      return(tags$span(class = "text-danger small", "Fehler: ", err))
    }
    tag <- tryCatch(mastr_release_info()$tag, error = function(e) "?")
    tags$span(
      class = "text-muted small",
      "Release: ", tags$code(tag)
    )
  })

  output$kpi_units <- renderText({
    if (isTRUE(data_loading()) || is.null(th_data())) {
      return("\u2026")
    }
    u <- data_kpi()$units[1]
    if (is.na(u)) "\u2013" else fmt_num(u, 0)
  })

  output$kpi_mw <- renderText({
    if (isTRUE(data_loading()) || is.null(th_data())) return("\u2026")
    mw <- data_kpi()$mw[1]
    if (is.na(mw)) "\u2013" else paste0(fmt_num(mw, 1), " MW")
  })

  output$kpi_ytd <- renderText({
    if (isTRUE(data_loading()) || is.null(th_data())) return("\u2026")
    d <- data_ytd()
    if (is.na(d$mw[1])) "\u2013" else paste0(fmt_num(d$mw[1], 1), " MW")
  })

  output$kpi_density <- renderText({
    if (isTRUE(data_loading()) || is.null(th_data())) return("\u2026")
    u <- data_kpi()$units[1]
    if (is.na(u)) "\u2013" else fmt_num(u / TH_POP * 1000, 1)
  })

  output$erfurt_card <- renderUI({
    erf <- data_kreis() |>
      filter(grepl("^Erfurt", kreis))
    if (!nrow(erf)) {
      return(p(class = "text-muted", "Keine Erfurt-Daten (PLZ-Mapping pr\u00fcfen)."))
    }
    row <- erf[1, ]
    rank <- data_kreis() |>
      filter(!is.na(per_1000)) |>
      arrange(desc(per_1000)) |>
      mutate(r = row_number()) |>
      filter(grepl("^Erfurt", kreis)) |>
      pull(r)
    tagList(
      div(class = "h4 mb-2", fmt_num(row$units, 0), tags$span(class = "small text-muted", " Anlagen")),
      div(class = "mb-1", tags$strong(fmt_num(row$mw, 1)), " MW installiert"),
      div(class = "mb-1",
          tags$strong(fmt_num(row$per_1000, 1)),
          " Anlagen / 1.000 EW",
          if (length(rank)) tags$span(class = "badge bg-secondary ms-1", paste0("#", rank, " im Land"))),
      p(class = "small text-muted mb-0",
        "Erfurt z\u00e4hlt zu den PV-st\u00e4rksten Kreisen \u2014 relevant f\u00fcr Gewerbe- und Kommunalfl\u00e4chen vor Ort.")
    )
  })

  output$zubau_header <- renderUI({
    tags$p(
      class = "small text-muted mb-2",
      sprintf("Brutto/DC-Leistung (MW) pro Inbetriebnahme-Monat \u2014 %d bis %d", input$yr_from, YEAR_NOW)
    )
  })

  output$plot_kreis_rank <- renderPlot({
    d <- data_kreis() |>
      filter(!is.na(per_1000)) |>
      arrange(per_1000) |>
      mutate(kreis = factor(kreis, levels = kreis))
    if (!nrow(d)) {
      return(ggplot() +
        annotate("text", x = 0.5, y = 0.5, label = "Keine Daten") +
        theme_void())
    }
    ggplot(d, aes(per_1000, kreis, fill = per_1000)) +
      geom_col(show.legend = FALSE, width = 0.75) +
      scale_fill_gradient(low = "#fde68a", high = ERWICON_PRIMARY) +
      scale_x_continuous(labels = label_number(decimal.mark = ",", big.mark = ".")) +
      labs(x = "Anlagen pro 1.000 Einwohner", y = NULL) +
      theme_minimal(base_size = 11) +
      theme(panel.grid.major.y = element_blank())
  })

  output$plot_zubau <- renderPlot({
    d <- data_monthly()
    if (!nrow(d)) {
      return(ggplot() +
        annotate("text", x = 0.5, y = 0.5, label = "Keine Daten") +
        theme_void())
    }
    d <- d |>
      mutate(
        label = paste0(sprintf("%02d", month), ".", year),
        ord = year * 100L + month
      )
    yrs <- sort(unique(d$year))
    pal <- setNames(
      colorRampPalette(c("#cbd5e1", ERWICON_PRIMARY))(length(yrs)),
      as.character(yrs)
    )
    tick_n <- min(12L, nrow(d))
    tick_idx <- unique(as.integer(round(seq(1, nrow(d), length.out = tick_n))))
    ggplot(d, aes(ord, mw, fill = factor(year))) +
      geom_col(width = 0.85) +
      scale_fill_manual(values = pal, name = "Jahr") +
      scale_x_continuous(
        breaks = d$ord[tick_idx],
        labels = d$label[tick_idx]
      ) +
      labs(x = NULL, y = "MW") +
      theme_minimal(base_size = 11) +
      theme(legend.position = "top", axis.text.x = element_text(angle = 45, hjust = 1))
  })

  output$plot_segments <- renderPlot({
    d <- data_segments()
    if (!nrow(d)) {
      return(ggplot() + theme_void())
    }
    d$segment <- factor(d$segment, levels = c("Home", "C&I", "Large Scale"))
    ggplot(d, aes(segment, mw, fill = segment)) +
      geom_col(show.legend = FALSE, width = 0.65) +
      scale_fill_manual(values = c("Home" = "#fde68a", "C&I" = ERWICON_PRIMARY, "Large Scale" = "#1e293b")) +
      labs(x = NULL, y = "MW") +
      theme_minimal(base_size = 11)
  })

  output$tbl_kreise <- renderReactable({
    d <- data_kreis() |>
      arrange(desc(mw)) |>
      transmute(
        Kreis = kreis,
        Anlagen = units,
        `MW` = round(mw, 1),
        `/1.000 EW` = round(per_1000, 1)
      )
    reactable(
      d,
      defaultPageSize = 10,
      compact = TRUE,
      highlight = TRUE,
      columns = list(
        Anlagen = colDef(format = colFormat(separators = TRUE, digits = 0)),
        MW = colDef(format = colFormat(separators = TRUE, digits = 1)),
        `/1.000 EW` = colDef(format = colFormat(separators = TRUE, digits = 1))
      )
    )
  })

  output$map_kreise <- renderLeaflet({
    if (isTRUE(data_loading()) || is.null(th_data())) {
      return(leaflet() |>
        addProviderTiles("CartoDB.Positron") |>
        thueringen_set_view() |>
        addControl("Lade Kartendaten\u2026", position = "topright"))
    }
    d <- data_kreis()
    if (!nrow(d) || !all(c("lat", "lon") %in% names(d))) {
      return(leaflet() |>
        addProviderTiles("CartoDB.Positron") |>
        thueringen_set_view() |>
        addControl("Keine Kartendaten", position = "topright"))
    }
    d <- d[!is.na(d$lat) & !is.na(d$lon) & d$mw > 0, , drop = FALSE]
    if (!nrow(d)) {
      return(leaflet() |>
        addProviderTiles("CartoDB.Positron") |>
        thueringen_set_view() |>
        addControl("Keine Kartendaten", position = "topright"))
    }
    pal <- colorNumeric("YlOrRd", d$mw, na.color = "#94a3b8")
    leaflet(d) |>
      addProviderTiles("CartoDB.Positron") |>
      thueringen_set_view() |>
      addCircleMarkers(
        ~lon, ~lat,
        radius = ~sqrt(mw) * 2.5,
        stroke = TRUE, weight = 1, color = "#444",
        fillOpacity = 0.75, fillColor = ~pal(mw),
        label = ~paste0(
          kreis, " \u00b7 ",
          format(units, big.mark = ".", decimal.mark = ","), " Anlagen \u00b7 ",
          format(round(mw, 1), decimal.mark = ","), " MW"
        ),
        labelOptions = kreis_leaflet_label_opts()
      ) |>
      addLegend("bottomright", pal = pal, values = ~mw, title = "MW")
  })
}

shinyApp(ui, server)
