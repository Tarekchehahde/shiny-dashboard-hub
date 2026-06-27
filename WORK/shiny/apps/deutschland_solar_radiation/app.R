# =============================================================================
# deutschland_solar_radiation — live GHI (W/m²) across Germany by PLZ + cities.
# Data: Open-Meteo Forecast API (DWD / satellite models). No API key.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(ggplot2)
  library(leaflet)
  library(jsonlite)
  library(httr2)
  library(tibble)
})

source("../../R/ui_helpers.R")

AUTO_REFRESH_MS <- 900000L

PLZ_GRID <- as_tibble(utils::read.csv(
  "data/plz_centroids.csv",
  stringsAsFactors = FALSE,
  fileEncoding = "UTF-8"
)) |>
  mutate(
    plz = sprintf("%05d", as.integer(plz)),
    id = plz
  )

STATIONS <- tibble(
  city = c(
    "Berlin", "Hamburg", "München", "Köln", "Frankfurt", "Stuttgart",
    "Dresden", "Hannover", "Leipzig", "Nürnberg", "Bremen", "Kiel",
    "Freiburg", "Erfurt", "Mainz", "Rostock", "Saarbrücken", "Magdeburg"
  ),
  lat = c(52.52, 53.55, 48.14, 50.94, 50.11, 48.78, 51.05, 52.37, 51.34,
          49.45, 53.08, 54.32, 47.99, 50.98, 50.00, 54.09, 49.24, 52.13),
  lon = c(13.41, 9.99, 11.58, 6.96, 8.68, 9.18, 13.74, 9.73, 12.37,
          11.08, 8.80, 10.12, 7.85, 11.03, 8.27, 12.14, 7.00, 11.62)
) |>
  mutate(id = city, plz = NA_character_, ort = city)

`%||%` <- function(x, y) if (is.null(x)) y else x

# Shared across Shiny sessions in one R process — avoids N sessions × 450 API calls.
.rad_cache <- new.env(parent = emptyenv())
.rad_cache$plz <- NULL
.rad_cache$cities <- NULL
.rad_cache$plz_ts <- NULL
.rad_cache$cities_ts <- NULL
.rad_cache$hourly <- list()
.rad_cache$hourly_ts <- list()
CACHE_TTL_SEC <- 900L
MAX_PLZ_POINTS <- 120L
API_CHUNK <- 40L
API_PAUSE_SEC <- 0.35

round_coord <- function(x) round(as.numeric(x), 2)

rad_color <- function(w) {
  ifelse(is.na(w), "#94a3b8",
         ifelse(w < 50, "#1e3a5f",
                ifelse(w < 200, "#2563eb",
                       ifelse(w < 500, "#f59e0b", "#ef4444"))))
}

parse_open_meteo_multi <- function(resp) {
  if (is.null(resp)) {
    return(list())
  }
  if (length(resp) == 0L) {
    return(list())
  }
  # Multi-location responses are a JSON array; single location is one object.
  if (!is.null(resp$latitude) && is.null(resp[[1]]$latitude)) {
    resp <- list(resp)
  }
  if (!is.null(resp$error)) {
    return(list())
  }
  lapply(resp, function(x) {
    cur <- x$current %||% list()
    list(
      current = as.numeric(cur$shortwave_radiation %||% NA_real_),
      is_day = cur$is_day %||% NA
    )
  })
}

fetch_open_meteo_json <- function(url, simplify = FALSE, retries = 3L) {
  for (attempt in seq_len(retries)) {
    Sys.sleep(API_PAUSE_SEC)
    resp <- tryCatch({
      req <- httr2::request(url) |>
        httr2::req_timeout(45) |>
        httr2::req_retry(max_tries = 1, is_transient = function(r) httr2::resp_status(r) %in% c(429L, 500L, 502L, 503L))
      out <- httr2::req_perform(req)
      status <- httr2::resp_status(out)
      if (status >= 400L) {
        stop(sprintf("HTTP %s", status), call. = FALSE)
      }
      jsonlite::fromJSON(httr2::resp_body_string(out), simplifyVector = simplify)
    }, error = function(e) NULL)
    if (!is.null(resp)) {
      return(resp)
    }
    Sys.sleep(0.5 * attempt)
  }
  NULL
}

