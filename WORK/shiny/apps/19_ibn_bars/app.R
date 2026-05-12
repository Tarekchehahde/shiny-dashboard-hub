# 19_ibn_bars :: Tableau "Inbetriebnahmen MaStR" parity
# 4 stacked-bar panels by Quartal: diff and absolute for Anlagen + Bruttoleistung.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(dplyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")

YEAR_NOW <- as.integer(format(Sys.Date(), "%Y"))

ui <- mastr_page(
  title = "Inbetriebnahmen MaStR \u2014 Quartalsbalken",
  subtitle = "IBN der Solaranlagen und Bruttoleistung MW je Quartal \u2014 absolut und als Differenz zum Vorquartal.",
  fluid = TRUE,

  tableau_parity_banner("Inbetriebnahmen MaStR"),

  layout_sidebar(
    sidebar = sidebar(
      title = "Filter", width = 290,
      sliderInput("yr", "IBN-Jahre",
                  min = 2008, max = YEAR_NOW,
                  value = c(2012, YEAR_NOW),
                  sep = "", step = 1, ticks = FALSE),
      selectizeInput("bl", "Bundesland", choices = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button"))),
      checkboxInput("only_active", "Nur aktive Einheiten", value = FALSE)
    ),

    card(full_screen = TRUE, height = "780px",
         card_header("Quartalsweise: Solaranlagen / Bruttoleistung MW (+ Differenzen)"),
         plotlyOutput("plot_bars", height = "720px"))
  )
)

server <- function(input, output, session) {

  observe({ updateSelectInput(session, "bl", choices = mastr_bundeslaender()) })

  where_sql <- reactive({
    p <- c("Inbetriebnahmedatum IS NOT NULL",
           sprintf("%s BETWEEN %d AND %d",
                   sql_ibn_year("Inbetriebnahmedatum"), input$yr[1], input$yr[2]))
    if (input$only_active) p <- c(p, "EinheitBetriebsstatus = 'InBetrieb'")
    if (length(input$bl)) {
      codes <- names(.BUNDESLAND)[.BUNDESLAND %in% input$bl]
      if (length(codes))
        p <- c(p, sprintf("CAST(Bundesland AS VARCHAR) IN (%s)",
                          mastr_sql_in(codes)))
    }
    paste(p, collapse = " AND ")
  })

  quarterly <- reactive({
    d <- mastr_query(sprintf("
      SELECT DATE_TRUNC('quarter', Inbetriebnahmedatum) AS q,
             COUNT(*) AS solaranlagen,
             SUM(Bruttoleistung)/1000.0 AS mw
      FROM solar WHERE %s
      GROUP BY 1 ORDER BY 1", where_sql()))
    if (!nrow(d)) return(d)
    d$q <- as.Date(d$q)
    d$qlabel <- sprintf("%s Q%s", format(d$q, "%Y"),
                        ((as.integer(format(d$q, "%m")) - 1) %/% 3) + 1)
    d$d_solaranlagen <- c(NA, diff(d$solaranlagen))
    d$d_mw           <- c(NA, diff(d$mw))
    d
  })

  output$plot_bars <- renderPlotly({
    d <- quarterly()
    if (!nrow(d)) return(plotly_empty())

    col_sol <- MASTR_PALETTE$primary
    col_mw  <- MASTR_PALETTE$solar

    mk <- function(y, col, ytitle) {
      plot_ly(d, x = ~qlabel, y = y, type = "bar",
              marker = list(color = col),
              hovertemplate = paste0("%{x}<br>", ytitle, ": %{y:,.1f}<extra></extra>")) |>
        layout(yaxis = list(title = list(text = ytitle, standoff = 8),
                            automargin = TRUE),
               xaxis = list(title = "", tickangle = -30))
    }

    p1 <- mk(d$d_solaranlagen, col_sol, "\u0394 Solaranlagen")
    p2 <- mk(d$solaranlagen,   col_sol, "Solaranlagen")
    p3 <- mk(d$d_mw,           col_mw,  "\u0394 Brutto MW")
    p4 <- mk(d$mw,             col_mw,  "Brutto MW")

    subplot(p1, p2, p3, p4, nrows = 4, shareX = TRUE, titleY = FALSE, margin = 0.015) |>
      layout(showlegend = FALSE,
             margin = list(t = 10, r = 10, b = 70, l = 60)) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  })
}

shinyApp(ui, server)
