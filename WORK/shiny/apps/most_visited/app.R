# =============================================================================
# most_visited :: flagship in-house R Shiny replica of the Tableau panel that
# Candida's team posts to the dashboard feed each month.
#
# Source Tableau panel:
#   "Aktuelle Zubauleistung für <Monat> in DE pro Segment.
#    Monate im Vergleich zu den Vorjahren über alle Segmente.
#    Segmente enthalten Anlagen wie folgt:
#       <10 kW = Home, <1 MW = C&I, Rest Large Scale."
#
# Parity goals (match what Candida generates):
#   1. Monthly new-capacity (DC/Brutto MW) as one chart at a time, with pills
#      to switch Home / C&I / Large Scale / Grand Total; one colored spline
#      per year yr_from..current.
#   2. Year-to-date columns highlighted with a translucent green band.
#   3. Side table "IBN Differenz der Vorjahre - Total | Brutto/DC-Leistung MW"
#      — YTD months × last 5-6 years, two rows per month (Wert + Abw. zu
#      Vorjahr), layout mirrors the Candida screenshot 1:1.
#
# Data differences from Tableau:
#   - Candida re-buckets Einheiten after BNetzA's size classes; we apply the
#     same Home/C&I/Large-Scale split on Bruttoleistung (kW) at query time.
#   - We read the raw solar parquet through DuckDB httpfs, so the numbers
#     come from the SAME BNetzA MaStR source, one night newer than Tableau.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable)
  library(dplyr); library(tidyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")

YEAR_NOW  <- as.integer(format(Sys.Date(), "%Y"))
MONTH_NOW <- as.integer(format(Sys.Date(), "%m"))

# Dark Matrix greens: dim forest (oldest) -> neon (current year).
SEGMENT_YEAR_COLORS <- function(years) {
  n <- length(years)
  pal <- c("#163d28", "#1a5c38", "#1f7a48", "#26a65a", "#4ade80", "#00ff41")
  if (n <= length(pal)) {
    tail(pal, n)
  } else {
    grDevices::colorRampPalette(pal)(n)
  }
}

# Shared tokens for bslib / plotly / reactable.
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
  neg    = "#ff6b6b"
)

matrix_theme <- function() {
  bslib::bs_theme(
    version = 5,
    bg = MATRIX$bg,
    fg = MATRIX$text,
    primary = MATRIX$neon,
    secondary = MATRIX$dim,
    success = MATRIX$pos,
    info = "#22c55e",
    warning = "#86efac",
    danger = MATRIX$neg,
    base_font = bslib::font_google("Inter", local = FALSE),
    heading_font = bslib::font_google("Inter", local = FALSE),
    "font-size-base" = "0.95rem"
  )
}

