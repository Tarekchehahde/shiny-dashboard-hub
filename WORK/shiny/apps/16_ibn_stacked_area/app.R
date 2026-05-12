# 16_ibn_stacked_area :: Tableau "Inbetriebnahmen (2)" parity
# Stacked 100% area chart of monthly solar IBN, split by BNetzA size bucket.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(dplyr); library(tidyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")

YEAR_NOW <- as.integer(format(Sys.Date(), "%Y"))

ui <- mastr_page(
  title = "Inbetriebnahmen (2) \u2014 gestapelte Fl\u00e4che",
  subtitle = "Anteil der Anlagen-Gr\u00f6\u00dfenklassen am Monatszubau (Tableau-Parit\u00e4t).",
  fluid = TRUE,

  tableau_parity_banner("Inbetriebnahmen (2)"),

  layout_sidebar(
    sidebar = sidebar(
      title = "Filter", width = 290,
      sliderInput("yr", "IBN-Jahre",
                  min = 2010, max = YEAR_NOW,
                  value = c(max(2021, YEAR_NOW - 4), YEAR_NOW),
                  sep = "", step = 1, ticks = FALSE),
      radioButtons("metric", "Switch KPI",
                   choices = c("Bruttoleistung MW" = "brutto",
                               "Anlagen (Stk.)"     = "count"),
                   selected = "brutto"),
      selectizeInput("nu", "Nutzungsbereich",
                     choices = NULL, selected = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button"))),
      selectizeInput("es", "Einspeisungsart",
                     choices = NULL, selected = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button"))),
      selectizeInput("lb", "Leistungsbegrenzung",
                     choices = NULL, selected = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button"))),
      radioButtons("norm", "Darstellung",
                   choices = c("100% gestapelt" = "percent",
                               "absolut (gestapelt)" = "absolute"),
                   selected = "percent")
    ),

    card(full_screen = TRUE,
         card_header("Monatlicher Zubau nach Anlagenkategorie"),
         plotlyOutput("plot_area", height = "640px"))
  )
)

server <- function(input, output, session) {

  filter_cats <- reactive({
    con <- mastr_con()
    list(
      nu = tryCatch(mastr_query("SELECT DISTINCT Nutzungsbereich   FROM solar WHERE Nutzungsbereich   IS NOT NULL ORDER BY 1")[[1]], error = function(e) character()),
      es = tryCatch(mastr_query("SELECT DISTINCT Einspeisungsart   FROM solar WHERE Einspeisungsart   IS NOT NULL ORDER BY 1")[[1]], error = function(e) character()),
      lb = tryCatch(mastr_query("SELECT DISTINCT Leistungsbegrenzung FROM solar WHERE Leistungsbegrenzung IS NOT NULL ORDER BY 1")[[1]], error = function(e) character())
    )
  })
  observe({
    fc <- filter_cats()
    updateSelectizeInput(session, "nu", choices = fc$nu, selected = NULL)
    updateSelectizeInput(session, "es", choices = fc$es, selected = NULL)
    updateSelectizeInput(session, "lb", choices = fc$lb, selected = NULL)
  })

  area_data <- reactive({
    where <- c(
      "Inbetriebnahmedatum IS NOT NULL",
      "Bruttoleistung IS NOT NULL",
      sprintf("%s BETWEEN %d AND %d",
              sql_ibn_year("Inbetriebnahmedatum"), input$yr[1], input$yr[2])
    )
    if (length(input$nu))
      where <- c(where, sprintf("CAST(Nutzungsbereich AS VARCHAR) IN (%s)",
                                mastr_sql_in(input$nu)))
    if (length(input$es))
      where <- c(where, sprintf("CAST(Einspeisungsart AS VARCHAR) IN (%s)",
                                mastr_sql_in(input$es)))
    if (length(input$lb))
      where <- c(where, sprintf("CAST(Leistungsbegrenzung AS VARCHAR) IN (%s)",
                                mastr_sql_in(input$lb)))

    value_expr <- if (input$metric == "brutto")
      "SUM(Bruttoleistung) / 1000.0" else "COUNT(*) * 1.0"

    sql <- sprintf("
      SELECT DATE_TRUNC('month', Inbetriebnahmedatum) AS month,
             %s AS bucket,
             %s AS value
      FROM solar
      WHERE %s
      GROUP BY 1, 2
      ORDER BY 1, 2",
      sql_size_bucket("Bruttoleistung"),
      value_expr,
      paste(where, collapse = " AND "))
    mastr_query(sql)
  })

  output$plot_area <- renderPlotly({
    d <- area_data()
    if (!nrow(d)) return(plotly_empty())

    d$bucket <- factor(d$bucket, levels = TABLEAU_BUCKET_LABELS)

    w <- d |>
      pivot_wider(names_from = bucket, values_from = value, values_fill = 0) |>
      arrange(month)

    stackgrp <- "one"
    groupnorm <- if (input$norm == "percent") "percent" else ""
    ytitle    <- if (input$norm == "percent") "%"
                 else if (input$metric == "brutto") "MW" else "Anzahl"

    pal <- grDevices::colorRampPalette(
      c("#1f77b4","#aec7e8","#ff7f0e","#ffbb78","#2ca02c","#98df8a",
        "#d62728","#ff9896","#9467bd","#c5b0d5","#8c564b","#c49c94",
        "#e377c2","#f7b6d2","#7f7f7f","#c7c7c7","#bcbd22"))(length(TABLEAU_BUCKET_LABELS))
    cols <- setNames(pal, TABLEAU_BUCKET_LABELS)

    p <- plot_ly()
    for (b in TABLEAU_BUCKET_LABELS) {
      if (!(b %in% names(w))) next
      p <- add_trace(p, x = w$month, y = w[[b]], name = b,
                     type = "scatter", mode = "none", stackgroup = stackgrp,
                     groupnorm = groupnorm,
                     fillcolor = cols[[b]], line = list(width = 0),
                     hovertemplate = paste0(b, "<br>%{x|%b %Y}: %{y:,.1f}<extra></extra>"))
    }
    p |> layout(
      margin = list(t = 20, r = 10, b = 50, l = 60),
      xaxis = list(title = "Monat von IBN"),
      yaxis = list(title = ytitle, automargin = TRUE,
                   ticksuffix = if (input$norm == "percent") "%" else ""),
      legend = list(orientation = "h", y = -0.18, x = 0.5,
                    xanchor = "center", font = list(size = 10))
    ) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  })
}

shinyApp(ui, server)
