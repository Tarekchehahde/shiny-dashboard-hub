# =============================================================================
# most_visited_forecast :: frozen previous-year ensemble + overlay of the
# current year (MaStR lag). Sibling of most_visited — does not change that
# dashboard. Same solar extract and segment split.
#
# Training: complete calendar years from Trainingsstart through December of
# (current year − 1). The current year is never used as a feature.
# Display: Ist of the current year is a labeled vorläufig overlay; the
# 4-month KPI strip is the remaining months of that frozen year-ahead
# forecast (not a retrain on last-complete-month).
# =============================================================================

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable)
  library(dplyr); library(tidyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")
source("forecast_engine.R")

YEAR_NOW  <- as.integer(format(Sys.Date(), "%Y"))
MONTH_NOW <- as.integer(format(Sys.Date(), "%m"))

SEGMENT_CHOICES <- c(
  "Home" = "Home",
  "C&I" = "C&I",
  "Large Scale" = "Large Scale",
  "Grand Total" = "Grand Total"
)
SEGMENT_HINTS <- c(
  Home = "Anlagen < 10 kW",
  `C&I` = "10 kW bis < 1 MW",
  `Large Scale` = "\u2265 1 MW",
  `Grand Total` = "Summe der drei Segmente (koh\u00e4rent)"
)
MODEL_LABELS <- c(
  snaive        = "Saisonale Naive",
  robust_snaive = "Robuste Naive (ohne Spikes)",
  anchor_damped = "Anker \u00d7 ged\u00e4mpftes YoY",
  seasonal_yoy  = "Saison \u00d7 ged\u00e4mpftes YoY",
  month_trend   = "Monats-Trend (log-linear)",
  ets           = "ETS / Holt-Winters",
  sarima        = "SARIMA (auto.arima)",
  stlm          = "STL + ETS",
  nnetar        = "NNAR (neuronales Netz)",
  rf_lags       = "Random Forest (Lags)"
)

MATRIX <- list(
  bg     = "#050a07",
  panel  = "#07140e",
  card   = "#0a1610",
  header = "#0c1f14",
  border = "#1a4d32",
  text   = "#c8ffd4",
  muted  = "#6ee7b7",
  neon   = "#00ff41",
  dim    = "#14532d",
  grid   = "#123322",
  pos    = "#39ff14",
  neg    = "#ff6b6b",
  fc     = "#7dd3fc"
)

.mv_href <- function() {
  if (identical(Sys.getenv("MASTR_HUB_MODE", "paths"), "ports"))
    "http://localhost:3839/" else "/most_visited/"
}

fmt_mw <- function(x, digits = 0) {
  ifelse(!is.finite(x), "\u2014",
         formatC(x, big.mark = ".", decimal.mark = ",",
                 format = "f", digits = digits))
}
fmt_pct <- function(x) {
  ifelse(!is.finite(x), "\u2014",
         paste0(ifelse(x >= 0, "+", ""),
                formatC(x * 100, format = "f", digits = 1,
                        decimal.mark = ",", big.mark = "."), " %"))
}
month_date <- function(year, month) as.Date(sprintf("%04d-%02d-01", year, month))

# Polynomial trend estimated on observed (Ist) points only. Never fit a
# separate polynomial on the short Prognose snippet — a 2nd/3rd order
# through 4–5 forecast points interpolates, it does not estimate a trend.
# Evaluate the Ist fit on a dense grid; pass x_from/x_to to extrapolate
# the same coefficients into the forecast window.
poly_fit <- function(x, y, degree = 3L) {
  ok <- is.finite(x) & is.finite(y)
  x <- as.numeric(x[ok])
  y <- as.numeric(y[ok])
  if (length(y) < 4L) return(NULL)
  d <- min(as.integer(degree), length(y) - 1L)
  if (d < 2L) return(NULL)
  dat <- data.frame(x = x, y = y)
  fit <- tryCatch(
    stats::lm(y ~ stats::poly(x, d, raw = TRUE), data = dat),
    error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  list(fit = fit, degree = d)
}

poly_eval <- function(model, x_from, x_to, n_out = 90L) {
  if (is.null(model)) return(NULL)
  x_from <- as.numeric(x_from)
  x_to <- as.numeric(x_to)
  if (!is.finite(x_from) || !is.finite(x_to) || x_to <= x_from) return(NULL)
  xg <- seq(x_from, x_to, length.out = n_out)
  yg <- as.numeric(stats::predict(model$fit, newdata = data.frame(x = xg)))
  data.frame(x = xg, y = pmax(yg, 0), degree = model$degree)
}

poly_curve <- function(x, y, degree = 3L, n_out = 90L) {
  model <- poly_fit(x, y, degree = degree)
  if (is.null(model)) return(NULL)
  xx <- as.numeric(x[is.finite(x) & is.finite(y)])
  poly_eval(model, min(xx), max(xx), n_out = n_out)
}

matrix_theme <- function() {
  bslib::bs_theme(
    version = 5,
    bg = MATRIX$bg, fg = MATRIX$text,
    primary = MATRIX$neon, secondary = MATRIX$dim,
    success = MATRIX$pos, info = "#22c55e",
    warning = "#86efac", danger = MATRIX$neg,
    base_font = bslib::font_google("Inter", local = FALSE),
    heading_font = bslib::font_google("Inter", local = FALSE),
    "font-size-base" = "0.95rem"
  )
}

matrix_css <- tags$style(HTML(sprintf("
  html { color-scheme: dark; }
  body, .bslib-page-fluid {
    background: radial-gradient(ellipse at top, #0d2818 0%%, %s 58%%) !important;
    color: %s;
  }
  h2.mb-0 { color: %s; text-shadow: 0 0 18px rgba(0, 255, 65, 0.22); }
  .text-muted, small.text-muted { color: %s !important; }
  a, a:link, #hub_back { color: %s !important; }
  a:hover, #hub_back:hover { color: #39ff14 !important; }
  hr { border-color: %s; opacity: 1; }
  .card {
    background: %s !important; border: 1px solid %s !important;
    box-shadow: 0 0 28px rgba(0, 255, 65, 0.07); color: %s;
  }
  .card-header {
    background: %s !important; border-bottom: 1px solid %s !important;
    color: %s !important;
  }
  .bslib-sidebar-layout > .sidebar {
    background: #050d09 !important; border-right: 1px solid %s !important; color: %s;
  }
  .bslib-sidebar-layout > .main { background: transparent !important; }
  .form-check-input { background-color: %s; border-color: %s; }
  .form-check-input:checked { background-color: %s; border-color: %s; }
  .form-check-label, .control-label, .shiny-input-container label { color: %s; }
  .irs--shiny .irs-bar, .irs-bar { background: %s !important; border-color: %s !important; }
  .irs--shiny .irs-line, .irs-line { background: %s !important; border-color: %s !important; }
  .irs--shiny .irs-handle, .irs-handle { background: %s !important; border: 1px solid %s !important; }
  .irs--shiny .irs-single, .irs--shiny .irs-from, .irs--shiny .irs-to,
  .irs-single, .irs-from, .irs-to { background: %s !important; color: #04110a !important; }
  .irs--shiny .irs-min, .irs--shiny .irs-max, .irs-min, .irs-max {
    background: %s !important; color: %s !important;
  }
  .irs-grid-text { color: %s !important; }
  .mastr-footer { color: %s !important; border-top-color: %s !important; }
  .mastr-footer a { color: %s !important; }
  .bslib-sidebar-title, .sidebar-title { color: #00ff41 !important; }
  .bslib-value-box, .value-box {
    background: %s !important; border: 1px solid %s !important; color: %s !important;
  }
  .value-box .value-box-value { color: %s !important; }
  .segment-pills .shiny-input-container { margin-bottom: 0.35rem; }
  .segment-pills .shiny-options-group { display: flex; flex-wrap: wrap; gap: 0.4rem; }
  .segment-pills .form-check { padding-left: 0; margin: 0; }
  .segment-pills .form-check-input { position: absolute; opacity: 0; pointer-events: none; }
  .segment-pills .form-check-label {
    display: inline-block; margin: 0; cursor: pointer; border-radius: 999px;
    border: 1px solid #1a4d32; background: #07140e; color: #6ee7b7;
    padding: 0.28rem 0.9rem; font-size: 0.82rem; font-weight: 600;
  }
  .segment-pills .form-check-label:hover { border-color: #00ff41; color: #c8ffd4; }
  .segment-pills .form-check:has(.form-check-input:checked) .form-check-label {
    background: #00ff41; border-color: #00ff41; color: #04110a;
    box-shadow: 0 0 12px rgba(0, 255, 65, 0.28);
  }
  .fc-nav a {
    display: inline-block; margin-bottom: 0.75rem; font-weight: 700;
    border: 1px solid #00ff41; border-radius: 999px; padding: 0.28rem 0.85rem;
    color: #04110a !important; background: #00ff41; text-decoration: none;
  }
  .fc-nav a:hover { background: #39ff14 !important; color: #04110a !important; }
  .alert-info {
    background: %s !important; border-color: %s !important; color: %s !important;
  }
  .fc-mape-banner {
    display: flex; flex-wrap: wrap; gap: 0.6rem; margin-bottom: 1rem;
  }
  .fc-mape-chip {
    border: 1px solid #1a4d32; background: #07140e; color: #c8ffd4;
    border-radius: 12px; padding: 0.55rem 0.85rem; min-width: 140px;
  }
  .fc-mape-chip strong { color: #00ff41; display: block; font-size: 1.05rem; }
  .fc-mape-chip span { color: #6ee7b7; font-size: 0.78rem; }

",
  MATRIX$bg, MATRIX$text, MATRIX$neon, MATRIX$muted, MATRIX$neon, MATRIX$border,
  MATRIX$card, MATRIX$border, MATRIX$text,
  MATRIX$header, MATRIX$border, MATRIX$neon,
  MATRIX$border, MATRIX$text,
  MATRIX$card, MATRIX$border, MATRIX$neon, MATRIX$neon, MATRIX$text,
  MATRIX$neon, MATRIX$neon, MATRIX$dim, MATRIX$border,
  MATRIX$panel, MATRIX$neon, MATRIX$neon,
  MATRIX$dim, MATRIX$muted, MATRIX$muted,
  MATRIX$muted, MATRIX$border, MATRIX$neon,
  MATRIX$card, MATRIX$border, MATRIX$text, MATRIX$neon,
  MATRIX$header, MATRIX$border, MATRIX$muted
)))

ui <- mastr_page(
  title = "Most Visited \u2014 4-Monats-Prognose",
  subtitle = sprintf(
    "Ein eingefrorenes Modell: volle Kalenderjahre bis Dezember %d, dann 12 Monate %d. Ist-%d ist nur Overlay (MaStR-Nachmeldung) und geht nicht ins Ensemble.",
    YEAR_NOW - 1L, YEAR_NOW, YEAR_NOW),
  fluid = TRUE,
  theme = matrix_theme(),
  tags$head(tags$meta(name = "theme-color", content = "#00ff41")),
  matrix_css,

  div(class = "fc-nav",
      tags$a(href = .mv_href(), "\u2190 Zur\u00fcck zu Most Visited")),

  div(class = "alert alert-info py-2 mb-3", style = "font-size:0.85rem;",
      tags$strong("Modell:"),
      " invers-MAPE-gewichtetes Ensemble aus ETS, SARIMA, STL+ETS, NNAR,",
      " Random Forest (Lags), monatsweisem log-linearem Trend und ged\u00e4mpftem",
      " saisonalem YoY. Grand Total = Summe der drei Segmente.",
      " Training ausschlie\u00dflich auf vollst\u00e4ndigen Jahren bis Dezember ",
      YEAR_NOW - 1L, " \u2014 keine ", YEAR_NOW, "-Monate im Fit",
      " (Nachmeldung w\u00fcrde sonst einen k\u00fcnstlichen R\u00fcckgang erzeugen).",
      " Die KPI-Leiste zeigt die Restmonate von ", YEAR_NOW,
      " aus genau diesem Jahr-voraus-Lauf. Ist ", YEAR_NOW,
      " erscheint nur als vorl\u00e4ufiges Overlay."),

  layout_sidebar(
    sidebar = sidebar(
      title = "Einstellungen", width = 280,
      sliderInput("yr_from", "Trainingsstart",
                  min = 2015, max = YEAR_NOW - 4,
                  value = 2016, sep = "", step = 1, ticks = FALSE),
      radioButtons("metric", "Metrik",
                   choices = c("Brutto/DC-Leistung MW" = "brutto",
                               "Nettonennleistung MW"  = "netto"),
                   selected = "brutto"),
      checkboxInput("only_active", "Nur aktive Einheiten", value = FALSE),
      tags$hr(),
      tags$small(class = "text-muted",
        "Das Ensemble endet mit Dezember des Vorjahres. Der laufende Monat",
        " und der Vormonat gelten als MaStR-vorl\u00e4ufig und werden weder",
        " trainiert noch in der MAPE gez\u00e4hlt. Die vier KPI-Monate sind",
        " die Restmonate des eingefrorenen Jahresausblicks.")
    ),

    layout_column_wrap(
      width = 1/4,
      uiOutput("kpi_1"), uiOutput("kpi_2"), uiOutput("kpi_3"), uiOutput("kpi_4")
    ),

    layout_column_wrap(
      width = 1/2, heights_equal = "row",
      card(full_screen = TRUE, height = "620px",
           card_header("Ist + Prognose (MW)"),
           div(class = "p-2",
               div(class = "segment-pills",
                   radioButtons("chart_segment", label = NULL,
                                choices = SEGMENT_CHOICES, selected = "Home",
                                inline = TRUE)),
               uiOutput("segment_hint"),
               plotlyOutput("plot_fc", height = "500px"))),
      card(full_screen = TRUE, height = "620px",
           card_header(sprintf("Restmonate %d \u00d7 vier Segmente", YEAR_NOW)),
           reactableOutput("tbl_fc"))
    ),

    uiOutput("mape_banner"),

    layout_column_wrap(
      width = 1/2, heights_equal = "row",
      card(full_screen = TRUE, height = "520px",
           card_header(sprintf("%d Ist vs. Prognose (trainiert bis Dez %d)",
                               YEAR_NOW, YEAR_NOW - 1L)),
           plotlyOutput("plot_backtest", height = "440px")),
      card(full_screen = TRUE, height = "520px",
           card_header("Modellg\u00fcte auf bekannten Monaten"),
           plotlyOutput("plot_model_mape", height = "440px"))
    ),

    card(full_screen = TRUE,
         card_header(sprintf(
           "Genauigkeit %d je Segment \u2014 eingefroren bis Dezember %d (Ist %d nur Overlay)",
           YEAR_NOW, YEAR_NOW - 1L, YEAR_NOW)),
         reactableOutput("tbl_backtest")),

    layout_column_wrap(
      width = 1/2, heights_equal = "row",
      card(full_screen = TRUE, height = "420px",
           card_header("Modellgewichte (Holdout-MAPE)"),
           plotlyOutput("plot_weights", height = "340px")),
      card(full_screen = TRUE, height = "420px",
           card_header("Saisonprofil \u2014 Anteil am Jahreszubau"),
           plotlyOutput("plot_season", height = "340px"))
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  data_monthly <- reactive({
    metric_col <- if (input$metric == "netto") "Nettonennleistung"
                  else                          "Bruttoleistung"
    active_filter <- if (input$only_active)
      "AND EinheitBetriebsstatus = 35" else ""
    sql <- sprintf("
      SELECT
        CAST(%s AS INTEGER) AS year,
        CAST(%s AS INTEGER) AS month,
        %s AS segment,
        SUM(%s) / 1000.0 AS mw,
        COUNT(*)         AS units
      FROM solar
      WHERE Inbetriebnahmedatum IS NOT NULL
        AND %s IS NOT NULL
        AND %s >= %d
        AND %s <= %d
        %s
      GROUP BY 1, 2, 3
      ORDER BY 1, 2, 3",
      sql_ibn_year("Inbetriebnahmedatum"),
      sql_ibn_month("Inbetriebnahmedatum"),
      sql_segment_3("Bruttoleistung"),
      metric_col,
      metric_col,
      sql_ibn_year("Inbetriebnahmedatum"), input$yr_from,
      sql_ibn_year("Inbetriebnahmedatum"), YEAR_NOW,
      active_filter)
    mastr_query(sql)
  })

  .fc_cache <- new.env(parent = emptyenv())

  bundle <- reactive({
    d <- data_monthly()
    req(nrow(d) > 0)
    key <- paste("v3-frozen", input$yr_from, input$metric, input$only_active, sep = "|")
    if (exists(key, envir = .fc_cache, inherits = FALSE)) {
      return(.fc_cache[[key]])
    }
    res <- withProgress(message = "Ensemble wird berechnet \u2026", value = 0.1, {
      setProgress(0.25, detail = sprintf("Eingefroren bis Dezember %d", YEAR_NOW - 1L))
      bt <- backtest_calendar_year(d, year = YEAR_NOW)
      setProgress(0.85, detail = "Restmonate + Overlay")
      fc <- outlook_from_backtest(bt)
      list(fc = fc, bt = bt)
    })
    if (!is.null(res)) .fc_cache[[key]] <- res
    res
  })

  fc_all <- reactive({
    b <- bundle()
    req(!is.null(b), !is.null(b$fc))
    b$fc
  })

  bt_all <- reactive({
    b <- bundle()
    req(!is.null(b), !is.null(b$bt))
    b$bt
  })

  fc_seg <- reactive({
    all <- fc_all()
    req(!is.null(all), input$chart_segment %in% names(all))
    all[[input$chart_segment]]
  })

  output$segment_hint <- renderUI({
    hint <- SEGMENT_HINTS[[input$chart_segment]]
    last <- fc_seg()$train_end
    extra <- if (!is.null(last))
      sprintf("Modell eingefroren: Dezember %d. Ist %d nur Overlay (Nachmeldung).",
              last$year, last$year + 1L) else ""
    div(class = "mb-2 small text-muted", paste(hint, extra))
  })

  kpi_box <- function(i) {
    fc <- fc_seg()
    req(!is.null(fc))
    if (i > length(fc$mean)) return(NULL)
    yr <- fc$horizon_year[i]; mo <- fc$horizon_month[i]
    mw <- fc$mean[i]
    hist <- fc$history
    ly <- hist$mw[hist$year == (yr - 1L) & hist$month == mo]
    ly <- if (length(ly)) ly[[1]] else NA_real_
    delta <- if (is.finite(ly) && ly > 1) mw / ly - 1 else NA_real_
    bslib::value_box(
      title = sprintf("%s %d", MONTHS_DE[mo], yr),
      value = paste(fmt_mw(mw), "MW"),
      showcase = NULL,
      theme = "success",
      span(class = "small",
           if (is.finite(delta))
             sprintf("vs. %d: %s", yr - 1L, fmt_pct(delta))
           else "kein Vorjahreswert")
    )
  }
  output$kpi_1 <- renderUI(kpi_box(1L))
  output$kpi_2 <- renderUI(kpi_box(2L))
  output$kpi_3 <- renderUI(kpi_box(3L))
  output$kpi_4 <- renderUI(kpi_box(4L))

  output$plot_fc <- renderPlotly({
    fc <- fc_seg()
    req(!is.null(fc))
    hist <- fc$history |> arrange(year, month)
    hist <- utils::tail(hist, 36L)
    hist$date <- month_date(hist$year, hist$month)
    fy <- if (!is.null(fc$frozen_year)) fc$frozen_year else YEAR_NOW
    y_mean <- if (!is.null(fc$year_mean)) fc$year_mean else fc$mean
    y_lo   <- if (!is.null(fc$year_lo)) fc$year_lo else fc$lo
    y_hi   <- if (!is.null(fc$year_hi)) fc$year_hi else fc$hi
    fc_dates <- month_date(rep(fy, length(y_mean)), seq_along(y_mean))
    last_d <- tail(hist$date, 1)
    last_y <- tail(hist$mw, 1)
    ribbon <- data.frame(
      date = c(last_d, fc_dates),
      lo = c(last_y, y_lo),
      hi = c(last_y, y_hi),
      mean = c(last_y, y_mean)
    )
    ov <- fc$overlay
    if (is.null(ov) || !nrow(ov)) {
      ov <- data.frame(year = integer(), month = integer(), mw = numeric(),
                       date = as.Date(character()))
    } else {
      ov$date <- month_date(ov$year, ov$month)
    }
    ly <- lapply(seq_along(y_mean), function(i) {
      m <- i; y <- fy - 1L
      v <- hist$mw[hist$month == m & hist$year == y]
      if (!length(v) && !is.null(fc$history)) {
        v <- fc$history$mw[fc$history$month == m & fc$history$year == y]
      }
      data.frame(date = fc_dates[i],
                 mw = if (length(v)) v[[1]] else NA_real_)
    }) |> bind_rows()

    ist_model <- poly_fit(as.numeric(hist$date), hist$mw, degree = 3L)
    tr_ist <- poly_eval(ist_model, min(hist$date), max(hist$date))
    # Same Ist polynomial (complete years only), continued into the frozen year.
    tr_fc  <- poly_eval(ist_model, min(ribbon$date), max(ribbon$date), n_out = 48L)

    p <- plot_ly() |>
      add_ribbons(data = ribbon, x = ~date, ymin = ~lo, ymax = ~hi,
                  name = "80 %-Band",
                  line = list(color = "transparent", shape = "spline", smoothing = 1.05),
                  fillcolor = "rgba(125, 211, 252, 0.22)",
                  hoverinfo = "skip") |>
      add_trace(data = hist, x = ~date, y = ~mw,
                type = "scatter", mode = "lines+markers",
                name = sprintf("Ist (bis Dez %d)", fy - 1L),
                line = list(color = MATRIX$neon, width = 2.4, shape = "spline",
                            smoothing = 1.05),
                marker = list(color = MATRIX$neon, size = 7,
                              line = list(color = MATRIX$bg, width = 1)),
                hoverinfo = "text",
                text = paste0(hist$year, " \u00b7 ", MONTHS_DE[hist$month], ": ",
                              fmt_mw(hist$mw), " MW"))
    if (nrow(ov) > 0 && "known" %in% names(ov)) {
      ov <- ov[which(ov$known %in% TRUE), ]
    } else if (nrow(ov) > 0) {
      ov <- ov[ov$month <= max(1L, MONTH_NOW - 2L), ]
    }
    if (nrow(ov) > 0) {
      p <- add_trace(p, data = ov, x = ~date, y = ~mw,
                     type = "scatter", mode = "markers",
                     name = sprintf("Ist %d Overlay", fy),
                     marker = list(color = "#fbbf24", size = 9, symbol = "circle-open",
                                   line = list(color = "#fbbf24", width = 2)),
                     hoverinfo = "text",
                     text = paste0(ov$year, " \u00b7 ", MONTHS_DE[ov$month], ": ",
                                   fmt_mw(ov$mw), " MW (Overlay, ohne Nachz\u00fcgler)"))
    }
    if (!is.null(tr_ist)) {
      tr_ist$date <- as.Date(tr_ist$x, origin = "1970-01-01")
      p <- add_trace(p, data = tr_ist, x = ~date, y = ~y,
                     type = "scatter", mode = "lines",
                     name = "Ist-Trend (3. Ordnung)",
                     line = list(color = "#4ade80", width = 2.2, dash = "dot",
                                 shape = "spline", smoothing = 1.3),
                     hoverinfo = "skip")
    }
    p <- add_trace(p, data = ribbon, x = ~date, y = ~mean,
                type = "scatter", mode = "lines+markers",
                name = "Prognose",
                line = list(color = MATRIX$fc, width = 2.6, dash = "dash",
                            shape = "spline", smoothing = 1.05),
                marker = list(color = MATRIX$fc, size = 9,
                              symbol = "diamond",
                              line = list(color = MATRIX$bg, width = 1)),
                hoverinfo = "text",
                text = paste0("Prognose aus Dez ", fy - 1L, " \u00b7 ",
                              format(ribbon$date, "%Y-%m"), ": ",
                              fmt_mw(ribbon$mean), " MW"))
    if (!is.null(tr_fc)) {
      tr_fc$date <- as.Date(tr_fc$x, origin = "1970-01-01")
      p <- add_trace(p, data = tr_fc, x = ~date, y = ~y,
                     type = "scatter", mode = "lines",
                     name = sprintf("Prognose-Trend (%d. Ordnung, aus Ist)",
                                    if (is.null(ist_model)) 3L else ist_model$degree),
                     line = list(color = "#bae6fd", width = 2.2, dash = "dot",
                                 shape = "spline", smoothing = 1.3),
                     hoverinfo = "skip")
    }
    p <- add_trace(p, data = ly, x = ~date, y = ~mw,
                type = "scatter", mode = "markers",
                name = "Vorjahr",
                marker = list(color = MATRIX$muted, size = 8, symbol = "x"),
                hoverinfo = "text",
                text = paste0("Vorjahr: ", fmt_mw(ly$mw), " MW"))
    p |>
      layout(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(7,20,14,0.55)",
        font = list(color = MATRIX$text),
        hovermode = "x unified",
        hoverlabel = list(bgcolor = MATRIX$header, font = list(color = MATRIX$neon),
                          bordercolor = MATRIX$border),
        xaxis = list(title = "", gridcolor = MATRIX$grid, linecolor = MATRIX$border,
                     tickfont = list(color = MATRIX$muted)),
        yaxis = list(title = "MW", gridcolor = MATRIX$grid, linecolor = MATRIX$border,
                     tickfont = list(color = MATRIX$muted), zerolinecolor = MATRIX$border),
        legend = list(orientation = "h", y = 1.08, x = 0.5, xanchor = "center",
                      font = list(color = MATRIX$text), bgcolor = "rgba(0,0,0,0)"),
        margin = list(t = 36, r = 12, b = 36, l = 52)
      ) |>
      config(displaylogo = FALSE, displayModeBar = FALSE)
  })

  output$tbl_fc <- renderReactable({
    all <- fc_all()
    req(!is.null(all))
    ref <- all[[1]]
    rows <- list()
    n_h <- length(ref$horizon_month)
    for (i in seq_len(n_h)) {
      yr <- ref$horizon_year[i]; mo <- ref$horizon_month[i]
      rec <- list(Monat = sprintf("%s %d", MONTHS_DE[mo], yr))
      for (seg in ALL_SEGMENTS) {
        fc <- all[[seg]]
        rec[[paste0(seg, " MW")]] <- fc$mean[i]
        hist <- fc$history
        ly <- hist$mw[hist$year == (yr - 1L) & hist$month == mo]
        ly <- if (length(ly)) ly[[1]] else NA_real_
        rec[[paste0(seg, " vs Vj.")]] <- if (is.finite(ly) && ly > 1)
          fc$mean[i] / ly - 1 else NA_real_
      }
      rows[[i]] <- rec
    }
    d <- bind_rows(rows)

    mw_col <- function(name) colDef(
      name = name, align = "right", minWidth = 88,
      headerStyle = list(color = MATRIX$neon, background = MATRIX$header),
      style = list(background = MATRIX$card, color = MATRIX$text, fontWeight = 600),
      cell = function(value) fmt_mw(value)
    )
    pct_col <- function() colDef(
      name = "vs Vj.", align = "right", minWidth = 72,
      headerStyle = list(color = MATRIX$muted, background = MATRIX$header),
      style = function(value) {
        col <- if (!is.finite(value)) MATRIX$muted
               else if (value >= 0) MATRIX$pos else MATRIX$neg
        list(background = MATRIX$card, color = col, fontStyle = "italic")
      },
      cell = function(value) fmt_pct(value)
    )

    cdefs <- list(
      Monat = colDef(sticky = "left", minWidth = 130,
                     style = list(background = MATRIX$card, color = MATRIX$text,
                                  fontWeight = 600))
    )
    for (seg in ALL_SEGMENTS) {
      cdefs[[paste0(seg, " MW")]] <- mw_col("MW")
      cdefs[[paste0(seg, " vs Vj.")]] <- pct_col()
    }

    reactable(
      d, columns = cdefs,
      columnGroups = lapply(ALL_SEGMENTS, function(seg) {
        colGroup(name = seg, columns = c(paste0(seg, " MW"), paste0(seg, " vs Vj.")))
      }),
      compact = TRUE, bordered = FALSE, highlight = TRUE,
      pagination = FALSE, defaultPageSize = 4,
      theme = reactableTheme(
        color = MATRIX$text, backgroundColor = MATRIX$card,
        borderColor = MATRIX$border, highlightColor = MATRIX$grid,
        headerStyle = list(fontWeight = 600, background = MATRIX$header,
                           color = MATRIX$neon),
        cellPadding = "8px 8px"
      )
    )
  })

  output$plot_weights <- renderPlotly({
    fc <- fc_seg()
    req(!is.null(fc))
    if (identical(fc$segment, "Grand Total") || is.null(fc$weights)) {
      return(
        plot_ly() |>
          add_annotations(text = "Grand Total = Summe der Segment-Ensembles\n(keine eigenen Modellgewichte).",
                          x = 0.5, y = 0.5, xref = "paper", yref = "paper",
                          showarrow = FALSE, font = list(color = MATRIX$muted, size = 14)) |>
          layout(paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
                 xaxis = list(visible = FALSE), yaxis = list(visible = FALSE))
      )
    }
    w <- fc$weights
    mape <- fc$mape[names(w)]
    df <- data.frame(
      model = factor(MODEL_LABELS[names(w)],
                     levels = MODEL_LABELS[names(w)][order(w, decreasing = TRUE)]),
      weight = as.numeric(w) * 100,
      mape = as.numeric(mape),
      stringsAsFactors = FALSE
    )
    df <- df[order(df$weight, decreasing = TRUE), ]
    hover <- paste0(df$model, "<br>Gewicht: ", sprintf("%.1f%%", df$weight),
                    "<br>Holdout-MAPE: ",
                    ifelse(is.finite(df$mape),
                           sprintf("%.1f%%", df$mape * 100), "Prior"))
    plot_ly(df, x = ~weight, y = ~model, type = "bar", orientation = "h",
            marker = list(color = MATRIX$neon),
            hoverinfo = "text", text = hover) |>
      layout(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(7,20,14,0.55)",
        font = list(color = MATRIX$text),
        xaxis = list(title = "Gewicht %", gridcolor = MATRIX$grid,
                     tickfont = list(color = MATRIX$muted)),
        yaxis = list(title = "", automargin = TRUE,
                     tickfont = list(color = MATRIX$muted)),
        margin = list(l = 160, t = 12, r = 12, b = 40)
      ) |>
      config(displaylogo = FALSE, displayModeBar = FALSE)
  })

  output$plot_season <- renderPlotly({
    fc <- fc_seg()
    req(!is.null(fc))
    prof <- seasonal_profile(fc$history)
    if (is.null(prof) || !nrow(prof)) {
      return(plotly_empty() |>
               layout(paper_bgcolor = "rgba(0,0,0,0)"))
    }
    prof$lab <- substr(MONTHS_DE[prof$month], 1, 3)
    plot_ly(prof, x = ~month, y = ~share * 100, type = "bar",
            marker = list(color = MATRIX$neon),
            hoverinfo = "text",
            text = paste0(MONTHS_DE[prof$month], ": ",
                          sprintf("%.1f%%", prof$share * 100),
                          " des Jahres \u00b7 typ. ", fmt_mw(prof$mw_typ), " MW")) |>
      layout(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(7,20,14,0.55)",
        font = list(color = MATRIX$text),
        xaxis = list(title = "", tickmode = "array", tickvals = 1:12,
                     ticktext = substr(MONTHS_DE, 1, 3),
                     tickfont = list(color = MATRIX$muted),
                     gridcolor = MATRIX$grid, linecolor = MATRIX$border),
        yaxis = list(title = "% des Jahreszubaus", gridcolor = MATRIX$grid,
                     tickfont = list(color = MATRIX$muted),
                     linecolor = MATRIX$border),
        margin = list(t = 12, r = 12, b = 36, l = 52)
      ) |>
      config(displaylogo = FALSE, displayModeBar = FALSE)
  })

  output$mape_banner <- renderUI({
    bt <- bt_all()
    req(!is.null(bt))
    chips <- lapply(ALL_SEGMENTS, function(seg) {
      x <- bt$segments[[seg]]
      lab <- if (is.finite(x$mape))
        sprintf("%.1f %% MAPE", x$mape * 100) else "\u2014"
      last_known <- which(x$known)
      div(class = "fc-mape-chip",
          strong(lab),
          span(sprintf("%s \u00b7 %s",
                       seg,
                       if (length(last_known))
                         sprintf("%s\u2013%s", MONTHS_DE[min(last_known)],
                                 MONTHS_DE[max(last_known)])
                       else "kein Ist")))
    })
    thru <- sprintf(
      "Trainiert bis Dezember %d. Ist %d ist Overlay und nicht im Modell. MAPE nur bis %s %d (ohne die letzten zwei Kalendermonate).",
      bt$train_end$year, bt$year,
      MONTHS_DE[bt$known_through$month], bt$known_through$year)
    tagList(
      p(class = "small text-muted mb-2", thru),
      div(class = "fc-mape-banner", chips)
    )
  })

  output$plot_backtest <- renderPlotly({
    bt <- bt_all()
    req(!is.null(bt), input$chart_segment %in% names(bt$segments))
    x <- bt$segments[[input$chart_segment]]
    df <- data.frame(
      month = x$month,
      pred = x$pred,
      lo = x$lo,
      hi = x$hi,
      actual = x$actual,
      known = x$known
    )
    df$lab <- MONTHS_DE[df$month]
    # Never draw current/previous-month MaStR stubs — a spline through
    # September ~0 MW is not a trend, it is incomplete reporting.
    act <- df[which(df$known %in% TRUE & is.finite(df$actual)), ]
    tr_pred <- poly_curve(df$month, df$pred, degree = 3L, n_out = 80L)
    p <- plot_ly() |>
      add_ribbons(data = df, x = ~month, ymin = ~lo, ymax = ~hi,
                  name = "80 %-Band",
                  line = list(color = "transparent", shape = "spline", smoothing = 1.05),
                  fillcolor = "rgba(125, 211, 252, 0.18)",
                  hoverinfo = "skip") |>
      add_trace(data = df, x = ~month, y = ~pred,
                type = "scatter", mode = "lines+markers",
                name = sprintf("Prognose aus %d", bt$train_end$year),
                line = list(color = MATRIX$fc, width = 2.4, dash = "dash",
                            shape = "spline", smoothing = 1.05),
                marker = list(color = MATRIX$fc, size = 8, symbol = "diamond"),
                hoverinfo = "text",
                text = paste0(df$lab, " Prognose: ", fmt_mw(df$pred), " MW"))
    if (!is.null(tr_pred)) {
      p <- add_trace(p, data = tr_pred, x = ~x, y = ~y,
                     type = "scatter", mode = "lines",
                     name = "Prognose-Trend (3. Ordnung)",
                     line = list(color = "#bae6fd", width = 2.2, dash = "dot",
                                 shape = "spline", smoothing = 1.3),
                     hoverinfo = "skip")
    }
    if (nrow(act) > 0) {
      p <- add_trace(p, data = act, x = ~month, y = ~actual,
                type = "scatter", mode = "lines+markers",
                name = sprintf("Ist %d Overlay", bt$year),
                line = list(color = "#fbbf24", width = 1.8, dash = "dot",
                            shape = "spline", smoothing = 1.05),
                marker = list(color = "#fbbf24", size = 9, symbol = "circle-open",
                              line = list(color = "#fbbf24", width = 2)),
                hoverinfo = "text",
                text = paste0(act$lab, " Overlay: ", fmt_mw(act$actual), " MW",
                              " \u00b7 Abw. ",
                              fmt_pct((act$pred - act$actual) / pmax(act$actual, 1))))
    }
    p |>
      layout(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(7,20,14,0.55)",
        font = list(color = MATRIX$text),
        hovermode = "x unified",
        xaxis = list(title = "", tickmode = "array", tickvals = 1:12,
                     ticktext = substr(MONTHS_DE, 1, 3),
                     gridcolor = MATRIX$grid, linecolor = MATRIX$border,
                     tickfont = list(color = MATRIX$muted)),
        yaxis = list(title = "MW", gridcolor = MATRIX$grid,
                     tickfont = list(color = MATRIX$muted),
                     linecolor = MATRIX$border, zerolinecolor = MATRIX$border),
        legend = list(orientation = "h", y = 1.08, x = 0.5, xanchor = "center",
                      font = list(color = MATRIX$text), bgcolor = "rgba(0,0,0,0)"),
        margin = list(t = 36, r = 12, b = 36, l = 52)
      ) |>
      config(displaylogo = FALSE, displayModeBar = FALSE)
  })

  output$plot_model_mape <- renderPlotly({
    bt <- bt_all()
    req(!is.null(bt), input$chart_segment %in% names(bt$segments))
    x <- bt$segments[[input$chart_segment]]
    if (identical(x$segment, "Grand Total") || is.null(x$model_mape)) {
      ens <- if (is.finite(x$mape)) sprintf("Ensemble-MAPE: %.1f%%", x$mape * 100)
             else "Grand Total = Summe der Segmente"
      return(
        plot_ly() |>
          add_annotations(
            text = paste0(ens, "\nKeine Einzelmodell-MAPE f\u00fcr Total."),
            x = 0.5, y = 0.5, xref = "paper", yref = "paper",
            showarrow = FALSE, font = list(color = MATRIX$muted, size = 14)) |>
          layout(paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
                 xaxis = list(visible = FALSE), yaxis = list(visible = FALSE))
      )
    }
    mape <- x$model_mape
    ens <- x$mape
    df <- data.frame(
      model = names(mape),
      mape = as.numeric(mape) * 100,
      stringsAsFactors = FALSE
    )
    df <- df[is.finite(df$mape), ]
    if (!nrow(df)) {
      return(plotly_empty() |> layout(paper_bgcolor = "rgba(0,0,0,0)"))
    }
    df$label <- MODEL_LABELS[df$model]
    df$label[is.na(df$label)] <- df$model
    if (is.finite(ens)) {
      df <- rbind(data.frame(model = "ensemble", mape = ens * 100,
                             label = "Ensemble", stringsAsFactors = FALSE),
                  df)
    }
    df <- df[order(df$mape), ]
    df$label <- factor(df$label, levels = rev(df$label))
    cols <- ifelse(df$model == "ensemble", MATRIX$neon, MATRIX$fc)
    plot_ly(df, x = ~mape, y = ~label, type = "bar", orientation = "h",
            marker = list(color = cols),
            hoverinfo = "text",
            text = paste0(df$label, "<br>MAPE ", sprintf("%.1f%%", df$mape),
                          " auf lag-sicheren Overlay-Monaten ", bt$year)) |>
      layout(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(7,20,14,0.55)",
        font = list(color = MATRIX$text),
        xaxis = list(title = "MAPE % (niedriger = besser)", gridcolor = MATRIX$grid,
                     tickfont = list(color = MATRIX$muted)),
        yaxis = list(title = "", automargin = TRUE,
                     tickfont = list(color = MATRIX$muted)),
        margin = list(l = 170, t = 12, r = 12, b = 40)
      ) |>
      config(displaylogo = FALSE, displayModeBar = FALSE)
  })

  output$tbl_backtest <- renderReactable({
    bt <- bt_all()
    req(!is.null(bt))
    rows <- list()
    for (m in seq_len(12L)) {
      rec <- list(Monat = MONTHS_DE[m])
      any_known <- FALSE
      any_overlay <- FALSE
      for (seg in ALL_SEGMENTS) {
        x <- bt$segments[[seg]]
        rec[[paste0(seg, " Ist")]] <- if (is.finite(x$actual[m])) x$actual[m] else NA_real_
        rec[[paste0(seg, " Prog")]] <- x$pred[m]
        rec[[paste0(seg, " Abw")]] <- if (is.finite(x$actual[m]) && x$actual[m] > 1)
          (x$pred[m] - x$actual[m]) / x$actual[m] else NA_real_
        if (isTRUE(x$known[m])) any_known <- TRUE
        if (is.finite(x$actual[m])) any_overlay <- TRUE
      }
      rec$Status <- if (any_known) "lag-sicher"
                    else if (isTRUE(any_overlay)) "vorl\u00e4ufig"
                    else "noch offen"
      rows[[m]] <- rec
    }
    # Summary: sums over known months + MAPE
    sum_rec <- list(Monat = "Summe (lag-sichere Monate)", Status = "")
    mape_rec <- list(Monat = "MAPE", Status = "")
    for (seg in ALL_SEGMENTS) {
      x <- bt$segments[[seg]]
      kn <- x$known
      sum_rec[[paste0(seg, " Ist")]] <- if (any(kn)) sum(x$actual[kn], na.rm = TRUE) else NA_real_
      sum_rec[[paste0(seg, " Prog")]] <- if (any(kn)) sum(x$pred[kn], na.rm = TRUE) else NA_real_
      ist <- sum_rec[[paste0(seg, " Ist")]]
      pr  <- sum_rec[[paste0(seg, " Prog")]]
      sum_rec[[paste0(seg, " Abw")]] <- if (is.finite(ist) && ist > 1) (pr - ist) / ist else NA_real_
      mape_rec[[paste0(seg, " Ist")]] <- NA_real_
      mape_rec[[paste0(seg, " Prog")]] <- NA_real_
      mape_rec[[paste0(seg, " Abw")]] <- x$mape
    }
    d <- bind_rows(bind_rows(rows), sum_rec, mape_rec)
    n_d <- nrow(d)

    ape_style <- function(value, index) {
      base <- list(background = MATRIX$card, fontStyle = "italic")
      if (index > 12L) base$fontWeight <- 700
      if (!is.finite(value)) return(modifyList(base, list(color = MATRIX$muted)))
      col <- if (abs(value) <= 0.15) MATRIX$pos
             else if (abs(value) <= 0.30) "#fbbf24"
             else MATRIX$neg
      modifyList(base, list(color = col))
    }
    mw_style <- function(value, index) {
      list(background = MATRIX$card, color = MATRIX$text,
           fontWeight = if (index > 12L) 700 else 500)
    }
    mw_col <- function(name) colDef(
      name = name, align = "right", minWidth = 78,
      headerStyle = list(color = MATRIX$neon, background = MATRIX$header),
      style = function(value, index) mw_style(value, index),
      cell = function(value, index) {
        if (index == n_d) "" else fmt_mw(value)
      }
    )
    ape_col <- function() colDef(
      name = "Abw.", align = "right", minWidth = 72,
      headerStyle = list(color = MATRIX$muted, background = MATRIX$header),
      style = function(value, index) ape_style(value, index),
      cell = function(value, index) {
        if (index == n_d && is.finite(value))
          sprintf("%.1f%%", abs(value) * 100)
        else fmt_pct(value)
      }
    )

    cdefs <- list(
      Monat = colDef(sticky = "left", minWidth = 150,
                     style = function(value, index) {
                       list(background = MATRIX$card, color = MATRIX$text,
                            fontWeight = if (index > 12L) 700 else 600)
                     }),
      Status = colDef(name = "", minWidth = 92,
                      style = function(value) {
                        list(background = MATRIX$card, color = MATRIX$muted,
                             fontSize = "0.78rem")
                      })
    )
    for (seg in ALL_SEGMENTS) {
      cdefs[[paste0(seg, " Ist")]] <- mw_col("Ist")
      cdefs[[paste0(seg, " Prog")]] <- mw_col("Prognose")
      cdefs[[paste0(seg, " Abw")]] <- ape_col()
    }

    reactable(
      d, columns = cdefs,
      columnGroups = lapply(ALL_SEGMENTS, function(seg) {
        colGroup(name = seg, columns = c(
          paste0(seg, " Ist"), paste0(seg, " Prog"), paste0(seg, " Abw")))
      }),
      compact = TRUE, bordered = FALSE, highlight = TRUE,
      pagination = FALSE, defaultPageSize = 14, minRows = 14,
      rowStyle = function(index) {
        if (index == 13L) list(borderTop = paste("2px solid", MATRIX$neon))
        else if (!is.null(d$Status[index]) && d$Status[index] %in% c("noch offen", "vorl\u00e4ufig"))
          list(opacity = 0.72)
        else NULL
      },
      theme = reactableTheme(
        color = MATRIX$text, backgroundColor = MATRIX$card,
        borderColor = MATRIX$border, highlightColor = MATRIX$grid,
        headerStyle = list(fontWeight = 600, background = MATRIX$header,
                           color = MATRIX$neon),
        cellPadding = "7px 6px"
      )
    )
  })
}

shinyApp(ui, server)
