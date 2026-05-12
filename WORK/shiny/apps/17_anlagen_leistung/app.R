# 17_anlagen_leistung :: Tableau "Überblick - Anlagen & Leistung" parity
# Summary-row table by size bucket + choropleth maps + historical quarterly time series.

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(reactable); library(leaflet)
  library(dplyr); library(tidyr)
})
source("../../R/mastr_data.R")
source("../../R/ui_helpers.R")
source("../../R/tableau_helpers.R")

YEAR_NOW <- as.integer(format(Sys.Date(), "%Y"))

ui <- mastr_page(
  title = "\u00DCberblick \u2014 Anlagen & Leistung",
  subtitle = "Gr\u00f6\u00dfenklassen, Verteilung Deutschland und Zubauzeitreihe (Tableau-Parit\u00e4t).",
  fluid = TRUE,

  tableau_parity_banner("\u00DCberblick \u2014 Anlagen & Leistung"),

  layout_sidebar(
    sidebar = sidebar(
      title = "Filter", width = 290,
      radioButtons("acnetto", "Bezugsleistung f\u00fcr Anlagenkategorie",
                   choices = c("AC/Netto" = "netto",
                               "DC/Brutto" = "brutto"),
                   selected = "netto"),
      selectizeInput("bl", "Bundesland",
                     choices = NULL, selected = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button"))),
      selectizeInput("es", "Einspeisungsart",
                     choices = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button"))),
      selectizeInput("lb", "Leistungsbegrenzung",
                     choices = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button"))),
      selectizeInput("nu", "Nutzungsbereich",
                     choices = NULL, multiple = TRUE,
                     options = list(placeholder = "Alle",
                                    plugins = list("remove_button")))
    ),

    card(full_screen = TRUE,
         card_header("Aggregierte Solaranlagen je Gr\u00f6\u00dfenklasse"),
         reactableOutput("tbl_buckets", height = "auto")),

    layout_column_wrap(
      width = 1/3, heights_equal = "row",
      card(full_screen = TRUE,
           card_header("Anlagen (Anzahl)"),
           leafletOutput("map_units", height = "420px")),
      card(full_screen = TRUE,
           card_header("Bruttoleistung MW"),
           leafletOutput("map_mw", height = "420px")),
      card(full_screen = TRUE,
           card_header("\u00D8 Bruttoleistung kW"),
           leafletOutput("map_avg", height = "420px"))
    ),

    card(full_screen = TRUE,
         card_header("Kennzahlnamen: Solaranlagen & Bruttoleistung MW (quartalsweise)"),
         plotlyOutput("plot_ts", height = "360px"))
  )
)

server <- function(input, output, session) {

  observe({ updateSelectInput(session, "bl", choices = mastr_bundeslaender()) })
  filter_cats <- reactive({
    list(
      es = tryCatch(mastr_query("SELECT DISTINCT Einspeisungsart   FROM solar WHERE Einspeisungsart   IS NOT NULL ORDER BY 1")[[1]], error = function(e) character()),
      lb = tryCatch(mastr_query("SELECT DISTINCT Leistungsbegrenzung FROM solar WHERE Leistungsbegrenzung IS NOT NULL ORDER BY 1")[[1]], error = function(e) character()),
      nu = tryCatch(mastr_query("SELECT DISTINCT Nutzungsbereich   FROM solar WHERE Nutzungsbereich   IS NOT NULL ORDER BY 1")[[1]], error = function(e) character())
    )
  })
  observe({
    fc <- filter_cats()
    updateSelectizeInput(session, "es", choices = fc$es, selected = NULL)
    updateSelectizeInput(session, "lb", choices = fc$lb, selected = NULL)
    updateSelectizeInput(session, "nu", choices = fc$nu, selected = NULL)
  })

  kw_col <- reactive({
    if (input$acnetto == "netto") "Nettonennleistung" else "Bruttoleistung"
  })

  where_sql <- reactive({
    parts <- c("Inbetriebnahmedatum IS NOT NULL",
               sprintf("%s IS NOT NULL", kw_col()))
    bl_codes <- if (length(input$bl)) {
      codes <- names(.BUNDESLAND)[.BUNDESLAND %in% input$bl]
      if (length(codes)) codes else NA_character_
    } else character()
    if (length(bl_codes)) {
      parts <- c(parts, sprintf("CAST(Bundesland AS VARCHAR) IN (%s)",
                                mastr_sql_in(bl_codes)))
    }
    if (length(input$es))
      parts <- c(parts, sprintf("CAST(Einspeisungsart AS VARCHAR) IN (%s)",
                                mastr_sql_in(input$es)))
    if (length(input$lb))
      parts <- c(parts, sprintf("CAST(Leistungsbegrenzung AS VARCHAR) IN (%s)",
                                mastr_sql_in(input$lb)))
    if (length(input$nu))
      parts <- c(parts, sprintf("CAST(Nutzungsbereich AS VARCHAR) IN (%s)",
                                mastr_sql_in(input$nu)))
    paste(parts, collapse = " AND ")
  })

  bucket_data <- reactive({
    sql <- sprintf("
      SELECT %s AS bucket,
             COUNT(*) AS units,
             SUM(%s) / 1000.0 AS mw
      FROM solar WHERE %s GROUP BY 1",
      sql_size_bucket(kw_col()), kw_col(), where_sql())
    mastr_query(sql)
  })

  output$tbl_buckets <- renderReactable({
    d <- bucket_data()
    if (!nrow(d)) return(reactable(data.frame()))
    d$bucket <- factor(d$bucket, levels = TABLEAU_BUCKET_LABELS)
    d <- d[order(d$bucket), ]
    tot_units <- sum(d$units); tot_mw <- sum(d$mw)

    wide <- data.frame(
      Kennzahl = c("Solaranlagen", "% Solaranlagen",
                   "Bruttoleistung MW", "% Bruttoleistung"),
      Gesamt   = c(tot_units, 1, tot_mw, 1))
    for (i in seq_len(nrow(d))) {
      b <- as.character(d$bucket[i])
      wide[[b]] <- c(d$units[i], d$units[i] / tot_units,
                     d$mw[i],    d$mw[i]    / tot_mw)
    }
    reactable(
      wide, compact = TRUE, striped = TRUE, highlight = TRUE, bordered = FALSE,
      defaultPageSize = 4, minRows = 4,
      columns = c(
        list(Kennzahl = colDef(name = "Kennzahl", minWidth = 160, sticky = "left"),
             Gesamt   = colDef(name = "Gesamt", align = "right",
                               cell = function(v, idx) {
                                 if (wide$Kennzahl[idx] %in% c("% Solaranlagen","% Bruttoleistung"))
                                   "100,00%"
                                 else
                                   formatC(v, big.mark = ".", decimal.mark = ",",
                                           format = "f", digits = 0)
                               })),
        setNames(lapply(TABLEAU_BUCKET_LABELS[TABLEAU_BUCKET_LABELS %in% names(wide)], function(b) {
          colDef(name = b, align = "right", minWidth = 100,
                 cell = function(v, idx) {
                   if (wide$Kennzahl[idx] %in% c("% Solaranlagen","% Bruttoleistung"))
                     paste0(formatC(v * 100, format = "f", digits = 2,
                                    big.mark = ".", decimal.mark = ","), "%")
                   else if (wide$Kennzahl[idx] == "Bruttoleistung MW")
                     formatC(v, format = "f", digits = 1,
                             big.mark = ".", decimal.mark = ",")
                   else
                     formatC(v, format = "f", digits = 0,
                             big.mark = ".", decimal.mark = ",")
                 })
        }), TABLEAU_BUCKET_LABELS[TABLEAU_BUCKET_LABELS %in% names(wide)])
      )
    )
  })

  plz_data <- reactive({
    sql <- sprintf("
      SELECT Postleitzahl AS plz,
             COUNT(*)     AS units,
             SUM(%s)/1000 AS mw,
             AVG(%s)      AS avg_kw,
             AVG(Breitengrad) AS lat,
             AVG(Laengengrad) AS lng
      FROM solar
      WHERE %s AND Breitengrad IS NOT NULL AND Laengengrad IS NOT NULL
        AND Postleitzahl IS NOT NULL
      GROUP BY 1",
      kw_col(), kw_col(), where_sql())
    mastr_query(sql)
  })

  make_map <- function(value_col, palette_name) {
    d <- plz_data()
    if (!nrow(d)) return(leaflet() |> addTiles() |>
                         setView(lng = 10.45, lat = 51.16, zoom = 5))
    d$val <- d[[value_col]]
    d <- d[is.finite(d$val) & d$val > 0, ]
    pal <- colorNumeric(palette_name, d$val, na.color = "transparent")
    leaflet(d) |>
      addProviderTiles("CartoDB.Positron") |>
      addCircleMarkers(lng = ~lng, lat = ~lat,
                       radius = ~pmin(10, 2 + log10(val + 1) * 1.5),
                       color = ~pal(val), stroke = FALSE, fillOpacity = 0.55,
                       popup = ~sprintf("PLZ %s<br>%.0f",
                                         plz, val)) |>
      setView(lng = 10.45, lat = 51.16, zoom = 5)
  }

  output$map_units <- renderLeaflet({ make_map("units",  "YlOrRd") })
  output$map_mw    <- renderLeaflet({ make_map("mw",     "viridis") })
  output$map_avg   <- renderLeaflet({ make_map("avg_kw", "Blues") })

  output$plot_ts <- renderPlotly({
    sql <- sprintf("
      SELECT DATE_TRUNC('quarter', Inbetriebnahmedatum) AS q,
             COUNT(*)          AS units,
             SUM(%s)/1000.0    AS mw
      FROM solar
      WHERE %s AND Inbetriebnahmedatum IS NOT NULL
      GROUP BY 1 ORDER BY 1",
      kw_col(), where_sql())
    d <- mastr_query(sql)
    plot_ly() |>
      add_bars(data = d, x = ~q, y = ~units, name = "Solaranlagen",
               marker = list(color = MASTR_PALETTE$primary),
               opacity = 0.7) |>
      add_lines(data = d, x = ~q, y = ~mw, yaxis = "y2", name = "Bruttoleistung MW",
                line = list(color = MASTR_PALETTE$solar, width = 3)) |>
      layout(yaxis  = list(title = list(text = "Solaranlagen", standoff = 10), automargin = TRUE),
             yaxis2 = list(title = list(text = "MW", standoff = 10),
                           overlaying = "y", side = "right", automargin = TRUE,
                           showgrid = FALSE),
             xaxis = list(title = "Quartal von IBN"),
             legend = list(orientation = "h", y = -0.18, x = 0.5, xanchor = "center"),
             margin = list(t = 20, r = 60, b = 50, l = 60)) |>
      config(displaylogo = FALSE,
             modeBarButtonsToRemove = c("lasso2d","select2d","autoScale2d"))
  })
}

shinyApp(ui, server)
