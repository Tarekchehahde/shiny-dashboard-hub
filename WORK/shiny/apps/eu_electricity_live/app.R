# =============================================================================
# eu_electricity_live — day-ahead electricity prices across European bidding
# zones. Data: Fraunhofer ISE Energy-Charts API (free, no key).
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(plotly)
  library(leaflet)
  library(reactable)
  library(jsonlite)
  library(httr2)
  library(tibble)
})

source("../../R/ui_helpers.R")

`%||%` <- function(x, y) if (is.null(x)) y else x

AUTO_REFRESH_MS <- 900000L
MAX_PRICE_DAYS <- 31L
TZ_BERLIN <- "Europe/Berlin"

EU_ZONES <- tibble(
  bzn = c("DE-LU", "FR", "NL", "BE", "AT", "PL", "CZ", "CH", "DK1", "IT-North", "ES"),
  country = c(
    "Germany", "France", "Netherlands", "Belgium", "Austria", "Poland",
    "Czechia", "Switzerland", "Denmark", "Italy (North)", "Spain"
  ),
  lat = c(51.1, 46.6, 52.2, 50.5, 47.5, 52.0, 49.8, 46.8, 56.0, 45.5, 40.4),
  lon = c(10.5, 2.3, 5.3, 4.5, 14.0, 19.0, 15.3, 8.2, 10.0, 9.5, -3.7)
)

.price_cache <- new.env(parent = emptyenv())
.price_cache$data <- NULL
.price_cache$ts <- NULL
CACHE_TTL <- 600L

parse_price_body <- function(body, bzn) {
  if (is.null(body$price) || !length(body$price)) {
    return(NULL)
  }
  ts <- as.POSIXct(body$unix_seconds, origin = "1970-01-01", tz = TZ_BERLIN)
  tibble(
    bzn = bzn,
    ts = ts,
    hour = format(ts, "%H:%M"),
    price = as.numeric(body$price),
    unit = body$unit %||% "EUR/MWh"
  )
}

fetch_zone_prices <- function(bzn, start = NULL, end = NULL) {
  url <- paste0(
    "https://api.energy-charts.info/price?bzn=",
    URLencode(bzn, reserved = TRUE)
  )
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
    parse_price_body(body, bzn)
  }, error = function(e) NULL)
}

fetch_all_zones <- function(start = NULL, end = NULL) {
  parts <- lapply(EU_ZONES$bzn, function(bzn) {
    Sys.sleep(0.12)
    fetch_zone_prices(bzn, start, end)
  })
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (!length(parts)) {
    return(tibble(
      bzn = character(), ts = as.POSIXct(character()), hour = character(),
      price = numeric(), unit = character(), country = character(),
      lat = numeric(), lon = numeric()
    ))
  }
  bind_rows(parts) |>
    left_join(EU_ZONES, by = "bzn")
}

fetch_zones <- function(bzns, start = NULL, end = NULL) {
  bzns <- intersect(bzns, EU_ZONES$bzn)
  if (!length(bzns)) {
    return(tibble(
      bzn = character(), ts = as.POSIXct(character()), hour = character(),
      price = numeric(), unit = character(), country = character(),
      lat = numeric(), lon = numeric()
    ))
  }
  parts <- lapply(bzns, function(bzn) {
    Sys.sleep(0.12)
    fetch_zone_prices(bzn, start, end)
  })
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (!length(parts)) {
    return(tibble(
      bzn = character(), ts = as.POSIXct(character()), hour = character(),
      price = numeric(), unit = character(), country = character(),
      lat = numeric(), lon = numeric()
    ))
  }
  bind_rows(parts) |>
    left_join(EU_ZONES, by = "bzn")
}

