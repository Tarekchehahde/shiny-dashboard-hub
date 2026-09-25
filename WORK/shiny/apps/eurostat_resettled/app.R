# =============================================================================
# eurostat_resettled — Eurostat migr_asyrescra (resettled persons).
# Does NOT load the 214-million-cell dense cube. Aggregated TOTAL slices
# written by scripts/eurostat-sync-resettled.py.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(plotly)
  library(reactable)
  library(dplyr)
  library(jsonlite)
})

source("../../R/ui_helpers.R")

DATA_DIR <- Sys.getenv(
  "MASTR_EUROSTAT_DIR",
  unset = file.path(getwd(), "data")
)

AGE_KEEP <- c("Y_LT14", "Y14-17", "Y18-34", "Y35-64", "Y_GE65", "UNK")
SEX_KEEP <- c("M", "F", "UNK")

read_meta <- function() {
  p <- file.path(DATA_DIR, "meta.json")
  if (!file.exists(p)) return(NULL)
  jsonlite::fromJSON(p)
}

read_csv_safe <- function(name) {
  p <- file.path(DATA_DIR, name)
  if (!file.exists(p)) return(NULL)
  utils::read.csv(p, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
}

fmt_int <- function(x) {
  ifelse(!is.finite(x), "\u2014",
         formatC(as.integer(round(x)), format = "d",
                 big.mark = ".", decimal.mark = ","))
}

ui <- mastr_page(
  title = "Eurostat \u2014 Resettled persons",
  subtitle = paste(
    "migr_asyrescra: persons resettled by receiving country, citizenship,",
    "previous residence, age and sex. Annual. Dashboard uses TOTAL slices",
    "from the Eurostat API \u2014 not the 214 million dense cells."
  ),
  fluid = TRUE,
  primary = "#0A3161",
  footer = "eurostat",
  layout_sidebar(
    sidebar = sidebar(
      title = "Filters", width = 280,
      uiOutput("geo_ui"),
      uiOutput("year_ui"),
      sliderInput("top_n", "Top nationalities / origins", min = 8, max = 25,
                  value = 15, step = 1, ticks = FALSE),
      tags$hr(),
      uiOutput("source_note")
    ),
    layout_column_wrap(
      width = 1/4,
      uiOutput("kpi_total"),
      uiOutput("kpi_yoy"),
      uiOutput("kpi_top_geo"),
      uiOutput("kpi_updated")
    ),
    layout_column_wrap(
      width = 1/2, heights_equal = "row",
      card(full_screen = TRUE, height = "420px",
           card_header("Resettled persons by year"),
           plotlyOutput("plot_trend", height = "360px")),
      card(full_screen = TRUE, height = "420px",
           card_header("Receiving countries (selected year)"),
           plotlyOutput("plot_geo", height = "360px"))
    ),
    layout_column_wrap(
      width = 1/2, heights_equal = "row",
      card(full_screen = TRUE, height = "460px",
           card_header("Citizenship (selected country \u00d7 year)"),
           plotlyOutput("plot_citizen", height = "400px")),
      card(full_screen = TRUE, height = "460px",
           card_header("Country of previous residence"),
           plotlyOutput("plot_origin", height = "400px"))
    ),
    layout_column_wrap(
      width = 1/2, heights_equal = "row",
      card(full_screen = TRUE, height = "400px",
           card_header("Age \u00d7 sex (selected country \u00d7 year)"),
           plotlyOutput("plot_age", height = "340px")),
      card(full_screen = TRUE, height = "400px",
           card_header("Receiving-country table"),
           reactableOutput("tbl_geo"))
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  bundle <- reactivePoll(
    30000,
    session,
    checkFunc = function() {
      p <- file.path(DATA_DIR, "meta.json")
      if (!file.exists(p)) return("")
      file.info(p)$mtime
    },
    valueFunc = function() {
      list(
        meta = read_meta(),
        geo = read_csv_safe("by_geo.csv"),
        citizen = read_csv_safe("by_citizen.csv"),
        origin = read_csv_safe("by_origin.csv"),
        agesex = read_csv_safe("by_age_sex.csv")
      )
    }
  )

  output$geo_ui <- renderUI({
    g <- bundle()$geo
    req(!is.null(g), nrow(g) > 0)
    labs <- g |>
      distinct(geo, geo_label) |>
      arrange(geo_label)
    ch <- setNames(labs$geo, labs$geo_label)
    sel <- if ("EU27_2020" %in% labs$geo) "EU27_2020" else labs$geo[[1]]
    selectInput("geo", "Receiving country / area", choices = ch, selected = sel)
  })

  output$year_ui <- renderUI({
    g <- bundle()$geo
    req(!is.null(g), nrow(g) > 0)
    yrs <- sort(unique(as.character(g$time)))
    selectInput("year", "Year", choices = yrs, selected = tail(yrs, 1))
  })

  output$source_note <- renderUI({
    m <- bundle()$meta
    req(!is.null(m))
    tagList(
      tags$small(class = "text-muted",
        "Eurostat last updated: ", strong(m$updated), tags$br(),
        tags$a(href = m$browser, target = "_blank", rel = "noopener",
               "Open official table"),
        " \u00b7 local files refresh when that timestamp changes.")
    )
  })

  geo_year <- reactive({
    g <- bundle()$geo
    req(!is.null(g), isTruthy(input$geo), isTruthy(input$year))
    g |>
      mutate(value = as.numeric(value), time = as.character(time)) |>
      filter(geo == input$geo)
  })

  output$kpi_total <- renderUI({
    d <- geo_year()
    req(nrow(d) > 0)
    v <- d$value[d$time == input$year]
    v <- if (length(v)) v[[1]] else NA_real_
    lab <- d$geo_label[1]
    bslib::value_box(
      title = paste("Resettled", input$year),
      value = fmt_int(v),
      showcase = NULL,
      p(class = "small mb-0", lab)
    )
  })

  output$kpi_yoy <- renderUI({
    d <- geo_year()
    req(nrow(d) > 0)
    yrs <- sort(unique(d$time))
    i <- match(input$year, yrs)
    cur <- d$value[d$time == input$year][1]
    prev <- if (!is.na(i) && i > 1) d$value[d$time == yrs[i - 1]][1] else NA_real_
    pct <- if (is.finite(cur) && is.finite(prev) && prev > 0) (cur / prev - 1) * 100 else NA_real_
    bslib::value_box(
      title = "vs previous year",
      value = if (is.finite(pct))
        paste0(ifelse(pct >= 0, "+", ""), sprintf("%.0f %%", pct)) else "\u2014",
      p(class = "small mb-0",
        if (is.finite(prev)) paste("was", fmt_int(prev)) else "no prior year")
    )
  })

  output$kpi_top_geo <- renderUI({
    g <- bundle()$geo
    req(!is.null(g), isTruthy(input$year))
    top <- g |>
      mutate(value = as.numeric(value)) |>
      filter(time == as.character(input$year), geo != "EU27_2020", is.finite(value)) |>
      arrange(desc(value))
    req(nrow(top) > 0)
    bslib::value_box(
      title = "Largest receiving country",
      value = top$geo[1],
      p(class = "small mb-0", top$geo_label[1], "\u00b7", fmt_int(top$value[1]))
    )
  })

  output$kpi_updated <- renderUI({
    m <- bundle()$meta
    req(!is.null(m))
    bslib::value_box(
      title = "Eurostat stamp",
      value = substr(m$updated, 1, 10),
      p(class = "small mb-0", "poll skips if unchanged")
    )
  })

  output$plot_trend <- renderPlotly({
    d <- geo_year()
    req(nrow(d) > 0)
    plot_ly(d, x = ~time, y = ~value, type = "scatter", mode = "lines+markers",
            line = list(width = 3, color = "#0A3161"),
            marker = list(size = 9, color = "#F5C518"),
            hoverinfo = "text",
            text = paste0(d$time, ": ", fmt_int(d$value), " persons")) |>
      layout(
        margin = list(t = 10, r = 10, b = 40, l = 50),
        xaxis = list(title = "", type = "category"),
        yaxis = list(title = "Persons", separatethousands = TRUE),
        hoverlabel = list(bgcolor = "#0A3161")
      ) |>
      config(displaylogo = FALSE, displayModeBar = FALSE)
  })

  output$plot_geo <- renderPlotly({
    g <- bundle()$geo
    req(!is.null(g), isTruthy(input$year))
    d <- g |>
      mutate(value = as.numeric(value)) |>
      filter(time == as.character(input$year), geo != "EU27_2020",
             is.finite(value), value > 0) |>
      arrange(value)
    req(nrow(d) > 0)
    plot_ly(d, x = ~value, y = ~reorder(geo_label, value), type = "bar",
            orientation = "h",
            marker = list(color = "#0A3161"),
            hoverinfo = "text",
            text = paste0(d$geo_label, ": ", fmt_int(d$value))) |>
      layout(
        margin = list(t = 10, r = 10, b = 40, l = 120),
        xaxis = list(title = "Persons", separatethousands = TRUE),
        yaxis = list(title = ""),
        hoverlabel = list(bgcolor = "#0A3161")
      ) |>
      config(displaylogo = FALSE, displayModeBar = FALSE)
  })

  output$plot_citizen <- renderPlotly({
    cits <- bundle()$citizen
    req(!is.null(cits), isTruthy(input$geo), isTruthy(input$year))
    d <- cits |>
      mutate(value = as.numeric(value)) |>
      filter(geo == input$geo, time == as.character(input$year),
             citizen != "TOTAL", is.finite(value), value > 0) |>
      arrange(desc(value)) |>
      slice_head(n = input$top_n) |>
      arrange(value)
    req(nrow(d) > 0)
    plot_ly(d, x = ~value, y = ~reorder(citizen_label, value), type = "bar",
            orientation = "h", marker = list(color = "#3B6FB6"),
            hoverinfo = "text",
            text = paste0(d$citizen_label, ": ", fmt_int(d$value))) |>
      layout(
        margin = list(t = 10, r = 10, b = 40, l = 140),
        xaxis = list(title = "Persons"),
        yaxis = list(title = "")
      ) |>
      config(displaylogo = FALSE, displayModeBar = FALSE)
  })

  output$plot_origin <- renderPlotly({
    ori <- bundle()$origin
    req(!is.null(ori), isTruthy(input$geo), isTruthy(input$year))
    d <- ori |>
      mutate(value = as.numeric(value)) |>
      filter(geo == input$geo, time == as.character(input$year),
             c_resid != "TOTAL", is.finite(value), value > 0) |>
      arrange(desc(value)) |>
      slice_head(n = input$top_n) |>
      arrange(value)
    req(nrow(d) > 0)
    plot_ly(d, x = ~value, y = ~reorder(c_resid_label, value), type = "bar",
            orientation = "h", marker = list(color = "#C99700"),
            hoverinfo = "text",
            text = paste0(d$c_resid_label, ": ", fmt_int(d$value))) |>
      layout(
        margin = list(t = 10, r = 10, b = 40, l = 140),
        xaxis = list(title = "Persons"),
        yaxis = list(title = "")
      ) |>
      config(displaylogo = FALSE, displayModeBar = FALSE)
  })

  output$plot_age <- renderPlotly({
    a <- bundle()$agesex
    req(!is.null(a), isTruthy(input$geo), isTruthy(input$year))
    d <- a |>
      mutate(value = as.numeric(value)) |>
      filter(geo == input$geo, time == as.character(input$year),
             age %in% AGE_KEEP, sex %in% SEX_KEEP,
             is.finite(value))
    req(nrow(d) > 0)
    plot_ly(d, x = ~age_label, y = ~value, color = ~sex_label, type = "bar",
            hoverinfo = "text",
            text = paste0(d$sex_label, " \u00b7 ", d$age_label, ": ", fmt_int(d$value))) |>
      layout(
        barmode = "stack",
        margin = list(t = 10, r = 10, b = 80, l = 50),
        xaxis = list(title = "", tickangle = -25),
        yaxis = list(title = "Persons"),
        legend = list(orientation = "h", y = 1.08)
      ) |>
      config(displaylogo = FALSE, displayModeBar = FALSE)
  })

  output$tbl_geo <- renderReactable({
    g <- bundle()$geo
    req(!is.null(g), isTruthy(input$year))
    d <- g |>
      mutate(value = as.numeric(value)) |>
      filter(time == as.character(input$year), geo != "EU27_2020") |>
      arrange(desc(value)) |>
      transmute(Country = geo_label, Code = geo, Persons = value)
    reactable(
      d, pagination = FALSE, highlight = TRUE, compact = TRUE,
      defaultPageSize = 40,
      columns = list(
        Country = colDef(minWidth = 140),
        Code = colDef(width = 70),
        Persons = colDef(align = "right", cell = function(value) fmt_int(value))
      )
    )
  })
}

shinyApp(ui, server)
