# 11_market_actors :: Marktakteure (Betreiber, Händler, Verbraucher)

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable)
})
source("../../R/mastr_data.R"); source("../../R/ui_helpers.R")

ui <- mastr_page(
  title = "Marktakteure",
  subtitle = "Registrierte Unternehmen und Organisationen im MaStR.",
  fluid = TRUE,

  layout_column_wrap(1/3,
    uiOutput("kpi_actors"), uiOutput("kpi_types"), uiOutput("kpi_newest")),

  layout_column_wrap(1/2, heights_equal = "row",
    card(card_header("Akteurstyp"),
         plotlyOutput("plot_type", height = "420px")),
    card(card_header("Neu-Registrierungen pro Jahr"),
         plotlyOutput("plot_reg", height = "420px"))
  ),

  card(card_header("Verzeichnis"), reactableOutput("table"))
)

server <- function(input, output, session) {
  df <- reactive(mastr_query("
    SELECT MastrNummer, Firmenname, Rechtsform, MarktakteurHauptTyp,
           TRY_CAST(DatumRegistrierung AS DATE) AS registriert,
           Land, Bundesland
    FROM marktakteure"))

  output$kpi_actors <- renderUI(mastr_kpi("Akteure", fmt_num(nrow(df()))))
  output$kpi_types <- renderUI({
    mastr_kpi("Typen", length(unique(na.omit(df()$MarktakteurHauptTyp))))
  })
  output$kpi_newest <- renderUI({
    n <- sum(df()$registriert >= Sys.Date() - 30, na.rm = TRUE)
    mastr_kpi("Neu (30 Tage)", fmt_num(n))
  })

  output$plot_type <- renderPlotly({
    d <- aggregate(MastrNummer ~ MarktakteurHauptTyp, data = df(), length)
    names(d) <- c("type", "n")
    d <- d[order(-d$n), ]
    plot_ly(d, x = ~n, y = ~reorder(type, n), type = "bar", orientation = "h",
            marker = list(color = MASTR_PALETTE$primary)) |>
      layout(yaxis = list(title = ""), xaxis = list(title = "Akteure"))
  })

  output$plot_reg <- renderPlotly({
    d <- aggregate(MastrNummer ~ format(registriert, "%Y"), data = df(), length)
    names(d) <- c("year", "n")
    plot_ly(d, x = ~year, y = ~n, type = "bar",
            marker = list(color = MASTR_PALETTE$primary))
  })

  output$table <- renderReactable({
    reactable(df()[1:500, ], compact = TRUE, striped = TRUE,
              searchable = TRUE, defaultPageSize = 15)
  })
}
shinyApp(ui, server)
