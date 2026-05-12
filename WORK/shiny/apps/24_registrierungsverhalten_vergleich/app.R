# 24_registrierungsverhalten_vergleich :: Tableau "Registrierungsverhalten im Vergleich"
# Side-by-side heatmaps of IBN-time vs Registrierungs-time + Nachmeldungen matrix.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(dplyr); library(tidyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")

YEAR_NOW <- as.integer(format(Sys.Date(), "%Y"))

ui <- mastr_page(
  title = "Registrierungsverhalten im Vergleich",
  subtitle = "Registrierungszeit vs. Inbetriebnahmezeit \u2014 Heatmaps mit Bruttoleistung GW und Anlagenanzahl.",
  fluid = TRUE,

  tableau_parity_banner("Registrierungsverhalten im Vergleich"),

  layout_sidebar(
    sidebar = sidebar(
      title = "Filter", width = 290,
      sliderInput("yr", "IBN-Jahre (Zeilen)",
                  min = 2010, max = YEAR_NOW,
                  value = c(2019, YEAR_NOW),
                  sep = "", step = 1, ticks = FALSE),
      radioButtons("kpi", "KPI",
                   choices = c("Bruttoleistung GW" = "gw",
                               "Solaranlagen (Anzahl)" = "n"),
                   selected = "gw")
    ),

    layout_column_wrap(
      width = 1/2, heights_equal = "row",
      card(full_screen = TRUE,
           card_header("Registrierungszeit"),
           plotlyOutput("plot_reg", height = "540px")),
      card(full_screen = TRUE,
           card_header("Inbetriebnahmezeit"),
           plotlyOutput("plot_ibn", height = "540px"))
    ),

    card(full_screen = TRUE,
         card_header("Nachmeldungen \u2014 IBN vs. Registrierung (Jahr-Matrix)"),
         plotlyOutput("plot_nachmeldung", height = "520px"))
  )
)

server <- function(input, output, session) {

  heatmap_data <- reactive({
    reg_d <- sql_reg_date()
    d <- mastr_query(sprintf("
      SELECT EXTRACT(YEAR FROM Inbetriebnahmedatum)    AS ibn_year,
             CAST(EXTRACT(QUARTER FROM Inbetriebnahmedatum) AS INTEGER) AS ibn_q,
             EXTRACT(YEAR FROM %s)                     AS reg_year,
             CAST(EXTRACT(QUARTER FROM %s) AS INTEGER) AS reg_q,
             COUNT(*)                                  AS n,
             SUM(Bruttoleistung) / 1e6                 AS gw
      FROM solar
      WHERE Inbetriebnahmedatum IS NOT NULL
        AND %s IS NOT NULL
        AND EXTRACT(YEAR FROM Inbetriebnahmedatum) BETWEEN %d AND %d
      GROUP BY 1,2,3,4",
      reg_d, reg_d, reg_d,
      input$yr[1], input$yr[2]))
    d
  })

  make_heat <- function(d, rows_year, rows_q, val_col, title_z) {
    mat <- d |>
      group_by({{ rows_year }}, {{ rows_q }}) |>
      summarise(val = sum(.data[[val_col]], na.rm = TRUE), .groups = "drop") |>
      mutate(qlabel = paste0("Q", {{ rows_q }}))
    wide <- mat |> tidyr::pivot_wider(names_from = qlabel, values_from = val, values_fill = 0)
    year_col <- rlang::as_name(rlang::enquo(rows_year))
    year_vals <- wide[[year_col]]
    wide <- wide[, -match(year_col, names(wide)), drop = FALSE]
    wide <- wide[, order(names(wide))]

    plot_ly(x = colnames(wide),
            y = as.character(year_vals),
            z = as.matrix(wide),
            type = "heatmap",
            colorscale = list(
              c(0,    "#e0f2fe"),
              c(0.3,  "#60a5fa"),
              c(0.6,  "#2563eb"),
              c(1,    "#1e3a8a")),
            hovertemplate = paste0(title_z, ": %{z:,.2f}<br>Jahr %{y}, %{x}<extra></extra>")) |>
      layout(xaxis = list(title = ""),
             yaxis = list(title = "Jahr", autorange = "reversed"),
             margin = list(t = 10, r = 10, b = 30, l = 60)) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  }

  output$plot_reg <- renderPlotly({
    d <- heatmap_data()
    if (!nrow(d)) return(plotly_empty())
    val_col <- if (input$kpi == "gw") "gw" else "n"
    make_heat(d, reg_year, reg_q, val_col,
              if (val_col == "gw") "GW" else "Anzahl")
  })

  output$plot_ibn <- renderPlotly({
    d <- heatmap_data()
    if (!nrow(d)) return(plotly_empty())
    val_col <- if (input$kpi == "gw") "gw" else "n"
    make_heat(d, ibn_year, ibn_q, val_col,
              if (val_col == "gw") "GW" else "Anzahl")
  })

  output$plot_nachmeldung <- renderPlotly({
    d <- heatmap_data()
    if (!nrow(d)) return(plotly_empty())
    val_col <- if (input$kpi == "gw") "gw" else "n"
    mat <- d |> group_by(reg_year, ibn_year) |>
      summarise(val = sum(.data[[val_col]], na.rm = TRUE), .groups = "drop")
    wide <- mat |> tidyr::pivot_wider(names_from = ibn_year, values_from = val, values_fill = 0) |>
      arrange(desc(reg_year))
    regs <- wide$reg_year
    wide <- wide[, -1, drop = FALSE]
    wide <- wide[, order(as.integer(names(wide)), decreasing = TRUE)]

    plot_ly(x = colnames(wide),
            y = as.character(regs),
            z = as.matrix(wide),
            type = "heatmap",
            colorscale = list(
              c(0,    "#fce7f3"),
              c(0.3,  "#f472b6"),
              c(0.6,  "#be185d"),
              c(1,    "#7c2d12")),
            hovertemplate = paste0(
              if (input$kpi == "gw") "GW" else "Anzahl",
              ": %{z:,.2f}<br>Reg.jahr %{y}, IBN-Jahr %{x}<extra></extra>")) |>
      layout(xaxis = list(title = "IBN-Jahr"),
             yaxis = list(title = "Registrierungs-Jahr"),
             margin = list(t = 10, r = 10, b = 40, l = 80)) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  })
}

shinyApp(ui, server)
