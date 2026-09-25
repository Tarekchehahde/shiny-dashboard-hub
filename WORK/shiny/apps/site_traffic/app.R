# =============================================================================
# site_traffic — private nginx access-log viewer (not listed on public hub).
# URL: /site_traffic/  ·  set MASTR_TRAFFIC_USER / MASTR_TRAFFIC_PASS on server.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(ggplot2)
  library(reactable)
  library(scales)
})

source("../../R/ui_helpers.R")
source("../../R/nginx_analytics.R")

auth_cfg <- traffic_auth_expected()

ui <- fluidPage(
  title = "Site traffic",
  theme = mastr_theme("#334155"),
  mastr_responsive_css(),
  tags$style(HTML("
    .traffic-login { max-width: 360px; margin: 4rem auto; }
    .traffic-meta { font-size: 0.8rem; color: #64748b; }
  ")),
  uiOutput("gate"),
  uiOutput("main_ui")
)

login_ui <- function() {
  div(
    class = "traffic-login card shadow-sm",
    card_body(
      h4("Site traffic", class = "mb-3"),
      p(class = "text-muted small", "Private view of nginx access logs."),
      textInput("login_user", "User", value = auth_cfg$user),
      passwordInput("login_pass", "Password"),
      actionButton("login_btn", "Sign in", class = "btn-primary w-100"),
      uiOutput("login_err")
    )
  )
}

main_ui <- function() {
  tagList(
    div(
      class = "py-2 mb-2 d-flex flex-wrap justify-content-between align-items-center gap-2",
      div(
        h2("Site traffic", class = "mb-0"),
        p(class = "text-muted mb-0", "nginx page views · refreshed on demand")
      ),
      div(
        class = "d-flex flex-wrap gap-2 align-items-center",
        selectInput(
          "days", "Window", choices = c("24 hours" = 1, "7 days" = 7, "30 days" = 30),
          selected = 7, width = "140px"
        ),
        selectInput(
          "audience", "Show",
          choices = c(
            "All traffic" = "all",
            "Organic only" = "organic",
            "Bots & scanners" = "non_organic"
          ),
          selected = "all",
          width = "170px"
        ),
        actionButton("refresh", "Refresh", class = "btn-primary"),
        actionLink("logout", "Sign out", class = "small")
      )
    ),
    uiOutput("log_status"),
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      mastr_kpi("Page views", textOutput("kpi_hits", inline = TRUE), color = "primary"),
      mastr_kpi("Organic", textOutput("kpi_organic", inline = TRUE), color = "success"),
      mastr_kpi("Bots / scanners", textOutput("kpi_bots", inline = TRUE), color = "warning"),
      mastr_kpi("Cloud / VPS", textOutput("kpi_cloud", inline = TRUE), color = "danger")
    ),
    layout_columns(
      col_widths = c(3, 3, 3, 3),
      mastr_kpi("Unique IPs", textOutput("kpi_ips", inline = TRUE), color = "info"),
      mastr_kpi("Top dashboard", textOutput("kpi_top", inline = TRUE), color = "dark"),
      mastr_kpi("Log file", textOutput("kpi_log", inline = TRUE), color = "secondary"),
      mastr_kpi("Filter", textOutput("kpi_filter", inline = TRUE), color = "light")
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        card_header("Visits per day"),
        card_body(plotOutput("plot_day", height = "260px"))
      ),
      card(
        card_header("Organic vs automated"),
        card_body(plotOutput("plot_kind", height = "260px"))
      )
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("Dashboards"),
        card_body(reactableOutput("tbl_dashboards"))
      ),
      card(
        card_header("Visitors (IP)"),
        card_body(reactableOutput("tbl_ips"))
      )
    ),
    card(
      card_header("Recent page views"),
      card_body(reactableOutput("tbl_recent", height = "420px"))
    ),
    div(
      class = "traffic-meta text-center mt-3",
      "Organic = real browser with referer or repeat views. Cloud = datacenter/proxy IP. Bot/Scanner = crawlers and scripts."
    )
  )
}