cached_prices <- function(force = FALSE) {
  if (!force && !is.null(.price_cache$data) && !is.null(.price_cache$ts) &&
      difftime(Sys.time(), .price_cache$ts, units = "secs") < CACHE_TTL) {
    return(.price_cache$data)
  }
  d <- fetch_all_zones()
  .price_cache$data <- d
  .price_cache$ts <- Sys.time()
  d
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

price_color <- function(p) {
  ifelse(is.na(p), "#94a3b8",
         ifelse(p < 0, "#2563eb",
                ifelse(p < 50, "#10b981",
                       ifelse(p < 100, "#f59e0b", "#ef4444"))))
}

ui <- mastr_page(
  title = "EU Electricity \u2014 Live Day-Ahead Prices",
  subtitle = paste(
    "European bidding-zone day-ahead prices (EUR/MWh) \u2014",
    "Fraunhofer ISE Energy-Charts. Interactive hourly history up to 31 days."
  ),
  fluid = TRUE,
  primary = "#0EA5E9",
  footer = "eu_electricity",
  tags$style(HTML("
    .preset-btns .btn { font-size: 0.78rem; padding: 0.2rem 0.45rem; }
  ")),
  layout_sidebar(
    sidebar = sidebar(
      width = 300,
      title = "Explore",
      tags$p(class = "small fw-semibold mb-1", "Price history"),
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
             "Up to ", MAX_PRICE_DAYS, " days, hourly resolution. ",
             "Zoom, pan, and use the timeline slider below the chart."),
      selectInput(
        "focus_bzn",
        "Focus country / zone",
        choices = setNames(EU_ZONES$bzn, EU_ZONES$country),
        selected = "DE-LU"
      ),
      checkboxGroupInput(
        "compare_bzn",
        "Compare on chart",
        choices = setNames(EU_ZONES$bzn, EU_ZONES$country),
        selected = c("DE-LU", "FR", "NL", "AT", "PL")
      ),
      actionButton("refresh", "Refresh now", class = "btn-sm btn-primary w-100"),
      p(class = "small text-muted mt-2", uiOutput("last_update")),
      hr(),
      tags$div(
        class = "small",
        tags$div(class = "mb-1", tags$span(style = "background:#2563eb;width:12px;height:12px;display:inline-block;border-radius:2px;"), " < 0"),
        tags$div(class = "mb-1", tags$span(style = "background:#10b981;width:12px;height:12px;display:inline-block;border-radius:2px;"), " 0\u201350"),
        tags$div(class = "mb-1", tags$span(style = "background:#f59e0b;width:12px;height:12px;display:inline-block;border-radius:2px;"), " 50\u2013100"),
        tags$div(class = "mb-1", tags$span(style = "background:#ef4444;width:12px;height:12px;display:inline-block;border-radius:2px;"), " > 100 EUR/MWh")
      )
    ),
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      mastr_kpi(
        "Germany now",
        textOutput("kpi_de", inline = TRUE),
        subtitle = "DE-LU latest hour",
        color = "primary"
      ),
      mastr_kpi(
        "EU max now",
        textOutput("kpi_max", inline = TRUE),
        subtitle = textOutput("kpi_max_zone", inline = TRUE),
        color = "danger"
      ),
      mastr_kpi(
        "EU min now",
        textOutput("kpi_min", inline = TRUE),
        subtitle = textOutput("kpi_min_zone", inline = TRUE),
        color = "success"
      ),
      mastr_kpi(
        "Zones loaded",
        textOutput("kpi_zones", inline = TRUE),
        subtitle = "of 11 bidding zones",
        color = "info"
      )
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        full_screen = TRUE,
        card_header("Europe \u2014 latest hour price by zone"),
        card_body(padding = 0, leafletOutput("map_prices", height = "420px"))
      ),
      card(
        full_screen = TRUE,
        card_header(
          "Day-ahead price comparison",
          tags$span(class = "text-muted small ms-2", textOutput("chart_title", inline = TRUE))
        ),
        card_body(plotlyOutput("price_chart", height = "420px"))
      )
    ),
    card(
      class = "mt-3",
      full_screen = TRUE,
      card_header("All zones \u2014 latest hour"),
      reactableOutput("tbl_zones")
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  price_latest <- reactiveVal(NULL)
  price_series <- reactiveVal(NULL)
  last_fetch <- reactiveVal(NULL)
  series_fetch <- reactiveVal(NULL)
  fetch_err <- reactiveVal(NULL)
  series_err <- reactiveVal(NULL)
  series_loading <- reactiveVal(TRUE)

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

  load_latest <- function(force = FALSE) {
    fetch_err(NULL)
    d <- tryCatch(cached_prices(force = force), error = function(e) {
      fetch_err(conditionMessage(e))
      NULL
    })
    price_latest(d)
    last_fetch(Sys.time())
  }

  load_series <- function() {
    series_loading(TRUE)
    series_err(NULL)
    rng <- price_range()
    pick <- intersect(input$compare_bzn, EU_ZONES$bzn)
    if (!length(pick)) {
      pick <- "DE-LU"
    }
    d <- tryCatch({
      withProgress(message = "Loading hourly price history\u2026", value = 0.5, {
        fetch_zones(pick, rng[1], rng[2])
      })
    }, error = function(e) {
      series_err(conditionMessage(e))
      NULL
    })
    if (is.null(d) || !nrow(d)) {
      series_err("No price data for the selected period / zones")
    }
    price_series(d)
    series_fetch(Sys.time())
    series_loading(FALSE)
  }

  load_all <- function(force = FALSE) {
    load_latest(force = force)
    load_series()
  }

  series_inputs <- reactive({
    list(
      range = price_range(),
      zones = sort(intersect(input$compare_bzn, EU_ZONES$bzn))
    )
  })
  series_inputs_debounced <- debounce(reactive(series_inputs()), 450)

  observe({ load_latest(force = FALSE) })
  observeEvent(series_inputs_debounced(), load_series(), ignoreInit = FALSE)
  observeEvent(input$refresh, load_all(force = TRUE), ignoreInit = TRUE)
  observe({
    invalidateLater(AUTO_REFRESH_MS, session)
    load_all(force = FALSE)
  })

  latest_by_zone <- reactive({
    d <- price_latest()
    if (is.null(d) || !nrow(d)) {
      return(d)
    }
    d |>
      group_by(bzn, country, lat, lon, unit) |>
      slice_max(order_by = ts, n = 1, with_ties = FALSE) |>
      ungroup()
  })

  output$last_update <- renderUI({
    t <- last_fetch()
    st <- series_fetch()
    err <- c(
      if (!is.null(fetch_err()) && nzchar(fetch_err())) fetch_err(),
      if (!is.null(series_err()) && nzchar(series_err())) series_err()
    )
    msgs <- character()
    if (isTRUE(series_loading())) {
      msgs <- c(msgs, "Loading history\u2026")
    }
    if (!is.null(t)) {
      msgs <- c(msgs, paste("Live:", format(t, "%H:%M")))
    }
    if (!is.null(st)) {
      p <- price_series()
      n <- if (!is.null(p) && nrow(p)) nrow(p) else 0L
      msgs <- c(msgs, paste0(n, " hourly points"))
    }
    tagList(
      tags$p(class = "mb-1", paste(msgs, collapse = " \u00b7 ")),
      if (length(err)) {
        tags$p(class = "text-danger mb-1", paste(err, collapse = " \u00b7 "))
      },
      tags$p(class = "mb-0", "Auto-refresh ~15 min \u00b7 zoom: scroll \u00b7 pan: drag")
    )
  })

  output$kpi_de <- renderText({
    d <- latest_by_zone()
    if (is.null(d) || !nrow(d)) return("\u2013")
    p <- d$price[d$bzn == "DE-LU"]
    if (!length(p) || is.na(p[1])) "\u2013" else sprintf("%.1f", p[1])
  })

  output$kpi_max <- renderText({
    d <- latest_by_zone()
    if (is.null(d) || !nrow(d)) return("\u2013")
    sprintf("%.1f", max(d$price, na.rm = TRUE))
  })

  output$kpi_max_zone <- renderText({
    d <- latest_by_zone()
    if (is.null(d) || !nrow(d)) return("")
    d$country[which.max(d$price)]
  })

  output$kpi_min <- renderText({
    d <- latest_by_zone()
    if (is.null(d) || !nrow(d)) return("\u2013")
    sprintf("%.1f", min(d$price, na.rm = TRUE))
  })

  output$kpi_min_zone <- renderText({
    d <- latest_by_zone()
    if (is.null(d) || !nrow(d)) return("")
    d$country[which.min(d$price)]
  })

  output$kpi_zones <- renderText({
    d <- latest_by_zone()
    if (is.null(d)) return("\u2013")
    as.character(nrow(d))
  })

  output$chart_title <- renderText({
    rng <- price_range()
    days <- as.integer(rng[2] - rng[1]) + 1L
    n_zones <- length(intersect(input$compare_bzn, EU_ZONES$bzn))
    sprintf("%s \u2013 %s (%d day%s, %d zone%s, hourly)",
            format(rng[1], "%d.%m.%Y"),
            format(rng[2], "%d.%m.%Y"),
            days, if (days == 1L) "" else "s",
            n_zones, if (n_zones == 1L) "" else "s")
  })

  output$map_prices <- renderLeaflet({
    d <- latest_by_zone()
    if (is.null(d) || !nrow(d)) {
      return(leaflet() |>
        addProviderTiles("CartoDB.Positron") |>
        setView(10, 51, 4) |>
        addControl("No price data", position = "topright"))
    }
    d$fill <- price_color(d$price)
    d$label <- paste0(
      d$country, "<br>",
      sprintf("%.1f EUR/MWh", d$price), "<br>",
      d$hour, " (Berlin)"
    )
    leaflet(d) |>
      addProviderTiles("CartoDB.Positron") |>
      setView(10, 51, 4) |>
      addCircleMarkers(
        ~lon, ~lat,
        radius = 8,
        fillColor = ~fill,
        color = "#fff",
        weight = 1,
        fillOpacity = 0.9,
        label = ~label
      )
  })

  output$price_chart <- renderPlotly({
    d <- price_series()
    if (is.null(d) || !nrow(d)) {
      return(
        plot_ly(type = "scatter", mode = "markers", x = NULL, y = NULL) |>
          layout(
            annotations = list(
              list(
                text = if (isTRUE(series_loading())) "Loading price history\u2026" else "No data",
                showarrow = FALSE, xref = "paper", yref = "paper", x = 0.5, y = 0.5
              )
            ),
            xaxis = list(visible = FALSE),
            yaxis = list(visible = FALSE)
          )
      )
    }

    d <- d |>
      arrange(ts, country) |>
      mutate(
        ts_label = format(ts, "%d.%m.%Y %H:%M", tz = TZ_BERLIN),
        bzn_label = country
      )

    zone_order <- d |>
      distinct(bzn_label) |>
      pull(bzn_label)

    plt <- plot_ly(type = "scatter", mode = "lines")
    palette <- RColorBrewer::brewer.pal(max(3L, length(zone_order)), "Set2")[seq_along(zone_order)]

    for (i in seq_along(zone_order)) {
      nm <- zone_order[i]
      z <- d[d$bzn_label == nm, , drop = FALSE]
      plt <- add_trace(
        plt,
        x = z$ts,
        y = z$price,
        name = nm,
        legendgroup = nm,
        line = list(color = palette[i], width = 1.5),
        marker = list(size = 3, color = palette[i]),
        text = z$ts_label,
        hovertemplate = paste0(
          "<b>", nm, "</b><br>",
          "%{text}<br>",
          "Price: %{y:.1f} EUR/MWh<extra></extra>"
        )
      )
    }

    span_days <- as.integer(max(as.Date(d$ts, tz = TZ_BERLIN)) -
                              min(as.Date(d$ts, tz = TZ_BERLIN))) + 1L
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
          title = "Time (Europe/Berlin)",
          type = "date",
          dtick = dtick,
          tickformat = if (span_days <= 2L) "%d.%m. %H:%M" else "%d.%m.",
          rangeslider = list(visible = TRUE, thickness = 0.08),
          rangeselector = list(
            buttons = list(
              list(count = 1, label = "1d", step = "day", stepmode = "backward"),
              list(count = 7, label = "7d", step = "day", stepmode = "backward"),
              list(step = "all", label = "All")
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

  output$tbl_zones <- renderReactable({
    d <- latest_by_zone()
    if (is.null(d) || !nrow(d)) {
      return(reactable(data.frame(Zone = "Loading\u2026")))
    }
    d |>
      arrange(desc(price)) |>
      transmute(
        Country = country,
        Zone = bzn,
        `EUR/MWh` = round(price, 1),
        Hour = hour
      ) |>
      reactable(defaultPageSize = 11, compact = TRUE, highlight = TRUE)
  })
}

shinyApp(ui, server)