matrix_css <- tags$style(HTML(sprintf("
  html { color-scheme: dark; }
  body, .bslib-page-fluid, .bslib-page-fill {
    background:
      radial-gradient(ellipse at top, #0d2818 0%%, %s 58%%) !important;
    color: %s;
  }
  h2.mb-0 {
    color: %s;
    text-shadow: 0 0 18px rgba(0, 255, 65, 0.22);
  }
  .text-muted, .text-muted.mb-0, small.text-muted { color: %s !important; }
  a, a:link, #hub_back { color: %s !important; }
  a:hover, #hub_back:hover { color: #39ff14 !important; }
  hr { border-color: %s; opacity: 1; }
  code {
    color: %s;
    background: %s;
    border: 1px solid %s;
  }
  .card {
    background: %s !important;
    border: 1px solid %s !important;
    box-shadow: 0 0 28px rgba(0, 255, 65, 0.07);
    color: %s;
  }
  .card-header {
    background: %s !important;
    border-bottom: 1px solid %s !important;
    color: %s !important;
  }
  .bslib-sidebar-layout > .sidebar {
    background: #050d09 !important;
    border-right: 1px solid %s !important;
    color: %s;
  }
  .bslib-sidebar-layout > .main { background: transparent !important; }
  .alert-info {
    background: %s !important;
    border-color: %s !important;
    color: %s !important;
  }
  .form-check-input {
    background-color: %s;
    border-color: %s;
  }
  .form-check-input:checked {
    background-color: %s;
    border-color: %s;
  }
  .form-check-label, .control-label, .shiny-input-container label { color: %s; }
  .irs--shiny .irs-bar {
    background: %s;
    border-top-color: %s;
    border-bottom-color: %s;
  }
  .irs--shiny .irs-line {
    background: %s;
    border-color: %s;
  }
  .irs--shiny .irs-handle {
    background: %s;
    border: 1px solid %s;
    box-shadow: 0 0 8px rgba(0, 255, 65, 0.4);
  }
  .irs--shiny .irs-single, .irs--shiny .irs-from, .irs--shiny .irs-to {
    background: %s;
    color: #04110a;
  }
  .irs--shiny .irs-min, .irs--shiny .irs-max {
    background: %s;
    color: %s;
  }
  .irs--shiny .irs-grid-pol { background: %s; }
  .irs--shiny .irs-grid-text { color: %s; }
  .mastr-footer {
    color: %s !important;
    border-top-color: %s !important;
  }
  .mastr-footer a { color: %s !important; }
  .mastr-creator-qr, .mastr-creator-qr-tab {
    background: %s !important;
    border-color: %s !important;
    color: %s !important;
    box-shadow: 0 4px 18px rgba(0, 255, 65, 0.12) !important;
  }
  .mastr-creator-qr-text { color: %s !important; }
  .mastr-creator-qr-text strong { color: %s !important; }
  .mastr-creator-qr-tab:hover { background: %s !important; color: %s !important; }
  .mastr-creator-qr-tab:focus-visible { outline-color: %s !important; }
  .js-plotly-plot .plotly .bg { fill: transparent !important; }
  .reactable, .rt-table, .ReactTable {
    background: #0a1610 !important;
    color: #c8ffd4 !important;
  }
  .bslib-sidebar-title, .sidebar-title { color: #00ff41 !important; }
  .irs-bar { background: #00ff41 !important; border-color: #00ff41 !important; }
  .irs-line { background: #14532d !important; border-color: #1a4d32 !important; }
  .irs-handle { border-color: #00ff41 !important; background: #07140e !important; }
  .irs-single, .irs-from, .irs-to { background: #00ff41 !important; color: #04110a !important; }
  .irs-min, .irs-max { background: #14532d !important; color: #6ee7b7 !important; }
  .irs-grid-text { color: #6ee7b7 !important; }
  .irs-grid-pol { background: #1a4d32 !important; }
  .collapse-toggle, .bslib-sidebar-toggle { color: #00ff41 !important; }
  .segment-pills .shiny-input-container { margin-bottom: 0.35rem; }
  .segment-pills .shiny-options-group {
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
    margin-bottom: 0.25rem;
  }
  .segment-pills .form-check {
    padding-left: 0;
    margin: 0;
  }
  .segment-pills .form-check-input {
    position: absolute;
    opacity: 0;
    pointer-events: none;
  }
  .segment-pills .form-check-label {
    display: inline-block;
    margin: 0;
    cursor: pointer;
    border-radius: 999px;
    border: 1px solid #1a4d32;
    background: #07140e;
    color: #6ee7b7;
    padding: 0.28rem 0.9rem;
    font-size: 0.82rem;
    font-weight: 600;
    line-height: 1.3;
  }
  .segment-pills .form-check-label:hover {
    border-color: #00ff41;
    color: #c8ffd4;
  }
  .segment-pills .form-check-input:checked + .form-check-label,
  .segment-pills .form-check-input:checked ~ .form-check-label,
  .segment-pills .form-check:has(.form-check-input:checked) .form-check-label {
    background: #00ff41;
    border-color: #00ff41;
    color: #04110a;
    box-shadow: 0 0 12px rgba(0, 255, 65, 0.28);
  }
  .segment-pills .form-check-input:focus-visible + .form-check-label {
    outline: 2px solid #00ff41;
    outline-offset: 2px;
  }
",
  MATRIX$bg, MATRIX$text, MATRIX$neon, MATRIX$muted, MATRIX$neon, MATRIX$border,
  MATRIX$neon, MATRIX$header, MATRIX$border,
  MATRIX$card, MATRIX$border, MATRIX$text,
  MATRIX$header, MATRIX$border, MATRIX$neon,
  MATRIX$border, MATRIX$text,
  MATRIX$header, MATRIX$border, MATRIX$muted,
  MATRIX$card, MATRIX$border, MATRIX$neon, MATRIX$neon, MATRIX$text,
  MATRIX$neon, MATRIX$neon, MATRIX$neon,
  MATRIX$dim, MATRIX$border,
  MATRIX$panel, MATRIX$neon,
  MATRIX$neon,
  MATRIX$dim, MATRIX$muted,
  MATRIX$border, MATRIX$muted,
  MATRIX$muted, MATRIX$border, MATRIX$neon,
  MATRIX$header, MATRIX$border, MATRIX$text,
  MATRIX$muted, MATRIX$neon,
  MATRIX$dim, MATRIX$neon, MATRIX$neon
)))

SEGMENTS <- c("Home", "C&I", "Large Scale", "Grand Total")
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
  `Grand Total` = "Alle Segmente zusammen"
)

ui <- mastr_page(
  title = "Most Visited \u2014 Zubauleistung pro Segment (R Shiny-Nachbau)",
  subtitle = sprintf(
    "Aktuelle Zubauleistung f\u00fcr %s in DE pro Segment. Monate im Vergleich zu den Vorjahren \u00fcber alle Segmente. Segmente enthalten Anlagen wie folgt: <10 kW = Home, <1 MW = C&I, Rest Large Scale.",
    MONTHS_DE[MONTH_NOW]),
  fluid = TRUE,
  theme = matrix_theme(),
  tags$head(tags$meta(name = "theme-color", content = "#00ff41")),
  matrix_css,
  tags$script(HTML("
    (function () {
      function graphDiv(root) {
        if (!root) return null;
        if (root.classList && root.classList.contains('js-plotly-plot')) return root;
        return root.querySelector ? root.querySelector('.js-plotly-plot') : null;
      }
      function bind(gd) {
        if (!gd || typeof gd.on !== 'function') return;
        if (typeof gd.removeAllListeners === 'function') {
          gd.removeAllListeners('plotly_hover');
          gd.removeAllListeners('plotly_unhover');
        }
        gd.on('plotly_hover', function (evt) {
          if (!evt || !evt.points || !evt.points.length || !gd.data) return;
          var cn = evt.points[0].curveNumber;
          var n = gd.data.length;
          var off = [];
          for (var i = 0; i < n; i++) if (i !== cn) off.push(i);
          if (off.length) Plotly.restyle(gd, {opacity: 0.14}, off);
          Plotly.restyle(gd, {opacity: 1}, [cn]);
        });
        gd.on('plotly_unhover', function () {
          if (!gd.data) return;
          var all = [];
          for (var i = 0; i < gd.data.length; i++) all.push(i);
          Plotly.restyle(gd, {opacity: 1}, all);
        });
      }
      function scan() {
        bind(graphDiv(document.getElementById('plot_segment')));
      }
      if (window.jQuery) {
        $(document).on('plotly_afterplot', function (e) {
          var t = e.target;
          if (!t) return;
          if (t.id === 'plot_segment' || (t.closest && t.closest('#plot_segment'))) {
            bind(graphDiv(t) || t);
          }
        });
        $(document).on('shiny:value shiny:visualchange shiny:idle', scan);
      }
      document.addEventListener('change', function (e) {
        if (e.target && e.target.name && String(e.target.name).indexOf('chart_segment') !== -1) {
          setTimeout(scan, 200);
          setTimeout(scan, 600);
        }
      }, true);
    })();
  ")),

  tableau_parity_banner("Aktuelle Zubauleistung pro Segment (Tableau-Referenz)"),

  layout_sidebar(
    sidebar = sidebar(
      title = "Einstellungen", width = 280,
      sliderInput("yr_from", "Vergleichs-Startjahr",
                  min = 2015, max = YEAR_NOW - 1,
                  value = max(2022, YEAR_NOW - 4),
                  sep = "", step = 1, ticks = FALSE),
      sliderInput("ytd_m",  "YTD bis Monat",
                  min = 1, max = 12, value = MONTH_NOW,
                  step = 1, ticks = FALSE),
      radioButtons("metric", "Metrik",
                   choices = c("Brutto/DC-Leistung MW" = "brutto",
                               "Nettonennleistung MW"  = "netto"),
                   selected = "brutto"),
      checkboxInput("only_active", "Nur aktive Einheiten", value = FALSE),
      tags$hr(),
      tags$p(
        tags$a(
          href = if (identical(Sys.getenv("MASTR_HUB_MODE", "paths"), "ports"))
            "http://localhost:3856/" else "/most_visited_forecast/",
          style = "display:inline-block;font-weight:700;border-radius:999px;padding:0.28rem 0.85rem;background:#00ff41;color:#04110a !important;text-decoration:none;",
          "4-Monats-Prognose \u2192"
        )
      ),
      tags$small(class = "text-muted",
        "Daten live aus dem neuesten GitHub-Release (", code("runGitHub"),
        "). Quelle BNetzA MaStR.")
    ),

    # Left = one segment chart (pills switch Home / C&I / Large Scale / Total).
    # Right = the Candida-style YTD diff table.
    layout_column_wrap(
      width = 1/2, heights_equal = "row",

      card(full_screen = TRUE, height = "720px",
           card_header("MaStR \u2014 monatlicher Zubau pro Segment (MW)"),
           div(class = "p-2",
               div(class = "segment-pills",
                   radioButtons(
                     "chart_segment",
                     label = NULL,
                     choices = SEGMENT_CHOICES,
                     selected = "Home",
                     inline = TRUE
                   )),
               uiOutput("segment_hint"),
               plotlyOutput("plot_segment", height = "560px"))),

      card(full_screen = TRUE, height = "720px",
           card_header(sprintf(
             "IBN Differenz der Vorjahre \u2014 Total | %s",
             "Brutto/DC-Leistung MW")),
           reactableOutput("tbl_diff", height = "auto"))
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

  data_with_total <- reactive({
    d <- data_monthly()
    if (!nrow(d)) return(d)
    d$segment <- as.character(d$segment)
    total <- d |>
      group_by(year, month) |>
      summarise(mw = sum(mw, na.rm = TRUE),
                units = sum(units, na.rm = TRUE),
                segment = "Grand Total",
                .groups = "drop")
    bind_rows(d, total)
  })

  # ----- one segment at a time (pills) ---------------------------------------
  output$segment_hint <- renderUI({
    hint <- SEGMENT_HINTS[[input$chart_segment]]
    if (is.null(hint)) return(NULL)
    div(class = "mb-2 small text-muted", hint)
  })

  make_segment_plot <- function(segment_name) {
    d <- data_with_total()
    if (!nrow(d) || !(segment_name %in% d$segment))
      return(
        plotly_empty(type = "scatter", mode = "lines") |>
          layout(paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
                 font = list(color = MATRIX$text))
      )
    dd <- d |> filter(segment == segment_name) |>
      mutate(year = as.integer(year), month = as.integer(month)) |>
      arrange(year, month)
    years <- sort(unique(dd$year))
    cols  <- setNames(SEGMENT_YEAR_COLORS(years), as.character(years))

    p <- plot_ly(height = 560)
    for (y in years) {
      dy <- dd |> filter(year == y)
      is_current <- (y == YEAR_NOW)
      p <- add_trace(p,
                     data = dy,
                     x = ~month, y = ~mw,
                     name = as.character(y),
                     legendgroup = as.character(y),
                     showlegend = TRUE,
                     type = "scatter",
                     mode = "lines+markers",
                     cliponaxis = FALSE,
                     opacity = 1,
                     line = list(color = cols[[as.character(y)]],
                                 width = if (is_current) 3 else 2,
                                 shape = "spline",
                                 smoothing = 1.05),
                     marker = list(
                       color = cols[[as.character(y)]],
                       size = if (is_current) 10 else 8,
                       opacity = 1,
                       line = list(color = MATRIX$bg, width = 1.5)
                     ),
                     hoverinfo = "text",
                     text = paste0(y, " \u00b7 ", MONTHS_DE[dy$month], ": ",
                                   round(dy$mw), " MW"))
    }
    p |> layout(
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor = "rgba(7,20,14,0.55)",
      font = list(color = MATRIX$text),
      hovermode = "closest",
      hoverdistance = 80,
      spikedistance = -1,
      hoverlabel = list(bgcolor = MATRIX$header, font = list(color = MATRIX$neon),
                        bordercolor = MATRIX$border),
      shapes = list(list(
        type = "rect", xref = "x", yref = "paper",
        x0 = 0.5, x1 = input$ytd_m + 0.5, y0 = 0, y1 = 1,
        fillcolor = MATRIX$neon, opacity = 0.10, line = list(width = 0))),
      xaxis = list(title = "",
                   tickmode = "array", tickvals = 1:12,
                   ticktext = substr(MONTHS_DE, 1, 3),
                   tickangle = 0,
                   tickfont = list(size = 11, color = MATRIX$muted),
                   gridcolor = MATRIX$grid, linecolor = MATRIX$border,
                   zeroline = FALSE),
      yaxis = list(title = list(text = "MW", standoff = 4, font = list(color = MATRIX$muted)),
                   automargin = TRUE,
                   tickfont = list(size = 11, color = MATRIX$muted),
                   gridcolor = MATRIX$grid, linecolor = MATRIX$border,
                   zeroline = TRUE, zerolinecolor = MATRIX$border),
      margin = list(t = 36, r = 12, b = 36, l = 52),
      showlegend = TRUE,
      legend = list(orientation = "h", y = 1.08, x = 0.5,
                    xanchor = "center", yanchor = "bottom",
                    font = list(size = 12, color = MATRIX$text),
                    bgcolor = "rgba(0,0,0,0)")
    ) |>
      config(displaylogo = FALSE, displayModeBar = FALSE) |>
      htmlwidgets::onRender("
        function(el, x) {
          var gd = el;
          if (el.querySelector) {
            var inner = el.querySelector('.js-plotly-plot');
            if (inner) gd = inner;
          }
          if (!gd || typeof gd.on !== 'function') return;
          if (typeof gd.removeAllListeners === 'function') {
            gd.removeAllListeners('plotly_hover');
            gd.removeAllListeners('plotly_unhover');
          }
          gd.on('plotly_hover', function(evt) {
            if (!evt || !evt.points || !evt.points.length || !gd.data) return;
            var cn = evt.points[0].curveNumber;
            var n = gd.data.length;
            var off = [];
            for (var i = 0; i < n; i++) if (i !== cn) off.push(i);
            if (off.length) Plotly.restyle(gd, {opacity: 0.14}, off);
            Plotly.restyle(gd, {opacity: 1}, [cn]);
          });
          gd.on('plotly_unhover', function() {
            if (!gd.data) return;
            var all = [];
            for (var i = 0; i < gd.data.length; i++) all.push(i);
            Plotly.restyle(gd, {opacity: 1}, all);
          });
        }
      ")
  }

  output$plot_segment <- renderPlotly({
    req(input$chart_segment)
    make_segment_plot(input$chart_segment)
  })

  # ----- Candida-style YTD diff table ----------------------------------------
  # Layout: 1 row per month, sub-rows ("Wert" + "Abw. zu Vorjahr") via a
  # "Kennzahl" column. One column per year (newest on the right). Every year
  # fits in the visible width, so 2026 is always visible.
  table_diff <- reactive({
    d <- data_monthly()
    if (!nrow(d)) return(NULL)

    ytd_m <- input$ytd_m
    total <- d |>
      group_by(year, month) |>
      summarise(mw = sum(mw, na.rm = TRUE), .groups = "drop") |>
      filter(month <= ytd_m)

    years <- sort(unique(total$year))
    yr_cols <- as.character(years)

    wide <- total |>
      mutate(MonthName = factor(MONTHS_DE[month], levels = MONTHS_DE)) |>
      select(MonthName, year, mw) |>
      tidyr::pivot_wider(names_from = year, values_from = mw,
                         values_fill = 0, names_prefix = "y_")

    wide <- wide[, c("MonthName", paste0("y_", yr_cols))]
    names(wide)[-1] <- yr_cols
    wide <- wide |> arrange(MonthName)

    # Build the Wert rows and the % rows.
    wert_df <- wide |> mutate(Kennzahl = "Wert", .after = MonthName)
    abw_df  <- wide |> mutate(Kennzahl = "Abw. zu Vorjahr", .after = MonthName)
    for (i in seq_along(yr_cols)) {
      if (i == 1) { abw_df[[yr_cols[i]]] <- NA_real_; next }
      prev <- yr_cols[i - 1]; y <- yr_cols[i]
      abw_df[[y]] <- (wide[[y]] - wide[[prev]]) / wide[[prev]]
    }

    bind_rows(wert_df, abw_df) |>
      arrange(MonthName, match(Kennzahl, c("Wert", "Abw. zu Vorjahr")))
  })

  output$tbl_diff <- renderReactable({
    d <- table_diff()
    if (is.null(d) || !nrow(d)) return(reactable(data.frame()))

    yr_cols <- grep("^\\d{4}$", names(d), value = TRUE)

    # Tight column widths so every year (including YEAR_NOW) fits inside the
    # half-width card without triggering a horizontal scrollbar.
    # Budget at ~560 px card width:  Monat 78 + Kennzahl 82 + N×60  ≈ 480-540
    n_years  <- length(yr_cols)
    year_w   <- if (n_years <= 5) 68 else if (n_years == 6) 60 else 54

    cdefs <- c(
      list(
        MonthName = colDef(name = "Monat", minWidth = 78, sticky = "left",
                           style = list(background = MATRIX$card, color = MATRIX$text),
                           cell = function(value, index, name) {
                             if (d$Kennzahl[index] == "Wert") as.character(value) else ""
                           }),
        Kennzahl  = colDef(name = "", minWidth = 82, sticky = "left",
                           style = function(value) list(color = MATRIX$muted,
                                                        background = MATRIX$card,
                                                        fontStyle = "italic",
                                                        whiteSpace = "nowrap",
                                                        fontSize = "0.78rem"),
                           cell = function(value) {
                             if (value == "Abw. zu Vorjahr") "Abw. Vj." else value
                           })
      ),
      setNames(lapply(yr_cols, function(y) colDef(
        name = y, align = "right", minWidth = year_w,
        headerStyle = list(fontWeight = 600, color = MATRIX$neon,
                           background = if (y == as.character(YEAR_NOW))
                             MATRIX$dim else MATRIX$header),
        style = function(value, index) {
          base <- if (y == as.character(YEAR_NOW))
            list(background = "#0f2a18", color = MATRIX$text) else
              list(background = MATRIX$card, color = MATRIX$text)
          if (d$Kennzahl[index] == "Wert")
            return(modifyList(base, list(fontWeight = 500, whiteSpace = "nowrap")))
          if (is.na(value) || !is.numeric(value)) return(base)
          col <- if (value >= 0) MATRIX$pos else MATRIX$neg
          modifyList(base, list(color = col, fontStyle = "italic",
                                whiteSpace = "nowrap"))
        },
        cell = function(value, index) {
          if (d$Kennzahl[index] == "Wert") {
            formatC(value, big.mark = ".", decimal.mark = ",",
                    format = "f", digits = 0)
          } else if (is.na(value)) {
            ""
          } else {
            # Keep it on ONE line: no space before % and 1 decimal when the
            # column is narrow, 2 decimals when there's room.
            digits <- if (n_years <= 5) 1 else 1
            sprintf("%s%s%%",
                    if (value >= 0) "+" else "",
                    formatC(value * 100, big.mark = ".", decimal.mark = ",",
                            format = "f", digits = digits))
          }
        })), yr_cols)
    )

    reactable(
      d, columns = cdefs,
      compact = TRUE, bordered = FALSE, highlight = TRUE, striped = FALSE,
      defaultPageSize = 24, minRows = 1,
      pagination = FALSE,
      rowStyle = function(index) {
        if (d$Kennzahl[index] == "Wert") list(borderTop = paste("1px solid", MATRIX$border)) else NULL
      },
      theme = reactableTheme(
        color = MATRIX$text,
        backgroundColor = MATRIX$card,
        borderColor = MATRIX$border,
        highlightColor = MATRIX$grid,
        headerStyle = list(fontWeight = 600, background = MATRIX$header, color = MATRIX$neon),
        cellPadding = "5px 6px"
      )
    )
  })
}

shinyApp(ui, server)
