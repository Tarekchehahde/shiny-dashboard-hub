# 23_registrierungsverhalten :: Tableau "Registrierungsverhalten" parity
# Days between Inbetriebnahme (IBN) and Registrierung — for each size bucket.
# Positive = Nachtraeglich (registered after IBN), negative = Vortraeglich.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(dplyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")

YEAR_NOW <- as.integer(format(Sys.Date(), "%Y"))

ui <- mastr_page(
  title = "Registrierungsverhalten",
  subtitle = "Tage zwischen IBN und Registrierung pro Anlagen-Gr\u00f6\u00dfenklasse.",
  fluid = TRUE,

  tableau_parity_banner("Registrierungsverhalten"),

  layout_sidebar(
    sidebar = sidebar(
      title = "Filter", width = 290,
      sliderInput("yr", "Jahr IBN",
                  min = 2019, max = YEAR_NOW,
                  value = c(2019, YEAR_NOW),
                  sep = "", step = 1, ticks = FALSE),
      selectizeInput("bl", "Bundesland", choices = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button"))),
      radioButtons("bezug", "Bezugsleistung f\u00fcr Anlagenregistrierung",
                   choices = c("AC/Netto" = "netto",
                               "DC/Brutto" = "brutto"),
                   selected = "netto"),
      helpText(class = "small text-muted",
               "Ist der Median negativ, wurde die Anlage vor Inbetriebnahme registriert. ",
               "Es werden nur IBN nach Start des MaStR 2019 ber\u00fccksichtigt.")
    ),

    layout_column_wrap(
      width = 1/2, heights_equal = "row",
      card(full_screen = TRUE,
           card_header("Median Differenz zwischen IBN & Registrierung"),
           plotlyOutput("plot_median", height = "320px")),
      card(full_screen = TRUE,
           card_header("Verteilung Differenz IBN & Registrierung (Box)"),
           plotlyOutput("plot_box", height = "320px"))
    ),

    card(full_screen = TRUE,
         card_header("Histogramm der Differenzen nach Gr\u00f6\u00dfenklasse"),
         plotlyOutput("plot_hist", height = "420px"))
  )
)

server <- function(input, output, session) {

  observe({ updateSelectInput(session, "bl", choices = mastr_bundeslaender()) })

  kw_col <- reactive(if (input$bezug == "netto") "Nettonennleistung" else "Bruttoleistung")

  where_sql <- reactive({
    p <- c("Inbetriebnahmedatum IS NOT NULL",
           "Registrierungsdatum IS NOT NULL",
           sprintf("%s BETWEEN %d AND %d",
                   sql_ibn_year("Inbetriebnahmedatum"), input$yr[1], input$yr[2]),
           sprintf("%s >= 2019", sql_ibn_year("Inbetriebnahmedatum")),
           sprintf("%s IS NOT NULL", kw_col()))
    if (length(input$bl)) {
      codes <- names(.BUNDESLAND)[.BUNDESLAND %in% input$bl]
      if (length(codes))
        p <- c(p, sprintf("CAST(Bundesland AS VARCHAR) IN (%s)",
                          mastr_sql_in(codes)))
    }
    paste(p, collapse = " AND ")
  })

  base_sample <- reactive({
    sql <- sprintf("
      SELECT DATE_DIFF('day', Inbetriebnahmedatum, %s) AS days,
             %s AS ibn_year,
             %s AS bucket
      FROM solar
      WHERE %s AND %s IS NOT NULL",
      sql_reg_date(),
      sql_ibn_year("Inbetriebnahmedatum"),
      sql_size_bucket(kw_col()),
      where_sql(),
      sql_reg_date())
    mastr_query(sql)
  })

  output$plot_median <- renderPlotly({
    d <- base_sample()
    if (!nrow(d)) return(plotly_empty())
    med <- d |> group_by(ibn_year) |>
      summarise(median = median(days, na.rm = TRUE),
                p25    = quantile(days, 0.25, na.rm = TRUE),
                p75    = quantile(days, 0.75, na.rm = TRUE),
                .groups = "drop")
    plot_ly(med, x = ~median, y = ~as.factor(ibn_year),
            type = "scatter", mode = "markers",
            marker = list(size = 10, color = MASTR_PALETTE$primary),
            error_x = list(type = "data", symmetric = FALSE,
                            array = ~(p75 - median),
                            arrayminus = ~(median - p25),
                            color = "#bbbbbb")) |>
      layout(shapes = list(list(type = "line",
                                x0 = 0, x1 = 0, y0 = -1, y1 = nrow(med),
                                line = list(color = "#555", dash = "dash"))),
             xaxis = list(title = "Tage zwischen IBN & Registrierung",
                          zeroline = TRUE),
             yaxis = list(title = "IBN-Jahr", autorange = "reversed"),
             margin = list(t = 10, r = 10, b = 50, l = 80)) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  })

  output$plot_box <- renderPlotly({
    d <- base_sample()
    if (!nrow(d)) return(plotly_empty())
    set.seed(1)
    if (nrow(d) > 80000) d <- d[sample.int(nrow(d), 80000), ]
    plot_ly(d, x = ~days, y = ~as.factor(ibn_year), type = "box",
            boxpoints = FALSE,
            marker = list(color = MASTR_PALETTE$primary),
            line   = list(color = MASTR_PALETTE$primary)) |>
      layout(xaxis = list(title = "Tage zwischen IBN & Registrierung"),
             yaxis = list(title = "IBN-Jahr", autorange = "reversed"),
             margin = list(t = 10, r = 10, b = 50, l = 80)) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  })

  output$plot_hist <- renderPlotly({
    d <- base_sample()
    if (!nrow(d)) return(plotly_empty())
    breaks <- c(-Inf, -900, -600, -300, -60, -30, -14, 0, 7, 14, 30, 60, 90, 180, 365, 730, Inf)
    labels <- c("<-900","-900","-600","-300","-60","-30","-14","0","7",
                "14","30","60","90","180","365","730+")
    d$bin <- cut(d$days, breaks = breaks, labels = labels, right = TRUE)

    d$bucket <- factor(d$bucket, levels = TABLEAU_BUCKET_LABELS)
    dd <- d |> group_by(bin, bucket) |> summarise(n = n(), .groups = "drop")

    total <- sum(dd$n)
    pal <- grDevices::colorRampPalette(
      c("#1f77b4","#aec7e8","#ff7f0e","#ffbb78","#2ca02c","#98df8a",
        "#d62728","#ff9896","#9467bd","#c5b0d5","#8c564b","#c49c94",
        "#e377c2","#f7b6d2","#7f7f7f","#c7c7c7","#bcbd22"))(length(TABLEAU_BUCKET_LABELS))
    cols <- setNames(pal, TABLEAU_BUCKET_LABELS)

    p <- plot_ly()
    for (b in TABLEAU_BUCKET_LABELS) {
      bb <- dd |> filter(bucket == b)
      if (!nrow(bb)) next
      p <- add_trace(p, data = bb,
                     x = ~bin, y = ~n, name = b, type = "bar",
                     marker = list(color = cols[[b]]))
    }
    p |> layout(
      barmode = "stack",
      xaxis = list(title = "Tage zwischen IBN & Registrierung (Bins)"),
      yaxis = list(title = "Solaranlagen"),
      annotations = list(list(
        x = 0, xref = "x", y = 1.05, yref = "paper",
        text = sprintf("Gesamtzahl: %s", formatC(total, big.mark = ".", format = "f", digits = 0)),
        showarrow = FALSE, align = "left")),
      margin = list(t = 40, r = 10, b = 50, l = 70),
      legend = list(orientation = "h", y = -0.25, x = 0.5, xanchor = "center",
                    font = list(size = 9))
    ) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  })
}

shinyApp(ui, server)
