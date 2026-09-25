# =============================================================================
# eurostat_de_gas — Germany natural-gas diversification (Eurostat slices).
# Cubes: nrg_ti_gas, nrg_ti_gasm, nrg_ind_id, nrg_stk_gasm, nrg_cb_gasm,
#        nrg_pc_202, nrg_pc_203. ETL: scripts/eurostat-sync-de-gas.py
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

`%||%` <- function(x, y) if (is.null(x) || (is.character(x) && !nzchar(x))) y else x

DATA_DIR <- Sys.getenv(
  "MASTR_EUROSTAT_DIR",
  unset = file.path(getwd(), "data")
)

PARTNER_SKIP <- c("TOTAL", "WORLD", "EU27_2020", "EA20", "EA19")
KEEP_ALWAYS <- c("RU", "NO", "NL", "BE", "US", "FR", "QA", "GB", "AZ", "NSP")
PARTNER_COLS <- c(
  RU = "#C41E3A", NO = "#00205B", NL = "#FF6600", BE = "#5B8DEF",
  US = "#2E7D32", FR = "#1565C0", QA = "#8E24AA", GB = "#6D4C41",
  AZ = "#00897B", NSP = "#9E9E9E", Rest = "#90A4AE"
)

read_meta <- function() {
  p <- file.path(DATA_DIR, "meta.json")
  if (!file.exists(p)) return(NULL)
  jsonlite::fromJSON(p)
}

