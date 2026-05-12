# Thesis track — Speicher-Technologie-Mix (alle Stromspeicher-Einheiten nach Technologie)

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable)
})
source("../../../R/mastr_data.R"); source("../../../R/ui_helpers.R")

THESIS_PRIMARY <- "#0f766e"

sql_all <- "
  SELECT EinheitMastrNummer AS mastr_nr,
         TRY_CAST(Bruttoleistung AS DOUBLE) AS kw,
         TRY_CAST(NutzbareSpeicherkapazitaet AS DOUBLE) AS kwh,
         TRY_CAST(Inbetriebnahmedatum AS DATE) AS inbetrieb,
         Technologie, Bundesland
  FROM stromspeicher
  WHERE Technologie IS NOT NULL
"

ui <- mastr_page(
  title = "Speicher-Technologien (Mix)",
  subtitle = "Alle MaStR-Stromspeicher nach Technologie — Batteriespeicher vs. Pumpspeicher u. a.",
  primary = THESIS_PRIMARY,

  p(class = "small text-muted mb-2",
    strong("Hinweis: "), "Im Rohdatensatz steht „Technologie“ als ",
    strong("Zahlencode"),
    " (BNetzA-Enumeration), nicht als Wort „Batterie“. ",
    "Die Grafiken nutzen unten erläuternde Kurzbezeichnungen; ",
    "offizielle Langtexte: ",
    tags$a(href = "https://www.marktstammdatenregister.de/MaStRHilfe/subpages/dokumentendownload.html",
           target = "_blank", "MaStR Datendefinition Einheiten (Excel), Feld Technologie Stromspeicher"),
    "."),

  layout_column_wrap(width = 1 / 2,
    card(card_header("Anteil Leistung [MW] nach Technologie"),
         plotlyOutput("plot_pie", height = "420px")),
    card(card_header("Zubau kumuliert (MW) — Top-5-Technologien"),
         plotlyOutput("plot_lines", height = "420px"))
  ),

  card(card_header("Stückzahlen und MW je Technologie"),
       reactableOutput("table_tech"))
)

server <- function(input, output, session) {
  df <- reactive(mastr_query(sql_all))

  tech_summary <- reactive({
    d <- df()
    if (nrow(d) == 0) {
      return(data.frame(
        Technologie = character(), Bezeichnung = character(),
        n = integer(), mw = numeric()
      ))
    }
    n_cnt <- as.data.frame(table(d$Technologie), stringsAsFactors = FALSE)
    names(n_cnt) <- c("Technologie", "n")
    mw_sum <- stats::aggregate(kw ~ Technologie, data = d, FUN = function(x) sum(x, na.rm = TRUE) / 1000)
    names(mw_sum)[2] <- "mw"
    out <- merge(n_cnt, mw_sum, by = "Technologie", all.x = TRUE)
    out$Bezeichnung <- mastr_label_stromspeicher_technologie(out$Technologie)
    out[order(-out$mw), ]
  })

  output$plot_pie <- renderPlotly({
    s <- tech_summary()
    if (nrow(s) == 0) return(mastr_plotly_empty("Keine Daten"))
    plot_ly(s, labels = ~Bezeichnung, values = ~mw, type = "pie", hole = 0.35,
            textinfo = "percent+label") |>
      layout(showlegend = TRUE)
  })

  output$plot_lines <- renderPlotly({
    d <- df()
    if (nrow(d) == 0) return(mastr_plotly_empty("Keine Daten"))
    d$year <- format(d$inbetrieb, "%Y")
    d <- d[!is.na(d$year) & d$year != "NA", , drop = FALSE]
    top5 <- head(tech_summary()$Technologie, 5)
    d <- d[d$Technologie %in% top5, , drop = FALSE]
    if (nrow(d) == 0) return(mastr_plotly_empty("Keine Daten"))

    cols <- c("#0f766e", "#0ea5e9", "#f59e0b", "#a855f7", "#64748b")
    traces <- list()
    ymax <- 0
    yi <- 1
    for (tt in top5) {
      sub <- d[d$Technologie == tt, , drop = FALSE]
      if (nrow(sub) == 0) next
      agg <- stats::aggregate(kw ~ year, data = sub, FUN = sum)
      agg <- agg[order(agg$year), , drop = FALSE]
      agg$mw <- agg$kw / 1000
      agg$cum_mw <- cumsum(agg$mw)
      ymax <- max(ymax, max(agg$cum_mw, na.rm = TRUE))
      traces[[length(traces) + 1L]] <- list(
        agg = agg,
        name = mastr_label_stromspeicher_technologie(tt),
        col = cols[[min(yi, length(cols))]]
      )
      yi <- yi + 1
    }
    if (length(traces) == 0L) return(mastr_plotly_empty("Keine Daten"))

    p <- plotly::plot_ly(traces[[1]]$agg, x = ~year, y = ~cum_mw, name = traces[[1]]$name,
                         type = "scatter", mode = "lines",
                         line = list(color = traces[[1]]$col))
    if (length(traces) > 1L) {
      for (j in 2:length(traces)) {
        t <- traces[[j]]
        p <- plotly::add_trace(p, x = t$agg$year, y = t$agg$cum_mw, name = t$name,
                               type = "scatter", mode = "lines",
                               line = list(color = t$col))
      }
    }
    y_pad <- max(ymax * 0.02, 1)
    p |> plotly::layout(
      xaxis = list(title = "Jahr"),
      yaxis = list(
        title = "Kumuliert MW",
        range = c(0, ymax + y_pad)
      ),
      hovermode = "x unified"
    )
  })

  output$table_tech <- renderReactable({
    s <- tech_summary()
    if (nrow(s) == 0) {
      return(reactable(data.frame(Hinweis = "Keine Daten")))
    }
    s$mw <- round(s$mw, 2)
    s <- s[, c("Technologie", "Bezeichnung", "n", "mw")]
    names(s)[names(s) == "Technologie"] <- "MaStR-Code"
    reactable(s, compact = TRUE, striped = TRUE, searchable = TRUE)
  })
}

shinyApp(ui, server)