server <- function(input, output, session) {
  authed <- reactiveVal(!auth_cfg$enabled)

  output$gate <- renderUI({
    if (!authed()) login_ui() else NULL
  })

  output$main_ui <- renderUI({
    if (authed()) main_ui() else NULL
  })

  output$login_err <- renderUI({
    req(input$login_btn)
    if (traffic_check_login(input$login_user, input$login_pass)) {
      return(NULL)
    }
    div(class = "text-danger small mt-2", "Invalid credentials.")
  })

  observeEvent(input$login_btn, {
    if (traffic_check_login(input$login_user, input$login_pass)) {
      authed(TRUE)
    }
  }, ignoreInit = TRUE)

  observeEvent(input$logout, {
    authed(FALSE)
  }, ignoreInit = TRUE)

  traffic_data <- eventReactive(
    list(input$refresh, input$days, input$audience, authed()),
    {
      req(authed())
      path <- nginx_log_path()
      raw <- tryCatch(
        read_nginx_access(path),
        error = function(e) {
          list(error = conditionMessage(e), path = path)
        }
      )
      if (!is.data.frame(raw)) {
        return(raw)
      }
      list(
        path = path,
        summary = nginx_traffic_summary(
          raw,
          days = as.integer(input$days),
          audience = input$audience
        )
      )
    },
    ignoreInit = FALSE
  )

  output$log_status <- renderUI({
    req(authed())
    d <- traffic_data()
    if (!is.null(d$error)) {
      return(div(
        class = "alert alert-danger py-2",
        "Cannot read log: ", tags$code(d$error),
        " — add user ", tags$code("rstudio"), " to group ", tags$code("adm"),
        " or set ", tags$code("MASTR_NGINX_LOG"), "."
      ))
    }
    s <- d$summary
    tags$p(
      class = "traffic-meta mb-2",
      "Source: ", tags$code(d$path),
      " · last refresh ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
    )
  })

  output$kpi_hits <- renderText({
    d <- traffic_data()
    req(is.null(d$error))
    format(d$summary$total_hits, big.mark = ".")
  })

  output$kpi_organic <- renderText({
    d <- traffic_data()
    req(is.null(d$error))
    format(d$summary$organic_hits, big.mark = ".")
  })

  output$kpi_bots <- renderText({
    d <- traffic_data()
    req(is.null(d$error))
    format(d$summary$bot_hits, big.mark = ".")
  })

  output$kpi_cloud <- renderText({
    d <- traffic_data()
    req(is.null(d$error))
    format(d$summary$cloud_hits, big.mark = ".")
  })

  output$kpi_uncertain <- renderText({
    d <- traffic_data()
    req(is.null(d$error))
    format(d$summary$uncertain_hits, big.mark = ".")
  })

  output$kpi_filter <- renderText({
    switch(
      input$audience,
      all = "All",
      organic = "Organic",
      non_organic = "Bots"
    )
  })

  output$kpi_ips <- renderText({
    d <- traffic_data()
    req(is.null(d$error))
    format(d$summary$unique_ips, big.mark = ".")
  })

  output$kpi_top <- renderText({
    d <- traffic_data()
    req(is.null(d$error))
    bd <- d$summary$by_dashboard
    if (!nrow(bd)) {
      return("\u2014")
    }
    paste0(bd$dashboard[1], " (", bd$hits[1], ")")
  })

  output$kpi_log <- renderText({
    d <- traffic_data()
    req(is.null(d$error))
    basename(d$path)
  })

  output$plot_day <- renderPlot({
    d <- traffic_data()
    req(is.null(d$error))
    bd <- d$summary$by_day
    if (!nrow(bd)) {
      return(mastr_empty_plot("No data"))
    }
    ggplot(bd, aes(day, hits)) +
      geom_col(fill = "#334155", width = 0.85) +
      scale_x_date(labels = label_date_short()) +
      scale_y_continuous(labels = label_number(big.mark = ".")) +
      labs(x = NULL, y = "Page views") +
      theme_minimal(base_size = 11)
  })

  output$plot_kind <- renderPlot({
    d <- traffic_data()
    req(is.null(d$error))
    bd <- d$summary$by_day_kind
    if (!nrow(bd)) {
      return(mastr_empty_plot("No data"))
    }
    kind_colors <- c(
      Organic = "#16a34a",
      Mixed = "#22c55e",
      Uncertain = "#94a3b8",
      Cloud = "#dc2626",
      Bot = "#f59e0b",
      Scanner = "#ef4444"
    )
    ggplot(bd, aes(day, hits, fill = visitor_kind)) +
      geom_col(position = "stack", width = 0.85) +
      scale_fill_manual(values = kind_colors) +
      scale_x_date(labels = label_date_short()) +
      scale_y_continuous(labels = label_number(big.mark = ".")) +
      labs(x = NULL, y = "Page views", fill = "Kind") +
      theme_minimal(base_size = 11) +
      theme(legend.position = "bottom", legend.title = element_blank())
  })

  output$tbl_dashboards <- renderReactable({
    d <- traffic_data()
    req(is.null(d$error))
    reactable(
      d$summary$by_dashboard,
      compact = TRUE,
      defaultSorted = "hits",
      columns = list(
        dashboard = colDef(name = "Dashboard"),
        hits = colDef(name = "Views", format = colFormat(separators = TRUE))
      )
    )
  })

  output$tbl_ips <- renderReactable({
    d <- traffic_data()
    req(is.null(d$error))
    reactable(
      d$summary$by_ip,
      compact = TRUE,
      defaultSorted = "hits",
      columns = list(
        ip = colDef(name = "IP"),
        hits = colDef(name = "Views", format = colFormat(separators = TRUE)),
        country = colDef(name = "Country"),
        city = colDef(name = "City"),
        last_seen = colDef(name = "Last seen", format = colFormat(datetime = TRUE)),
        visitor_kind = colDef(name = "Kind"),
        device = colDef(name = "Device")
      )
    )
  })

  output$tbl_recent <- renderReactable({
    d <- traffic_data()
    req(is.null(d$error))
    reactable(
      d$summary$recent,
      compact = TRUE,
      defaultPageSize = 15,
      columns = list(
        time = colDef(name = "Time", format = colFormat(datetime = TRUE)),
        ip = colDef(name = "IP"),
        country = colDef(name = "Country"),
        city = colDef(name = "City"),
        dashboard = colDef(name = "Dashboard"),
        path = colDef(name = "Path"),
        visitor_kind = colDef(name = "Kind"),
        device = colDef(name = "Device"),
        status = colDef(name = "HTTP")
      )
    )
  })
}

shinyApp(ui, server)
