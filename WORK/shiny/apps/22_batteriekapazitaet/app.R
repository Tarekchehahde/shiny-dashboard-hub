# 22_batteriekapazitaet :: Tableau "Histogramm Batteriekapazität" parity (partial)
#
# The original Tableau sheet shows a histogram of *Nutzbare Speicherkapazität
# kWh* per Stromspeicher. Our parquet does not yet expose that column (it
# lives in AnlagenStromSpeicher_*.xml, which the ETL does not ingest today).
#
# Until that is fixed we render the closest equivalents that *are* available:
#   - histogram of Bruttoleistung kW (Leistung, not Kapazität)
#   - stack by AcDcKoppelung and Batterietechnologie (both already in parquet)
# plus a visible warning card explaining the missing capacity column.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(dplyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")

ui <- mastr_page(
  title = "Histogramm Batteriekapazit\u00e4t \u2014 (R Shiny-Nachbau)",
  subtitle = "Verteilung der Stromspeicher. Kapazit\u00e4tsdaten folgen nach ETL-Erweiterung (siehe Hinweis unten).",
  fluid = TRUE,

  tableau_parity_banner("Histogramm Batteriekapazit\u00e4t"),

  div(class = "alert alert-warning py-2 mb-3",
      tags$strong("Kapazit\u00e4tsdaten derzeit nicht verf\u00fcgbar: "),
      "Unser aktueller Parquet-Stand enth\u00e4lt keine ",
      code("NutzbareSpeicherkapazitaet"),
      " (diese Spalte steckt im separaten Dataset ",
      code("AnlagenStromSpeicher_*.xml"),
      ", das vom ETL heute noch nicht eingelesen wird). ",
      "Bis dahin zeigen wir die Verteilung der ",
      tags$em("Bruttoleistung"),
      " kW statt kWh. Kapazit\u00e4tsansicht erscheint automatisch nach dem n\u00e4chsten Nightly, ",
      "sobald ", code("anlagen_speicher"),
      " als Entity in ", code("WORK/etl/src/mastr_etl/config.py"), " erg\u00e4nzt ist."),

  layout_sidebar(
    sidebar = sidebar(
      title = "Filter", width = 290,
      selectizeInput("tech", "Batterietechnologie",
                     choices = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button"))),
      radioButtons("ac", "Ac/Dc Koppelung",
                   choices = c("Alle" = "all",
                               "AC" = "AC gekoppeltes System",
                               "DC" = "DC gekoppeltes System"),
                   selected = "all"),
      sliderInput("binsz", "Bin-Breite (kW)",
                  min = 1, max = 50, value = 5, step = 1, ticks = FALSE),
      sliderInput("xmax", "Max. Leistung (kW) anzeigen",
                  min = 10, max = 500, value = 100, step = 10, ticks = FALSE)
    ),

    layout_column_wrap(
      width = 1/2, heights_equal = "row",
      card(full_screen = TRUE,
           card_header("Verteilung: Anteil Stromspeicher"),
           plotlyOutput("plot_pct", height = "520px")),
      card(full_screen = TRUE,
           card_header("Verteilung: Anzahl Stromspeicher (stacked)"),
           plotlyOutput("plot_cnt", height = "520px"))
    )
  )
)

server <- function(input, output, session) {

  observe({
    t <- tryCatch(mastr_query(
      "SELECT DISTINCT Batterietechnologie FROM stromspeicher
       WHERE Batterietechnologie IS NOT NULL ORDER BY 1")[[1]],
      error = function(e) character())
    updateSelectizeInput(session, "tech", choices = t, selected = NULL)
  })

  where_sql <- reactive({
    p <- c("Bruttoleistung IS NOT NULL")
    if (length(input$tech))
      p <- c(p, sprintf("CAST(Batterietechnologie AS VARCHAR) IN (%s)",
                        mastr_sql_in(input$tech)))
    if (input$ac != "all")
      p <- c(p, sprintf("AcDcKoppelung = %s", mastr_sql_in(input$ac)))
    paste(p, collapse = " AND ")
  })

  histo <- reactive({
    sql <- sprintf("
      SELECT FLOOR(Bruttoleistung / %d) * %d AS bin_lo,
             Batterietechnologie             AS tech,
             AcDcKoppelung                   AS ac,
             COUNT(*)                        AS n
      FROM stromspeicher
      WHERE %s AND Bruttoleistung <= %d
      GROUP BY 1, 2, 3",
      input$binsz, input$binsz, where_sql(), input$xmax + input$binsz)
    d <- mastr_query(sql)
    if (!nrow(d)) return(d)
    d$bin_label <- sprintf("%d\u2013%d", d$bin_lo, d$bin_lo + input$binsz)
    d
  })

  output$plot_pct <- renderPlotly({
    d <- histo()
    if (!nrow(d)) return(plotly_empty())
    d2 <- d |> group_by(bin_lo, bin_label) |> summarise(n = sum(n), .groups = "drop")
    d2$pct <- d2$n / sum(d2$n)
    d2 <- d2 |> arrange(bin_lo)
    plot_ly(d2, y = ~factor(bin_label, levels = bin_label),
            x = ~pct, type = "bar", orientation = "h",
            marker = list(color = MASTR_PALETTE$storage),
            hovertemplate = "%{y}: %{x:.2%}<extra></extra>") |>
      layout(yaxis = list(title = "Bruttoleistung kW", autorange = "reversed"),
             xaxis = list(title = "% aller Stromspeicher",
                          tickformat = ".0%"),
             margin = list(t = 10, r = 10, b = 50, l = 90)) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  })

  output$plot_cnt <- renderPlotly({
    d <- histo()
    if (!nrow(d)) return(plotly_empty())

    d$tech <- ifelse(is.na(d$tech), "Unbekannt", d$tech)
    tech_order <- d |> group_by(tech) |> summarise(n = sum(n), .groups = "drop") |>
      arrange(desc(n)) |> pull(tech)

    d$tech <- factor(d$tech, levels = tech_order)

    pal <- c("#ef4444","#f59e0b","#0ea5e9","#111827","#7c3aed",
             "#10b981","#64748b","#dc2626","#2563eb","#6b7280")
    pal <- setNames(rep(pal, length.out = length(tech_order)), tech_order)

    p <- plot_ly()
    for (t in tech_order) {
      dd <- d |> filter(tech == t) |>
        group_by(bin_lo, bin_label) |>
        summarise(n = sum(n), .groups = "drop") |>
        arrange(bin_lo)
      p <- add_trace(p, data = dd,
                     y = ~factor(bin_label, levels = bin_label),
                     x = ~n, name = as.character(t),
                     type = "bar", orientation = "h",
                     marker = list(color = pal[[as.character(t)]]))
    }
    p |> layout(
      barmode = "stack",
      yaxis = list(title = "Bruttoleistung kW", autorange = "reversed"),
      xaxis = list(title = "Anzahl Stromspeicher"),
      legend = list(orientation = "h", y = -0.18, x = 0.5, xanchor = "center"),
      margin = list(t = 10, r = 10, b = 70, l = 90)
    ) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  })
}

shinyApp(ui, server)
