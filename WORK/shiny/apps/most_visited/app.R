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
#   1. Four vertically stacked small multiples (Home / C&I / Large Scale /
#      Grand Total) of monthly new-capacity (DC/Brutto MW), one colored line
#      per year yr_from..current.
#   2. Year-to-date columns highlighted with a light orange band.
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

# Color palette aligned with the Candida screenshot:
# light blue (oldest) -> dark grey -> orange (current year).
SEGMENT_YEAR_COLORS <- function(years) {
  n <- length(years)
  pal <- c("#a8c9e2","#7b9db7","#5e7a8e","#3f4a57","#f97316")
  if (n <= length(pal)) tail(pal, n) else c(rep(pal[1], n - length(pal) + 1), pal[-1])
}

SEGMENTS <- c("Home", "C&I", "Large Scale", "Grand Total")

ui <- mastr_page(
  title = "Most Visited \u2014 Zubauleistung pro Segment (R Shiny-Nachbau)",
  subtitle = sprintf(
    "Aktuelle Zubauleistung f\u00fcr %s in DE pro Segment. Monate im Vergleich zu den Vorjahren \u00fcber alle Segmente. Segmente enthalten Anlagen wie folgt: <10 kW = Home, <1 MW = C&I, Rest Large Scale.",
    MONTHS_DE[MONTH_NOW]),
  fluid = TRUE,

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
      tags$small(class = "text-muted",
        "Daten live aus dem neuesten GitHub-Release (", code("runGitHub"),
        "). Quelle BNetzA MaStR.")
    ),

    # 2-column layout: left = 4 stacked small multiples (each its own plotly),
    # right = the Candida-style YTD diff table.
    layout_column_wrap(
      width = 1/2, heights_equal = "row",

      card(full_screen = TRUE, height = "720px",
           card_header("MaStR \u2014 monatlicher Zubau pro Segment (MW)"),
           div(class = "p-2",
               div(class = "mb-1 small text-muted fw-semibold", "Home (< 10 kW)"),
               plotlyOutput("plot_home",   height = "130px"),
               div(class = "mb-1 small text-muted fw-semibold mt-2", "C&I (10 kW \u2013 < 1 MW)"),
               plotlyOutput("plot_ci",     height = "130px"),
               div(class = "mb-1 small text-muted fw-semibold mt-2", "Large Scale (\u2265 1 MW)"),
               plotlyOutput("plot_large",  height = "130px"),
               div(class = "mb-1 small text-muted fw-semibold mt-2", "Grand Total"),
               plotlyOutput("plot_total",  height = "140px"))),

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

  # ----- one small-multiple per segment --------------------------------------
  make_segment_plot <- function(segment_name, show_legend = FALSE) {
    d <- data_with_total()
    if (!nrow(d) || !(segment_name %in% d$segment))
      return(plotly_empty(type = "scatter", mode = "lines"))
    dd <- d |> filter(segment == segment_name) |>
      mutate(year = as.integer(year), month = as.integer(month)) |>
      arrange(year, month)
    years <- sort(unique(dd$year))
    cols  <- setNames(SEGMENT_YEAR_COLORS(years), as.character(years))

    p <- plot_ly(height = if (segment_name == "Grand Total") 140 else 130)
    for (y in years) {
      dy <- dd |> filter(year == y)
      is_current <- (y == YEAR_NOW)
      p <- add_trace(p,
                     data = dy,
                     x = ~month, y = ~mw,
                     name = as.character(y),
                     legendgroup = as.character(y),
                     showlegend = show_legend,
                     type = "scatter", mode = "lines+markers",
                     line = list(color = cols[[as.character(y)]],
                                 width = if (is_current) 3 else 1.5),
                     marker = list(color = cols[[as.character(y)]],
                                   size = if (is_current) 6 else 4),
                     hovertemplate = paste0(as.character(y),
                                            " \u00b7 %{x}: %{y:,.0f} MW<extra></extra>"))
    }
    p |> layout(
      shapes = list(list(
        type = "rect", xref = "x", yref = "paper",
        x0 = 0.5, x1 = input$ytd_m + 0.5, y0 = 0, y1 = 1,
        fillcolor = "#fde68a", opacity = 0.25, line = list(width = 0))),
      xaxis = list(title = "",
                   tickmode = "array", tickvals = 1:12,
                   ticktext = substr(MONTHS_DE, 1, 3),
                   tickangle = 0, tickfont = list(size = 10)),
      yaxis = list(title = list(text = "MW", standoff = 4),
                   automargin = TRUE, tickfont = list(size = 10),
                   zeroline = TRUE, zerolinecolor = "#e5e7eb"),
      margin = list(t = 8, r = 8, b = 22, l = 46),
      showlegend = show_legend,
      legend = list(orientation = "h", y = 1.18, x = 0.5,
                    xanchor = "center", yanchor = "bottom",
                    font = list(size = 11))
    ) |>
      config(displaylogo = FALSE, displayModeBar = FALSE)
  }

  output$plot_home  <- renderPlotly(make_segment_plot("Home",        show_legend = TRUE))
  output$plot_ci    <- renderPlotly(make_segment_plot("C&I",         show_legend = FALSE))
  output$plot_large <- renderPlotly(make_segment_plot("Large Scale", show_legend = FALSE))
  output$plot_total <- renderPlotly(make_segment_plot("Grand Total", show_legend = FALSE))

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
                           cell = function(value, index, name) {
                             if (d$Kennzahl[index] == "Wert") as.character(value) else ""
                           }),
        Kennzahl  = colDef(name = "", minWidth = 82, sticky = "left",
                           style = function(value) list(color = "#6b7280",
                                                        fontStyle = "italic",
                                                        whiteSpace = "nowrap",
                                                        fontSize = "0.78rem"),
                           cell = function(value) {
                             if (value == "Abw. zu Vorjahr") "Abw. Vj." else value
                           })
      ),
      setNames(lapply(yr_cols, function(y) colDef(
        name = y, align = "right", minWidth = year_w,
        headerStyle = list(fontWeight = 600,
                           background = if (y == as.character(YEAR_NOW))
                             "#fde68a" else "#f9fafb"),
        style = function(value, index) {
          base <- if (y == as.character(YEAR_NOW))
            list(background = "#fef3c7") else list()
          if (d$Kennzahl[index] == "Wert")
            return(modifyList(base, list(fontWeight = 500, whiteSpace = "nowrap")))
          if (is.na(value) || !is.numeric(value)) return(base)
          col <- if (value >= 0) "#15803d" else "#b91c1c"
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
        if (d$Kennzahl[index] == "Wert") list(borderTop = "1px solid #e5e7eb") else NULL
      },
      theme = reactableTheme(
        headerStyle = list(fontWeight = 600, background = "#f9fafb"),
        cellPadding = "5px 6px"
      )
    )
  })
}

shinyApp(ui, server)