fetch_current_batch <- function(lats, lons) {
  lats <- round_coord(lats)
  lons <- round_coord(lons)
  n <- length(lats)
  if (n == 0L) {
    return(vector("list", 0))
  }
  out <- vector("list", n)
  idx <- 1L
  for (i in seq(1L, n, API_CHUNK)) {
    j <- min(i + API_CHUNK - 1L, n)
    url <- paste0(
      "https://api.open-meteo.com/v1/forecast?",
      "latitude=", paste(lats[i:j], collapse = ","),
      "&longitude=", paste(lons[i:j], collapse = ","),
      "&current=shortwave_radiation,is_day",
      "&timezone=Europe/Berlin"
    )
    parsed <- parse_open_meteo_multi(fetch_open_meteo_json(url))
    k <- length(parsed)
    if (k > 0L) {
      out[idx:(idx + k - 1L)] <- parsed
      idx <- idx + k
    }
  }
  if (idx == 1L) {
    return(rep(list(list(current = NA_real_, is_day = NA)), n))
  }
  if (idx - 1L < n) {
    for (k in idx:n) {
      out[[k]] <- list(current = NA_real_, is_day = NA)
    }
  }
  out
}

cache_fresh <- function(ts) {
  !is.null(ts) && is.finite(as.numeric(difftime(Sys.time(), ts, units = "secs"))) &&
    difftime(Sys.time(), ts, units = "secs") < CACHE_TTL_SEC
}

attach_current <- function(pts) {
  batch <- fetch_current_batch(pts$lat, pts$lon)
  n <- nrow(pts)
  if (length(batch) < n) {
    batch <- c(batch, rep(list(list(current = NA_real_, is_day = NA)), n - length(batch)))
  }
  pts$current_w_m2 <- vapply(batch[seq_len(n)], function(x) x$current, numeric(1))
  pts$is_day <- vapply(batch[seq_len(n)], function(x) x$is_day, numeric(1))
  pts
}

empty_hourly <- function() {
  tibble(hour = character(), hour_ord = integer(), radiation = numeric())
}

fetch_hourly_point <- function(lat, lon) {
  url <- paste0(
    "https://api.open-meteo.com/v1/forecast?",
    "latitude=", round_coord(lat), "&longitude=", round_coord(lon),
    "&hourly=shortwave_radiation",
    "&timezone=Europe/Berlin&forecast_days=1"
  )
  resp <- fetch_open_meteo_json(url, simplify = TRUE)
  if (is.null(resp) || is.null(resp$hourly)) {
    return(empty_hourly())
  }
  hrs <- resp$hourly$time
  rad <- resp$hourly$shortwave_radiation
  if (is.null(hrs) || !length(hrs)) {
    return(empty_hourly())
  }
  tibble(
    hour = sub("^.*T", "", hrs),
    hour_ord = seq_along(hrs),
    radiation = as.numeric(rad)
  )
}

fetch_hourly_cached <- function(lat, lon) {
  key <- paste(round_coord(lat), round_coord(lon), sep = ",")
  ts <- .rad_cache$hourly_ts[[key]] %||% NULL
  hit <- .rad_cache$hourly[[key]] %||% NULL
  if (!is.null(hit) && !is.null(ts) &&
      difftime(Sys.time(), ts, units = "secs") < 600) {
    return(hit)
  }
  d <- fetch_hourly_point(lat, lon)
  .rad_cache$hourly[[key]] <- d
  .rad_cache$hourly_ts[[key]] <- Sys.time()
  d
}

plz_grid_sampled <- function() {
  n <- nrow(PLZ_GRID)
  step <- max(1L, as.integer(ceiling(n / MAX_PLZ_POINTS)))
  PLZ_GRID[seq(1L, n, by = step), , drop = FALSE]
}

