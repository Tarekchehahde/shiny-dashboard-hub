# =============================================================================
# thueringen_gewerbe_strom — Strompreise + Gewerbe-/Industrie-Energie in Thüringen.
# erwicon connect 2026 · Demo 1/7 for business audience.
# Price: Energy-Charts (DE-LU). Assets: MaStR solar C&I/Large + batteries.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(ggplot2)
  library(plotly)
  library(jsonlite)
  library(httr2)
  library(tibble)
})

source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")

`%||%` <- function(x, y) if (is.null(x)) y else x

ERWICON_PRIMARY <- "#6B1D3A"
AUTO_REFRESH_MS <- 900000L
BH_START <- 7L
BH_END <- 18L
MAX_PRICE_DAYS <- 31L
TZ_BERLIN <- "Europe/Berlin"

parse_price_body <- function(body) {
  if (is.null(body$price) || !length(body$price)) {
    return(NULL)
  }
  ts <- as.POSIXct(body$unix_seconds, origin = "1970-01-01", tz = TZ_BERLIN)
  tibble(
    ts = ts,
    hour = as.integer(format(ts, "%H")),
    price = as.numeric(body$price),
    business_hour = as.integer(format(ts, "%H")) >= BH_START &
      as.integer(format(ts, "%H")) <= BH_END
  )
}

fetch_energy_charts_prices <- function(start = NULL, end = NULL) {
  url <- "https://api.energy-charts.info/price?bzn=DE-LU"
  if (!is.null(start)) {
    url <- paste0(url, "&start=", format(as.Date(start), "%Y-%m-%d"))
  }
  if (!is.null(end)) {
    url <- paste0(url, "&end=", format(as.Date(end), "%Y-%m-%d"))
  }
  tryCatch({
    resp <- httr2::request(url) |>
      httr2::req_timeout(45) |>
      httr2::req_retry(max_tries = 3, backoff = ~1) |>
      httr2::req_perform()
    body <- jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = TRUE)
    parse_price_body(body)
  }, error = function(e) NULL)
}

sql_active_solar <- function(active = TRUE) {
  if (!isTRUE(active)) {
    return("")
  }
  # Remote MaStR parquet stores Betriebsstatus as numeric code 35 (= InBetrieb).
  "AND EinheitBetriebsstatus = 35"
}

clamp_price_range <- function(start, end, today = Sys.Date()) {
  start <- as.Date(start)
  end <- as.Date(end)
  if (is.na(start) || is.na(end)) {
    return(c(today - 6L, today))
  }
  if (end < start) {
    end <- start
  }
  max_end <- today + 1L
  if (end > max_end) {
    end <- max_end
  }
  if (as.integer(end - start) + 1L > MAX_PRICE_DAYS) {
    start <- end - (MAX_PRICE_DAYS - 1L)
  }
  c(start, end)
}