read_csv_safe <- function(name) {
  p <- file.path(DATA_DIR, name)
  if (!file.exists(p)) return(NULL)
  d <- utils::read.csv(p, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  if ("value" %in% names(d)) d$value <- as.numeric(d$value)
  d
}

fmt_int <- function(x) {
  ifelse(!is.finite(x), "\u2014",
         formatC(as.integer(round(x)), format = "d",
                 big.mark = ",", decimal.mark = "."))
}

fmt_num <- function(x, digits = 1) {
  ifelse(!is.finite(x), "\u2014",
         formatC(x, format = "f", digits = digits,
                 big.mark = ",", decimal.mark = "."))
}

fmt_pct <- function(x) {
  ifelse(!is.finite(x), "\u2014", sprintf("%.1f %%", x))
}

stamp_max <- function(m) {
  if (is.null(m) || is.null(m$updated)) return("\u2014")
  u <- unlist(m$updated, use.names = FALSE)
  u <- u[nzchar(u)]
  if (!length(u)) return("\u2014")
  substr(max(u), 1, 10)
}

group_partners <- function(d, n_keep = 8) {
  d <- d |>
    filter(!partner %in% PARTNER_SKIP, is.finite(value), value > 0)
  if (!nrow(d)) return(d)
  latest <- max(as.character(d$time))
  top <- d |>
    filter(time == latest) |>
    arrange(desc(value)) |>
    slice_head(n = n_keep) |>
    pull(partner)
  keep <- unique(c(KEEP_ALWAYS[KEEP_ALWAYS %in% d$partner], top))
  d |>
    mutate(
      partner_group = ifelse(partner %in% keep, partner, "Rest"),
      partner_label_g = ifelse(partner %in% keep, partner_label, "Other partners")
    ) |>
    group_by(time, partner_group, partner_label_g) |>
    summarise(value = sum(value, na.rm = TRUE), .groups = "drop")
}

attach_share <- function(grouped, totals) {
  grouped |>
    left_join(totals, by = "time") |>
    mutate(share = ifelse(is.finite(total) & total > 0, 100 * value / total, NA_real_))
}

ly <- function(p) {
  p |>
    layout(
      margin = list(t = 28, r = 12, b = 48, l = 58),
      hoverlabel = list(bgcolor = "#0A3161"),
      legend = list(orientation = "h", y = 1.12, font = list(size = 11))
    ) |>
    config(displaylogo = FALSE, displayModeBar = FALSE)
}

ui <- mastr_page(
  title = "Germany \u2014 Natural gas diversification",
  subtitle = paste(
    "Eurostat cubes for Germany: partner mix (annual origin + monthly transit),",
    "import dependency, storage, supply, and household / industrial prices.",
    "Annual and monthly import tables use different partner definitions."
  ),
  fluid = TRUE,
  primary = "#0A3161",
  footer = "eurostat_gas",
  navset_card_tab(
    id = "gas_tabs",
    nav_panel(
      "Overview",
      layout_column_wrap(
        width = 1/4,
        uiOutput("kpi_total"),
        uiOutput("kpi_ru"),
        uiOutput("kpi_lng"),
        uiOutput("kpi_updated")
      ),
      layout_column_wrap(
        width = 1/2, heights_equal = "row",
        card(full_screen = TRUE, height = "420px",
             card_header("Annual import mix by origin (G3000, % of TOTAL)"),
             plotlyOutput("plot_overview_mix", height = "360px")),
        card(full_screen = TRUE, height = "420px",
             card_header("Natural-gas import dependency (%)"),
             plotlyOutput("plot_overview_dep", height = "360px"))
      ),
      uiOutput("overview_note")
    ),
    nav_panel(
      "Annual origin",
      layout_column_wrap(
        width = 1, heights_equal = "row",
        card(full_screen = TRUE, height = "440px",
             card_header("nrg_ti_gas \u2014 Germany, terajoule GCV, natural gas (G3000)"),
             plotlyOutput("plot_annual_stack", height = "380px"))
      ),
      layout_column_wrap(
        width = 1/2, heights_equal = "row",
        card(full_screen = TRUE, height = "420px",
             card_header("LNG (G3200) vs natural gas TOTAL"),
             plotlyOutput("plot_lng", height = "360px")),
        card(full_screen = TRUE, height = "420px",
             card_header("Partners in latest annual year"),
             reactableOutput("tbl_annual"))
      )
    ),
    nav_panel(
      "Monthly transit",
      card(
        full_screen = TRUE, height = "460px",
        card_header("nrg_ti_gasm \u2014 last transit country, not ultimate origin"),
        plotlyOutput("plot_monthly_stack", height = "400px")
      ),
      p(class = "small text-muted",
        "Monthly reporting since 2013 records the last country the gas entered from.",
        "Belgium / Netherlands shares here are often LNG or Norwegian gas in transit.",
        "Use the Annual origin tab for diversification-by-producer.")
    ),
    nav_panel(
      "Dependency",
      card(full_screen = TRUE, height = "440px",
           card_header("nrg_ind_id \u2014 import dependency, Germany vs EU-27"),
           plotlyOutput("plot_dep", height = "380px")),
      p(class = "small text-muted",
        "Net imports / gross available energy. Natural gas (G3000) vs all fuels (TOTAL).")
    ),
    nav_panel(
      "Stocks",
      card(full_screen = TRUE, height = "440px",
           card_header("nrg_stk_gasm \u2014 closing stocks on national territory (TJ GCV)"),
           plotlyOutput("plot_stocks", height = "380px"))
    ),
    nav_panel(
      "Supply",
      card(full_screen = TRUE, height = "440px",
           card_header("nrg_cb_gasm \u2014 production, imports, exports, inland consumption"),
           plotlyOutput("plot_supply", height = "380px"))
    ),
    nav_panel(
      "Prices",
      card(full_screen = TRUE, height = "440px",
           card_header("nrg_pc_202 / nrg_pc_203 \u2014 EUR per kWh, excluding VAT (X_VAT)"),
           plotlyOutput("plot_prices", height = "380px")),
      p(class = "small text-muted",
        "Household band D2 (20\u2013199 GJ). Industrial band I3 (10 000\u201399 999 GJ).")
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
        annual = read_csv_safe("imports_annual.csv"),
        monthly = read_csv_safe("imports_monthly.csv"),
        dep = read_csv_safe("dependency.csv"),
        stocks = read_csv_safe("stocks_monthly.csv"),
        supply = read_csv_safe("supply_monthly.csv"),
        hh = read_csv_safe("prices_household.csv"),
        ind = read_csv_safe("prices_industrial.csv")
      )
    }
  )

  annual_g <- reactive({
    d <- bundle()$annual
    req(!is.null(d), nrow(d) > 0)
    d |>
      mutate(time = as.character(time)) |>
      filter(siec == "G3000")
  })

  annual_totals <- reactive({
    annual_g() |>
      filter(partner == "TOTAL") |>
      transmute(time, total = value)
  })

  output$kpi_total <- renderUI({
    tot <- annual_totals()
    req(nrow(tot) > 0)
    last <- tot[tot$time == max(tot$time), ]
    bslib::value_box(
      title = paste("DE imports", last$time),
      value = paste(fmt_int(last$total), "TJ"),
      p(class = "small mb-0", "nrg_ti_gas \u00b7 G3000 TOTAL")
    )
  })

  output$kpi_ru <- renderUI({
    d <- annual_g()
    tot <- annual_totals()
    req(nrow(d) > 0, nrow(tot) > 0)
    yr <- max(tot$time)
    ru <- d$value[d$partner == "RU" & d$time == yr]
    ru <- if (length(ru)) ru[[1]] else 0
    den <- tot$total[tot$time == yr][1]
    bslib::value_box(
      title = "Russia share (origin)",
      value = fmt_pct(100 * ru / den),
      p(class = "small mb-0", yr, "\u00b7 partner RU / TOTAL")
    )
  })

  output$kpi_lng <- renderUI({
    d <- bundle()$annual
    req(!is.null(d), nrow(d) > 0)
    d <- d |> mutate(time = as.character(time))
    yr <- max(d$time[d$siec == "G3000" & d$partner == "TOTAL"])
    g <- d$value[d$siec == "G3000" & d$partner == "TOTAL" & d$time == yr][1]
    lng <- d$value[d$siec == "G3200" & d$partner == "TOTAL" & d$time == yr]
    lng <- if (length(lng)) lng[[1]] else NA_real_
    bslib::value_box(
      title = "LNG share of TOTAL",
      value = fmt_pct(100 * lng / g),
      p(class = "small mb-0", yr, "\u00b7 G3200 / G3000")
    )
  })

  output$kpi_updated <- renderUI({
    m <- bundle()$meta
    req(!is.null(m))
    bslib::value_box(
      title = "Eurostat stamp",
      value = stamp_max(m),
      p(class = "small mb-0", "refresh skips if all cubes unchanged")
    )
  })

  output$overview_note <- renderUI({
    m <- bundle()$meta
    req(!is.null(m))
    tags$p(
      class = "small text-muted mt-2",
      m$note %||% "",
      " Official tables: ",
      tags$a(href = m$browser$nrg_ti_gas, target = "_blank", rel = "noopener", "nrg_ti_gas"),
      ", ",
      tags$a(href = m$browser$nrg_ti_gasm, target = "_blank", rel = "noopener", "nrg_ti_gasm"),
      "."
    )
  })

  output$plot_overview_mix <- renderPlotly({
    g <- group_partners(annual_g())
    tot <- annual_totals()
    req(nrow(g) > 0)
    d <- attach_share(g, tot) |>
      filter(is.finite(share), as.integer(time) >= 2010) |>
      arrange(time, partner_group)
    ly(plot_ly(
      d, x = ~time, y = ~share, color = ~partner_group,
      colors = PARTNER_COLS,
      type = "bar", hoverinfo = "text",
      text = paste0(d$partner_label_g, " \u00b7 ", d$time, ": ", fmt_pct(d$share))
    ) |> layout(
      barmode = "stack",
      xaxis = list(title = "", type = "category"),
      yaxis = list(title = "% of TOTAL", range = c(0, 100))
    ))
  })

  output$plot_overview_dep <- renderPlotly({
    d <- bundle()$dep
    req(!is.null(d), nrow(d) > 0)
    d <- d |>
      mutate(time = as.character(time)) |>
      filter(siec %in% c("G3000", "TOTAL"), is.finite(value))
    d$series <- paste(d$geo_label, d$siec_label)
    ly(plot_ly(
      d, x = ~time, y = ~value, color = ~series, type = "scatter",
      mode = "lines", hoverinfo = "text",
      text = paste0(d$series, " \u00b7 ", d$time, ": ", fmt_pct(d$value))
    ) |> layout(
      xaxis = list(title = "", type = "category"),
      yaxis = list(title = "%")
    ))
  })

  output$plot_annual_stack <- renderPlotly({
    g <- group_partners(annual_g(), n_keep = 10)
    req(nrow(g) > 0)
    d <- g |> filter(as.integer(time) >= 2008) |> arrange(time)
    ly(plot_ly(
      d, x = ~time, y = ~value, color = ~partner_group,
      colors = PARTNER_COLS, type = "bar", hoverinfo = "text",
      text = paste0(d$partner_label_g, " \u00b7 ", d$time, ": ", fmt_int(d$value), " TJ")
    ) |> layout(
      barmode = "stack",
      xaxis = list(title = "", type = "category"),
      yaxis = list(title = "TJ (GCV)", separatethousands = TRUE)
    ))
  })

  output$plot_lng <- renderPlotly({
    d <- bundle()$annual
    req(!is.null(d), nrow(d) > 0)
    d <- d |>
      mutate(time = as.character(time)) |>
      filter(partner == "TOTAL", siec %in% c("G3000", "G3200"),
             is.finite(value), as.integer(time) >= 2008)
    ly(plot_ly(
      d, x = ~time, y = ~value, color = ~siec_label, type = "scatter",
      mode = "lines+markers", hoverinfo = "text",
      text = paste0(d$siec_label, " \u00b7 ", d$time, ": ", fmt_int(d$value), " TJ")
    ) |> layout(
      xaxis = list(title = "", type = "category"),
      yaxis = list(title = "TJ (GCV)", separatethousands = TRUE)
    ))
  })

  output$tbl_annual <- renderReactable({
    d <- annual_g()
    tot <- annual_totals()
    req(nrow(d) > 0, nrow(tot) > 0)
    yr <- max(tot$time)
    den <- tot$total[tot$time == yr][1]
    tab <- d |>
      filter(time == yr, !partner %in% PARTNER_SKIP, is.finite(value), value > 0) |>
      arrange(desc(value)) |>
      transmute(
        Partner = partner_label,
        Code = partner,
        TJ = value,
        Share = 100 * value / den
      )
    reactable(
      tab, pagination = FALSE, highlight = TRUE, compact = TRUE,
      defaultPageSize = 25,
      columns = list(
        Partner = colDef(minWidth = 140),
        Code = colDef(width = 70),
        TJ = colDef(align = "right", cell = function(value) fmt_int(value)),
        Share = colDef(align = "right", cell = function(value) fmt_pct(value))
      )
    )
  })

  output$plot_monthly_stack <- renderPlotly({
    d <- bundle()$monthly
    req(!is.null(d), nrow(d) > 0)
    d <- d |>
      mutate(time = as.character(time)) |>
      filter(siec == "G3000")
    tot <- d |> filter(partner == "TOTAL") |> transmute(time, total = value)
    g <- group_partners(d, n_keep = 8)
    req(nrow(g) > 0)
    times <- sort(unique(g$time))
    keep_t <- tail(times, 72)
    s <- attach_share(g, tot) |>
      filter(time %in% keep_t, is.finite(share))
    ly(plot_ly(
      s, x = ~time, y = ~share, color = ~partner_group,
      colors = PARTNER_COLS, type = "bar", hoverinfo = "text",
      text = paste0(s$partner_label_g, " \u00b7 ", s$time, ": ", fmt_pct(s$share))
    ) |> layout(
      barmode = "stack",
      xaxis = list(title = "", type = "category", dtick = 6),
      yaxis = list(title = "% of TOTAL", range = c(0, 100))
    ))
  })

  output$plot_dep <- renderPlotly({
    d <- bundle()$dep
    req(!is.null(d), nrow(d) > 0)
    d <- d |>
      mutate(time = as.character(time)) |>
      filter(siec %in% c("G3000", "TOTAL", "O4000XBIO"), is.finite(value))
    d$series <- paste(d$geo, d$siec_label)
    ly(plot_ly(
      d, x = ~time, y = ~value, color = ~series, type = "scatter",
      mode = "lines", hoverinfo = "text",
      text = paste0(d$series, " \u00b7 ", d$time, ": ", fmt_pct(d$value))
    ) |> layout(
      xaxis = list(title = "", type = "category"),
      yaxis = list(title = "%")
    ))
  })

  output$plot_stocks <- renderPlotly({
    d <- bundle()$stocks
    req(!is.null(d), nrow(d) > 0)
    d <- d |>
      mutate(time = as.character(time)) |>
      filter(stk_flow %in% c("STKCL_NAT", "STKCL_ABR"), is.finite(value))
    ly(plot_ly(
      d, x = ~time, y = ~value, color = ~stk_flow_label, type = "scatter",
      mode = "lines", hoverinfo = "text",
      text = paste0(d$stk_flow_label, " \u00b7 ", d$time, ": ", fmt_int(d$value), " TJ")
    ) |> layout(
      xaxis = list(title = "", type = "category", dtick = 12),
      yaxis = list(title = "TJ (GCV)", separatethousands = TRUE)
    ))
  })

  output$plot_supply <- renderPlotly({
    d <- bundle()$supply
    req(!is.null(d), nrow(d) > 0)
    keep <- c("IPRD", "IMP", "EXP", "IC_OBS")
    d <- d |>
      mutate(time = as.character(time)) |>
      filter(nrg_bal %in% keep, is.finite(value))
    times <- sort(unique(d$time))
    d <- d |> filter(time %in% tail(times, 96))
    ly(plot_ly(
      d, x = ~time, y = ~value, color = ~nrg_bal_label, type = "scatter",
      mode = "lines", hoverinfo = "text",
      text = paste0(d$nrg_bal_label, " \u00b7 ", d$time, ": ", fmt_int(d$value), " TJ")
    ) |> layout(
      xaxis = list(title = "", type = "category", dtick = 6),
      yaxis = list(title = "TJ (GCV)", separatethousands = TRUE)
    ))
  })

  output$plot_prices <- renderPlotly({
    hh <- bundle()$hh
    ind <- bundle()$ind
    req(!is.null(hh), !is.null(ind))
    hh2 <- hh |>
      filter(nrg_cons == "GJ20-199", tax == "X_VAT", is.finite(value)) |>
      mutate(series = "Household D2 (excl. VAT)")
    ind2 <- ind |>
      filter(nrg_cons == "GJ10000-99999", tax == "X_VAT", is.finite(value)) |>
      mutate(series = "Industry I3 (excl. VAT)")
    d <- bind_rows(hh2, ind2) |> mutate(time = as.character(time))
    req(nrow(d) > 0)
    ly(plot_ly(
      d, x = ~time, y = ~value, color = ~series, type = "scatter",
      mode = "lines+markers", hoverinfo = "text",
      text = paste0(d$series, " \u00b7 ", d$time, ": ", fmt_num(d$value, 3), " EUR/kWh")
    ) |> layout(
      xaxis = list(title = "", type = "category"),
      yaxis = list(title = "EUR / kWh")
    ))
  })
}

shinyApp(ui, server)