ui <- mastr_page(
  title = "Solar Radiation — Germany",
  subtitle = paste(
    "Near-real-time global horizontal irradiance (W/m²) — Open-Meteo / DWD satellite models.",
    "Source updates hourly; this dashboard auto-refreshes every 15 minutes."
  ),
  fluid = TRUE,
  primary = "#f59e0b",
  footer = "solar_radiation",
  tags$style(HTML("
    .rad-map { border-radius: 8px; overflow: hidden; min-height: 480px; }
    .rad-legend span { display: inline-block; width: 14px; height: 14px;
      border-radius: 3px; margin-right: 4px; vertical-align: middle; }
    .live-pill { font-size: 0.75rem; }
  ")),
  layout_sidebar(
    sidebar = sidebar(
      width = 300,
      title = "Explore",
      radioButtons(
        "map_mode", "Map view",
        choices = c("PLZ grid (~120 areas)" = "plz", "Major cities (18)" = "cities"),
        selected = "plz"
      ),
      selectInput("plz_pick", "PLZ / city", choices = c("Loading…" = "")),
      actionButton("refresh", "Refresh now", class = "btn-sm btn-warning w-100"),
      p(class = "small text-muted mt-2", textOutput("last_update", inline = TRUE)),
      p(class = "small text-success live-pill mb-0",
        tags$span(class = "badge bg-success me-1", "Live"),
        "Open-Meteo · auto-refresh 15 min"),
      hr(),
      uiOutput("sel_kpi"),
      hr(),
      tags$div(
        class = "small",
        tags$div(class = "rad-legend mb-1", tags$span(style = "background:#1e3a5f"), " < 50 W/m²"),
        tags$div(class = "rad-legend mb-1", tags$span(style = "background:#2563eb"), " 50–200"),
        tags$div(class = "rad-legend mb-1", tags$span(style = "background:#f59e0b"), " 200–500"),
        tags$div(class = "rad-legend mb-1", tags$span(style = "background:#ef4444"), " > 500"),
        tags$p(class = "text-muted mt-2 mb-0",
               "PLZ map: ~120 sampled postal codes (GeoNames). Click a dot for hourly chart.")
      )
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        card_header(textOutput("map_title", inline = TRUE)),
        card_body(padding = 0, div(class = "rad-map", leafletOutput("map_rad", height = "480px")))
      ),
      card(
        card_header(textOutput("chart_title", inline = TRUE)),
        plotOutput("hourly_plot", height = "480px")
      )
    ),
    card(
      class = "mt-3",
      card_header("Selected area — current value"),
      tableOutput("detail_table")
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  plz_data <- reactiveVal(NULL)
  city_data <- reactiveVal(NULL)
  last_fetch <- reactiveVal(NULL)
  fetch_error <- reactiveVal(NULL)

  active_data <- reactive({
    if (identical(input$map_mode, "plz")) plz_data() else city_data()
  })

  selected_id <- reactive({
    d <- active_data()
    req(d, nrow(d) > 0)
    pick <- input$plz_pick
    if (!is.null(pick) && nzchar(pick) && pick %in% d$id) {
      return(pick)
    }
    d$id[1]
  })

  selected_row <- reactive({
    d <- active_data()
    req(d)
    row <- d |> filter(id == selected_id())
    req(nrow(row) == 1)
    row
  })

  hourly_data <- reactive({
    row <- selected_row()
    fetch_hourly_cached(row$lat, row$lon)
  })

  sync_choices <- function(d, mode, preserve = NULL) {
    req(d, nrow(d) > 0)
    if (identical(mode, "plz")) {
      choices <- stats::setNames(d$id, paste0(d$plz, " · ", d$ort))
    } else {
      choices <- stats::setNames(d$id, d$city)
    }
    sel <- preserve %||% input$plz_pick
    if (is.null(sel) || !nzchar(sel) || !sel %in% d$id) {
      sel <- d$id[1]
    }
    updateSelectInput(session, "plz_pick", choices = choices, selected = sel)
  }

  load_plz <- function(force = FALSE) {
    if (!force && cache_fresh(.rad_cache$plz_ts) && !is.null(.rad_cache$plz)) {
      plz_data(.rad_cache$plz)
      last_fetch(.rad_cache$plz_ts)
      fetch_error(NULL)
      return(invisible())
    }
    fetch_error(NULL)
    withProgress(message = "Fetching PLZ grid…", value = 0.5, {
      d <- attach_current(plz_grid_sampled())
      ok <- sum(!is.na(d$current_w_m2))
      if (ok == 0L) {
        fetch_error("Open-Meteo rate limit or network error — try Refresh or switch to cities.")
      }
      .rad_cache$plz <- d
      .rad_cache$plz_ts <- Sys.time()
      plz_data(d)
      last_fetch(.rad_cache$plz_ts)
    })
  }

  load_cities <- function(force = FALSE) {
    if (!force && cache_fresh(.rad_cache$cities_ts) && !is.null(.rad_cache$cities)) {
      city_data(.rad_cache$cities)
      last_fetch(.rad_cache$cities_ts)
      fetch_error(NULL)
      return(invisible())
    }
    fetch_error(NULL)
    withProgress(message = "Fetching cities…", value = 0.5, {
      d <- attach_current(STATIONS)
      ok <- sum(!is.na(d$current_w_m2))
      if (ok == 0L) {
        fetch_error("Open-Meteo rate limit or network error — try Refresh in a minute.")
      }
      .rad_cache$cities <- d
      .rad_cache$cities_ts <- Sys.time()
      city_data(d)
      last_fetch(.rad_cache$cities_ts)
    })
  }

  load_active <- function(force = FALSE) {
    if (identical(input$map_mode, "plz")) {
      load_plz(force = force)
    } else {
      load_cities(force = force)
    }
  }

  observe({
    invalidateLater(AUTO_REFRESH_MS, session)
    load_active(force = FALSE)
  })

  # Populate dropdown once when data arrives; do not reset on every refresh tick.
  observeEvent(plz_data(), {
    d <- plz_data()
    if (!is.null(d) && identical(input$map_mode, "plz")) {
      preserve <- if (nzchar(input$plz_pick %||% "") && input$plz_pick %in% d$id) {
        input$plz_pick
      } else {
        NULL
      }
      sync_choices(d, "plz", preserve = preserve)
    }
  }, ignoreInit = TRUE)

  observeEvent(city_data(), {
    d <- city_data()
    if (!is.null(d) && identical(input$map_mode, "cities")) {
      preserve <- if (nzchar(input$plz_pick %||% "") && input$plz_pick %in% d$id) {
        input$plz_pick
      } else {
        NULL
      }
      sync_choices(d, "cities", preserve = preserve)
    }
  }, ignoreInit = TRUE)

  observeEvent(input$refresh, load_active(force = TRUE), ignoreInit = TRUE)

  observeEvent(input$map_mode, {
    d <- active_data()
    if (is.null(d)) {
      load_active()
    } else {
      sync_choices(d, input$map_mode)
    }
  }, ignoreInit = TRUE)

  observeEvent(input$plz_pick, {
    req(input$plz_pick, nzchar(input$plz_pick))
    d <- active_data()
    req(d, input$plz_pick %in% d$id)
    row <- d[d$id == input$plz_pick, , drop = FALSE]
    if (nrow(row) != 1L) {
      return()
    }
    leafletProxy("map_rad") |>
      clearPopups() |>
      addPopups(
        lng = row$lon,
        lat = row$lat,
        popup = if (identical(input$map_mode, "plz")) {
          paste0("PLZ ", row$plz, " · ", row$ort)
        } else {
          row$city
        }
      )
  }, ignoreInit = TRUE)

  observeEvent(input$map_rad_marker_click, {
    id <- input$map_rad_marker_click$id
    if (!is.null(id) && nzchar(id)) {
      updateSelectInput(session, "plz_pick", selected = id)
    }
  })

  output$last_update <- renderText({
    t <- last_fetch()
    err <- fetch_error()
    base <- if (is.null(t)) {
      "Loading…"
    } else {
      paste("Last fetch:", format(t, "%H:%M %d %b %Y"), "· auto-refresh ~15 min")
    }
    if (!is.null(err) && nzchar(err)) paste(base, "·", err) else base
  })

  output$map_title <- renderText({
    if (identical(input$map_mode, "plz")) {
      "Germany — current irradiance by PLZ (sampled grid, ~120 areas)"
    } else {
      "Germany — current irradiance (major cities)"
    }
  })

  output$chart_title <- renderText({
    row <- selected_row()
    label <- if (identical(input$map_mode, "plz")) {
      paste0("PLZ ", row$plz, " · ", row$ort)
    } else {
      row$city
    }
    paste("Today — hourly GHI:", label)
  })

  output$sel_kpi <- renderUI({
    if (is.null(active_data())) {
      return(p(class = "text-muted small", "Loading map data…"))
    }
    row <- tryCatch(selected_row(), error = function(e) NULL)
    if (is.null(row)) {
      return(p(class = "text-muted small", "Select a PLZ or city"))
    }
    w <- row$current_w_m2
    tagList(
      h4(if (is.na(w)) "—" else sprintf("%.0f W/m²", w), class = "mb-1"),
      p(class = "small text-muted mb-0",
        if (identical(input$map_mode, "plz")) {
          paste0("PLZ ", row$plz, " · ", row$ort)
        } else {
          row$city
        }),
      p(class = "small text-muted mb-0",
        if (isTRUE(row$is_day == 1L)) "Daylight — radiation active" else "Night / low sun")
    )
  })

  output$map_rad <- renderLeaflet({
    d <- active_data()
    req(d, nrow(d) > 0L)
    plz_mode <- identical(input$map_mode, "plz")
    d$fill <- rad_color(d$current_w_m2)
    d$rad <- pmax(replace(d$current_w_m2, is.na(d$current_w_m2), 0), 0)
    if (plz_mode) {
      d$radius <- 5
      d$label <- paste0(
        "PLZ ", d$plz, " · ", d$ort, ": ",
        ifelse(is.na(d$current_w_m2), "n/a", paste0(round(d$current_w_m2), " W/m²"))
      )
    } else {
      d$radius <- pmax(7, sqrt(d$rad) / 2)
      d$label <- paste0(
        d$city, ": ",
        ifelse(is.na(d$current_w_m2), "n/a", paste0(round(d$current_w_m2), " W/m²"))
      )
    }

    leaflet(d, options = leafletOptions(minZoom = 5, maxZoom = 12)) |>
      addProviderTiles(providers$CartoDB.Positron) |>
      setView(lng = 10.5, lat = 51.0, zoom = 6) |>
      addCircleMarkers(
        lng = ~lon, lat = ~lat,
        radius = ~radius,
        fillColor = ~fill,
        color = "#fff",
        weight = if (plz_mode) 0.5 else 1,
        fillOpacity = 0.85,
        label = ~label,
        layerId = ~id
      ) |>
      addLegend(
        "bottomright",
        colors = c("#1e3a5f", "#2563eb", "#f59e0b", "#ef4444"),
        labels = c("< 50", "50–200", "200–500", "> 500 W/m²"),
        title = "GHI now",
        opacity = 0.9
      )
  })

  output$hourly_plot <- renderPlot({
    h <- hourly_data()
    n <- NROW(h)
    if (n < 1L) {
      plot.new()
      text(0.5, 0.5, "Hourly data unavailable\n(rate limit? click Refresh)",
           cex = 0.9, col = "gray40")
      return(invisible())
    }
    tick_n <- min(12L, n)
    tick_idx <- unique(as.integer(round(seq(1, n, length.out = tick_n))))
    tick_breaks <- h$hour_ord[tick_idx]
    tick_labels <- as.character(h$hour[tick_idx])
    ggplot(h, aes(hour_ord, radiation)) +
      geom_col(fill = "#f59e0b", width = 0.85) +
      scale_x_continuous(breaks = tick_breaks, labels = tick_labels) +
      labs(x = "Hour (Europe/Berlin)", y = "W/m²") +
      theme_minimal(base_size = 12) +
      theme(
        panel.grid.minor = element_blank(),
        axis.text.x = element_text(angle = 45, hjust = 1)
      )
  }, height = 460)

  output$detail_table <- renderTable({
    row <- selected_row()
    if (identical(input$map_mode, "plz")) {
      data.frame(
        PLZ = as.character(row$plz),
        Ort = as.character(row$ort),
        `GHI now (W/m2)` = ifelse(is.na(row$current_w_m2), "n/a",
                                  sprintf("%.0f", row$current_w_m2)),
        Status = ifelse(is.na(row$is_day), "n/a",
                        ifelse(row$is_day == 1L, "Day", "Night")),
        Lat = round(row$lat, 3),
        Lon = round(row$lon, 3),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    } else {
      data.frame(
        City = as.character(row$city),
        `GHI now (W/m2)` = sprintf("%.0f", row$current_w_m2),
        Status = ifelse(is.na(row$is_day), "n/a",
                        ifelse(row$is_day == 1L, "Day", "Night")),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    }
  }, striped = TRUE, spacing = "s")
}

shinyApp(ui, server)