ui <- mastr_page(
  title = "Th\u00fcringen Gewerbe-Strom",
  subtitle = "Day-Ahead-Strompreis & industrielle Energie im Freistaat.",
  fluid = TRUE,
  primary = ERWICON_PRIMARY,
  footer = "thueringen_gewerbe",
  hub_back_label = "\u2190 Zur\u00fcck zum Hub",
  creator_qr_lang = "de",
  tags$style(HTML("
    .erwicon-banner {
      background: linear-gradient(90deg, #6B1D3A 0%, #8B2942 100%);
      color: #fff; border-radius: 8px; padding: 0.65rem 1rem; margin-bottom: 1rem;
    }
    .preset-btns .btn { font-size: 0.78rem; padding: 0.2rem 0.45rem; }
  ")),
  div(
    class = "erwicon-banner small",
    tags$strong("Gespr\u00e4chsstarter:"),
    " \u201eWann ist Ihr Strom am teuersten \u2014 und was machen Sie dann?\u201c",
    " PV, Speicher und Lastverschiebung im Blick."
  ),
  layout_sidebar(
    sidebar = sidebar(
      width = 300,
      title = "Filter",
      tags$p(class = "small fw-semibold mb-1", "Strompreis-Verlauf"),
      dateRangeInput(
        "price_range",
        NULL,
        start = Sys.Date() - 6L,
        end = Sys.Date(),
        max = Sys.Date() + 1L,
        min = Sys.Date() - 365L,
        format = "dd.mm.yyyy",
        separator = " \u2013 ",
        language = "de",
        weekstart = 1
      ),
      div(
        class = "preset-btns d-flex flex-wrap gap-1 mb-2",
        actionButton("preset_7d", "7 Tage", class = "btn-sm btn-outline-secondary"),
        actionButton("preset_30d", "30 Tage", class = "btn-sm btn-outline-secondary"),
        actionButton("preset_today", "Heute", class = "btn-sm btn-outline-secondary")
      ),
      tags$p(class = "small text-muted mb-3",
             "Bis ", MAX_PRICE_DAYS, " Tage, st\u00fcndliche Aufl\u00f6sung. ",
             "Chart zoomen, schwenken und mit der Zeitleiste navigieren."),
      checkboxInput("only_active", "Nur aktive MaStR-Einheiten", TRUE),
      checkboxInput("highlight_bh", "Gesch\u00e4ftszeiten hervorheben (07\u201318 Uhr)", TRUE),
      actionButton("refresh", "Aktualisieren", class = "btn-sm btn-warning w-100"),
      hr(),
      uiOutput("load_status"),
      hr(),
      tags$p(class = "small text-muted mb-0",
             "Strompreis: Fraunhofer Energy-Charts (B\u00f6rse DE-LU).",
             " Anlagen: BNetzA MaStR, Bundesland Th\u00fcringen (1415).")
    ),
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      mastr_kpi("Strompreis jetzt", textOutput("kpi_now", inline = TRUE),
                subtitle = "DE-LU / EUR pro MWh", color = "danger"),
      mastr_kpi("Heute min / max", textOutput("kpi_range", inline = TRUE),
                subtitle = "Day-Ahead heute", color = "warning"),
      mastr_kpi("Gewerbe PV (C&I)", textOutput("kpi_ci", inline = TRUE),
                subtitle = "10 kW \u2013 < 1 MW", color = "success"),
      mastr_kpi("Industrie-PV", textOutput("kpi_large", inline = TRUE),
                subtitle = "\u2265 1 MW + Speicher MW", color = "primary")
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        full_screen = TRUE,
        card_header(
          "Strompreis-Verlauf (DE-LU)",
          tags$span(class = "text-muted small ms-2", textOutput("price_range_label", inline = TRUE))
        ),
        card_body(plotlyOutput("plot_prices", height = "420px"))
      ),
      card(
        full_screen = TRUE,
        card_header("Energie-Anlagen Th\u00fcringen (MaStR)"),
        card_body(
          plotOutput("plot_segments", height = "200px"),
          tableOutput("tbl_assets")
        )
      )
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  prices_today <- reactiveVal(NULL)
  prices_series <- reactiveVal(NULL)
  mastr_data <- reactiveVal(NULL)
  data_loading <- reactiveVal(TRUE)
  price_loading <- reactiveVal(TRUE)
  data_err <- reactiveVal(NULL)
  price_err <- reactiveVal(NULL)

  price_range <- reactive({
    clamp_price_range(input$price_range[1], input$price_range[2])
  })

  observeEvent(price_range(), {
    rng <- price_range()
    if (!identical(as.Date(input$price_range[1]), rng[1]) ||
        !identical(as.Date(input$price_range[2]), rng[2])) {
      updateDateRangeInput(session, "price_range", start = rng[1], end = rng[2])
    }
  }, ignoreInit = TRUE)

  set_price_range <- function(start, end) {
    rng <- clamp_price_range(start, end)
    updateDateRangeInput(session, "price_range", start = rng[1], end = rng[2])
  }

  observeEvent(input$preset_7d, set_price_range(Sys.Date() - 6L, Sys.Date()), ignoreInit = TRUE)
  observeEvent(input$preset_30d, set_price_range(Sys.Date() - 29L, Sys.Date()), ignoreInit = TRUE)
  observeEvent(input$preset_today, set_price_range(Sys.Date(), Sys.Date()), ignoreInit = TRUE)

  load_lock <- reactiveVal(FALSE)

  run_exclusive <- function(label, expr) {
    if (isTRUE(load_lock())) {
      return(invisible(NULL))
    }
    load_lock(TRUE)
    on.exit(load_lock(FALSE), add = TRUE)
    force(expr)
  }

  load_prices <- function() {
    run_exclusive("prices", {
      price_loading(TRUE)
      price_err(NULL)
      rng <- price_range()
      series <- fetch_energy_charts_prices(rng[1], rng[2])
      today <- fetch_energy_charts_prices()
      if ((is.null(today) || !nrow(today)) && !is.null(series) && nrow(series)) {
        today <- series[as.Date(series$ts, tz = TZ_BERLIN) == Sys.Date(), , drop = FALSE]
      }
      errs <- character()
      if (is.null(series) || !nrow(series)) {
        errs <- c(errs, "Energy-Charts: keine Preisdaten f\u00fcr den Zeitraum")
      }
      if (is.null(today) || !nrow(today)) {
        errs <- c(errs, "Energy-Charts: keine Tagespreise")
      }
      if (length(errs)) {
        price_err(paste(errs, collapse = " \u00b7 "))
      } else {
        price_err(NULL)
      }
      prices_series(series)
      prices_today(today)
      price_loading(FALSE)
    })
  }

  load_mastr <- function() {
    run_exclusive("mastr", {
      data_loading(TRUE)
      data_err(NULL)
      active <- sql_active_solar(input$only_active)
      out <- tryCatch({
        seg <- mastr_query(sprintf("
          SELECT
            %s AS segment,
            COUNT(*) AS units,
            SUM(Bruttoleistung) / 1000.0 AS mw
          FROM solar
          WHERE Bundesland = '1415'
            AND Bruttoleistung >= 10
            %s
          GROUP BY 1", sql_segment_3("Bruttoleistung"), active))
        stor <- mastr_query("
          SELECT COUNT(*) AS units,
            SUM(TRY_CAST(Bruttoleistung AS DOUBLE)) / 1000.0 AS mw
          FROM stromspeicher
          WHERE Bundesland = '1415'")
        list(segments = seg, storage = stor)
      }, error = function(e) {
        data_err(conditionMessage(e))
        NULL
      })
      mastr_data(out)
      data_loading(FALSE)
    })
  }

  load_all <- function() {
    run_exclusive("all", {
      price_loading(TRUE)
      data_loading(TRUE)
      price_err(NULL)
      data_err(NULL)
      rng <- price_range()
      series <- fetch_energy_charts_prices(rng[1], rng[2])
      today <- fetch_energy_charts_prices()
      if ((is.null(today) || !nrow(today)) && !is.null(series) && nrow(series)) {
        today <- series[as.Date(series$ts, tz = TZ_BERLIN) == Sys.Date(), , drop = FALSE]
      }
      errs <- character()
      if (is.null(series) || !nrow(series)) {
        errs <- c(errs, "Energy-Charts: keine Preisdaten f\u00fcr den Zeitraum")
      }
      if (is.null(today) || !nrow(today)) {
        errs <- c(errs, "Energy-Charts: keine Tagespreise")
      }
      price_err(if (length(errs)) paste(errs, collapse = " \u00b7 ") else NULL)
      prices_series(series)
      prices_today(today)
      price_loading(FALSE)

      active <- sql_active_solar(input$only_active)
      out <- tryCatch({
        seg <- mastr_query(sprintf("
          SELECT
            %s AS segment,
            COUNT(*) AS units,
            SUM(Bruttoleistung) / 1000.0 AS mw
          FROM solar
          WHERE Bundesland = '1415'
            AND Bruttoleistung >= 10
            %s
          GROUP BY 1", sql_segment_3("Bruttoleistung"), active))
        stor <- mastr_query("
          SELECT COUNT(*) AS units,
            SUM(TRY_CAST(Bruttoleistung AS DOUBLE)) / 1000.0 AS mw
          FROM stromspeicher
          WHERE Bundesland = '1415'")
        list(segments = seg, storage = stor)
      }, error = function(e) {
        data_err(conditionMessage(e))
        NULL
      })
      mastr_data(out)
      data_loading(FALSE)
    })
  }

  price_range_debounced <- debounce(reactive(price_range()), 400)
  loaded_once <- reactiveVal(FALSE)

  session$onFlushed(function() {
    load_all()
    loaded_once(TRUE)
  }, once = TRUE)

  observe({
    invalidateLater(AUTO_REFRESH_MS, session)
    req(isTRUE(loaded_once()))
    load_all()
  })

  observeEvent(price_range_debounced(), load_prices(), ignoreInit = TRUE)
  observeEvent(input$only_active, load_mastr(), ignoreInit = TRUE)
  observeEvent(input$refresh, load_all(), ignoreInit = TRUE)

  output$load_status <- renderUI({
    msgs <- character()
    if (isTRUE(price_loading())) {
      msgs <- c(msgs, "Lade Strompreise \u2026")
    }
    if (isTRUE(data_loading())) {
      msgs <- c(msgs, "Lade MaStR \u2026")
    }
    if (length(msgs)) {
      return(tags$span(class = "text-muted small", paste(msgs, collapse = " \u00b7 ")))
    }
    errs <- c(
      if (!is.null(price_err())) price_err(),
      if (!is.null(data_err())) paste("MaStR:", data_err())
    )
    if (length(errs)) {
      return(tags$span(class = "text-danger small", paste(errs, collapse = " \u00b7 ")))
    }
    p <- prices_series()
    n_hours <- if (!is.null(p) && nrow(p)) nrow(p) else 0L
    tag <- tryCatch(mastr_release_info()$tag, error = function(e) "?")
    tags$div(
      class = "small text-muted",
      tags$p(class = "mb-1", n_hours, " Stunden im Chart \u00b7 MaStR: ", tags$code(tag)),
      tags$p(class = "mb-0", "Zoom: Mausrad \u00b7 Schwenken: ziehen \u00b7 Reset: Doppelklick")
    )
  })

  output$price_range_label <- renderText({
    rng <- price_range()
    days <- as.integer(rng[2] - rng[1]) + 1L
    sprintf("%s \u2013 %s (%d Tag%s, st\u00fcndlich)",
            format(rng[1], "%d.%m.%Y"),
            format(rng[2], "%d.%m.%Y"),
            days, if (days == 1L) "" else "e")
  })

  price_now <- reactive({
    p <- prices_today()
    if (is.null(p) || !nrow(p)) {
      return(NA_real_)
    }
    now_h <- as.integer(format(Sys.time(), "%H", tz = TZ_BERLIN))
    hit <- p[p$hour == now_h, , drop = FALSE]
    if (nrow(hit)) hit$price[1] else tail(p$price, 1)
  })

  output$kpi_now <- renderText({
    if (isTRUE(price_loading()) && is.null(prices_today())) {
      return("\u2026")
    }
    x <- price_now()
    if (is.na(x)) "\u2013" else sprintf("%.1f", x)
  })

  output$kpi_range <- renderText({
    p <- prices_today()
    if (is.null(p) || !nrow(p)) {
      return("\u2013")
    }
    sprintf("%.0f / %.0f", min(p$price, na.rm = TRUE), max(p$price, na.rm = TRUE))
  })

  output$kpi_ci <- renderText({
    if (is.null(mastr_data())) {
      return("\u2026")
    }
    d <- mastr_data()$segments
    if (is.null(d) || !nrow(d)) {
      return("\u2013")
    }
    row <- d[d$segment == "C&I", , drop = FALSE]
    if (!nrow(row)) "\u2013" else paste0(fmt_num(row$mw[1], 1), " MW")
  })

  output$kpi_large <- renderText({
    if (is.null(mastr_data())) {
      return("\u2026")
    }
    d <- mastr_data()$segments
    s <- mastr_data()$storage
    large_mw <- 0
    if (!is.null(d) && nrow(d)) {
      r <- d[d$segment == "Large Scale", , drop = FALSE]
      if (nrow(r)) {
        large_mw <- r$mw[1]
      }
    }
    stor_mw <- if (!is.null(s) && nrow(s) && !is.na(s$mw[1])) s$mw[1] else 0
    paste0(fmt_num(large_mw, 1), " + ", fmt_num(stor_mw, 1), " Speicher")
  })

  output$plot_prices <- renderPlotly({
    p <- prices_series()
    if (is.null(p) || !nrow(p)) {
      return(
        plot_ly(type = "scatter", mode = "markers", x = NULL, y = NULL) |>
          layout(
            annotations = list(
              list(text = "Keine Preisdaten", showarrow = FALSE,
                   xref = "paper", yref = "paper", x = 0.5, y = 0.5)
            ),
            xaxis = list(visible = FALSE),
            yaxis = list(visible = FALSE)
          )
      )
    }

    p <- p |>
      arrange(ts) |>
      mutate(
        ts_label = format(ts, "%d.%m.%Y %H:%M", tz = TZ_BERLIN),
        trace = if (isTRUE(input$highlight_bh)) {
          ifelse(
            business_hour,
            "Gesch\u00e4ftszeit (07\u201318 Uhr)",
            "Au\u00dferhalb Gesch\u00e4ftszeit"
          )
        } else {
          "Day-Ahead"
        }
      )

    if (isTRUE(input$highlight_bh)) {
      traces <- split(p, p$trace)
      plt <- plot_ly(type = "scatter", mode = "lines+markers")
      colors <- c(
        "Gesch\u00e4ftszeit (07\u201318 Uhr)" = "#f59e0b",
        "Au\u00dferhalb Gesch\u00e4ftszeit" = ERWICON_PRIMARY
      )
      for (nm in names(traces)) {
        d <- traces[[nm]]
        plt <- add_trace(
          plt,
          x = d$ts, y = d$price,
          name = nm,
          legendgroup = nm,
          line = list(color = colors[[nm]], width = if (nm == "Gesch\u00e4ftszeit (07\u201318 Uhr)") 2 else 1.2),
          marker = list(size = 4, color = colors[[nm]]),
          text = d$ts_label,
          hovertemplate = paste0(
            "<b>%{text}</b><br>",
            "Preis: %{y:.1f} EUR/MWh<extra>", nm, "</extra>"
          )
        )
      }
    } else {
      plt <- plot_ly(
        p, x = ~ts, y = ~price,
        type = "scatter", mode = "lines+markers",
        name = "Day-Ahead",
        line = list(color = ERWICON_PRIMARY, width = 1.4),
        marker = list(size = 4, color = ERWICON_PRIMARY),
        text = ~ts_label,
        hovertemplate = paste0(
          "<b>%{text}</b><br>",
          "Preis: %{y:.1f} EUR/MWh<extra></extra>"
        )
      )
    }

    span_days <- as.integer(max(as.Date(p$ts)) - min(as.Date(p$ts))) + 1L
    dtick <- if (span_days <= 2L) {
      3600000 * 3
    } else if (span_days <= 7L) {
      3600000 * 6
    } else {
      86400000
    }

    plt |>
      layout(
        xaxis = list(
          title = "Zeit (Europe/Berlin)",
          type = "date",
          dtick = dtick,
          tickformat = if (span_days <= 2L) "%d.%m. %H:%M" else "%d.%m.",
          rangeslider = list(visible = TRUE, thickness = 0.08),
          rangeselector = list(
            buttons = list(
              list(count = 1, label = "1T", step = "day", stepmode = "backward"),
              list(count = 7, label = "7T", step = "day", stepmode = "backward"),
              list(step = "all", label = "Alles")
            )
          )
        ),
        yaxis = list(title = "EUR/MWh", zeroline = TRUE, zerolinecolor = "#cbd5e1"),
        hovermode = "x unified",
        legend = list(orientation = "h", y = 1.12),
        margin = list(t = 40, b = 60)
      ) |>
      config(displayModeBar = TRUE, displaylogo = FALSE, scrollZoom = TRUE)
  })

  output$plot_segments <- renderPlot({
    d <- mastr_data()$segments
    if (is.null(d) || !nrow(d)) {
      return(ggplot() + theme_void())
    }
    d <- d |>
      filter(segment %in% c("C&I", "Large Scale")) |>
      mutate(segment = factor(segment, levels = c("C&I", "Large Scale")))
    if (!nrow(d)) {
      return(ggplot() + theme_void())
    }
    ggplot(d, aes(segment, mw, fill = segment)) +
      geom_col(show.legend = FALSE, width = 0.6) +
      scale_fill_manual(values = c("C&I" = "#fde68a", "Large Scale" = ERWICON_PRIMARY)) +
      labs(x = NULL, y = "MW installiert") +
      theme_minimal(base_size = 11)
  })

  output$tbl_assets <- renderTable({
    d <- mastr_data()
    if (is.null(d)) {
      return(data.frame(Info = "Lade\u2026"))
    }
    seg <- d$segments
    stor <- d$storage
    rows <- list()
    if (!is.null(seg) && nrow(seg)) {
      for (i in seq_len(nrow(seg))) {
        if (seg$segment[i] %in% c("C&I", "Large Scale", "Home")) {
          rows[[length(rows) + 1L]] <- data.frame(
            Kategorie = as.character(seg$segment[i]),
            Anlagen = seg$units[i],
            MW = round(seg$mw[i], 1),
            stringsAsFactors = FALSE
          )
        }
      }
    }
    if (!is.null(stor) && nrow(stor) && !is.na(stor$units[1])) {
      rows[[length(rows) + 1L]] <- data.frame(
        Kategorie = "Batteriespeicher",
        Anlagen = stor$units[1],
        MW = round(stor$mw[1], 1),
        stringsAsFactors = FALSE
      )
    }
    if (!length(rows)) {
      return(data.frame(Hinweis = "Keine MaStR-Daten"))
    }
    do.call(rbind, rows)
  }, striped = TRUE, spacing = "s")
}

shinyApp(ui, server)
