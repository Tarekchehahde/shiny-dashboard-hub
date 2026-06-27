# =============================================================================
# care_workers_thuringia — Research dashboard
# Navigating Expectations in the Recruitment Journey of Care Workers in Thuringia
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(plotly)
  library(leaflet)
  library(reactable)
  library(jsonlite)
  library(scales)
})

source("../../R/ui_helpers.R")
source("../../R/care_workers_data.R")

`%||%` <- function(x, y) if (is.null(x)) y else x

CARE_PRIMARY <- "#6366f1"
INTERVIEWS <- care_workers_load_interviews()
ORGS <- care_workers_load_orgs()
ANALYSIS <- care_workers_load_analysis()
VIZ_LINKS <- care_workers_viz_links()

INTERVIEW_CHOICES <- sort(unique(INTERVIEWS$Interview))
THEME_CHOICES <- levels(INTERVIEWS$Theme)
CODE_CHOICES <- sort(unique(INTERVIEWS$Code))

ui <- mastr_page(
  title = "Care Workers in Th\u00fcringen",
  subtitle = paste0(
    "Navigating Expectations \u2014 ",
    ANALYSIS$summary$total_entries, " coded interview extracts \u00b7 ",
    ANALYSIS$summary$total_interviews, " stakeholders \u00b7 ",
    nrow(ORGS), " mapped organizations"
  ),
  fluid = TRUE,
  primary = CARE_PRIMARY,
  footer = "care_workers",
  hub_back_label = "\u2190 Back to hub",
  creator_qr_lang = "en",
  tags$style(HTML("
    .care-banner {
      background: linear-gradient(135deg, rgba(99,102,241,.18), rgba(139,92,246,.12));
      border: 1px solid rgba(99,102,241,.35);
      border-radius: 12px;
      padding: .85rem 1rem;
      margin-bottom: 1rem;
      font-size: .92rem;
    }
    .viz-card {
      border: 1px solid rgba(148,163,184,.2);
      border-radius: 12px;
      padding: 1rem;
      height: 100%;
      background: rgba(15,23,42,.55);
      transition: border-color .2s, transform .2s;
    }
    .viz-card:hover { border-color: rgba(99,102,241,.55); transform: translateY(-2px); }
    .viz-card h4 { font-size: 1rem; margin: 0 0 .35rem; }
    .viz-card p { font-size: .85rem; color: #94a3b8; margin: 0 0 .75rem; }
    .viz-frame { width: 100%; min-height: 520px; border: 0; border-radius: 10px; background: #0a0a12; }
    .org-map { min-height: 480px; border-radius: 10px; }
  ")),
  div(
    class = "care-banner",
    tags$strong("Research project"),
    " \u2014 qualitative stakeholder interviews (LEG, AWO AJS, IBS, Diako) ",
    "and a mapped landscape of ",
    tags$strong("59 healthcare & migration organizations"),
    " across Th\u00fcringen. ",
    tags$a(href = "https://github.com/Tarekchehahde/Navigating-Expectations-Care-Workers-Thuringia",
           target = "_blank", rel = "noopener", "GitHub repo")
  ),
  navset_card_tab(
    nav_panel(
      "Overview",
      layout_columns(
        col_widths = c(3, 3, 3, 3),
        mastr_kpi("Coded extracts", ANALYSIS$summary$total_entries, "Interview passages", color = "primary"),
        mastr_kpi("Stakeholders", ANALYSIS$summary$total_interviews, "Semi-structured interviews", color = "info"),
        mastr_kpi("Themes", ANALYSIS$summary$total_themes, "Qualitative code groups", color = "success"),
        mastr_kpi("Organizations", nrow(ORGS), "Mapped in Th\u00fcringen", color = "warning")
      ),
      layout_columns(
        col_widths = c(6, 6),
        card(
          card_header("Theme distribution"),
          plotlyOutput("plot_themes", height = "340px")
        ),
        card(
          card_header("Entries by interview"),
          plotlyOutput("plot_interviews", height = "340px")
        )
      ),
      layout_columns(
        col_widths = c(4, 4, 4),
        card(
          card_header("Recruitment countries mentioned"),
          plotlyOutput("plot_countries", height = "280px")
        ),
        card(
          card_header("Challenge keywords"),
          plotlyOutput("plot_challenges", height = "280px")
        ),
        card(
          card_header("Support behaviour"),
          plotlyOutput("plot_behaviors", height = "280px")
        )
      )
    ),
    nav_panel(
      "Organizations",
      layout_sidebar(
        sidebar = sidebar(
          width = 280,
          title = "Map filters",
          selectInput(
            "org_sector", "Sector",
            choices = c("All sectors" = "all", sort(unique(ORGS$Sector))),
            selected = "all"
          ),
          selectInput(
            "org_location", "Location",
            choices = c("All locations" = "all", sort(unique(ORGS$Location))),
            selected = "all"
          ),
          tags$p(class = "small text-muted mb-0",
                 "Source: Weltoffenes Th\u00fcringen + Bundesagentur f\u00fcr Arbeit mapping (Nov 2025).")
        ),
        layout_columns(
          col_widths = c(8, 4),
          leafletOutput("org_map", height = "520px"),
          card(
            card_header("By location"),
            plotlyOutput("plot_org_locations", height = "240px"),
            card_header("By sector", class = "mt-2"),
            plotlyOutput("plot_org_sectors", height = "220px")
          )
        ),
        card(
          card_header("Organization directory"),
          reactableOutput("org_table")
        )
      )
    ),
    nav_panel(
      "Interviews",
      layout_sidebar(
        sidebar = sidebar(
          width = 300,
          title = "Filters",
          checkboxGroupInput("f_interview", "Interview", choices = INTERVIEW_CHOICES,
                             selected = INTERVIEW_CHOICES),
          checkboxGroupInput("f_theme", "Theme", choices = THEME_CHOICES,
                             selected = THEME_CHOICES),
          selectizeInput("f_code", "Codes", choices = CODE_CHOICES, selected = CODE_CHOICES,
                         multiple = TRUE, options = list(plugins = list("remove_button"))),
          textInput("f_search", "Search extracts", placeholder = "Keyword in quote text\u2026"),
          tags$p(class = "small text-muted", textOutput("filter_count", inline = TRUE))
        ),
        layout_columns(
          col_widths = c(6, 6),
          card(card_header("Code heatmap"), plotlyOutput("plot_heatmap", height = "360px")),
          card(card_header("Theme by interview"), plotlyOutput("plot_theme_stack", height = "360px"))
        ),
        card(
          card_header("Coded extracts"),
          reactableOutput("extract_table")
        )
      )
    ),
    nav_panel(
      "Advanced viz",
      p(class = "text-muted", "Full-screen interactive dashboards from the research project."),
      layout_columns(
        col_widths = c(4, 4, 4),
        !!!lapply(VIZ_LINKS, function(v) {
          card(
            div(
              class = "viz-card",
              tags$h4(v$title),
              tags$p(v$desc),
              tags$a(
                class = "btn btn-sm btn-primary",
                href = paste0("viz/", v$file),
                target = "_blank",
                rel = "noopener",
                "Open dashboard"
              )
            )
          )
        })
      ),
      hr(),
      selectInput("viz_embed", "Preview in page",
                  choices = c("Select a dashboard\u2026" = "", setNames(
                    vapply(VIZ_LINKS, function(x) paste0("viz/", x$file), character(1)),
                    vapply(VIZ_LINKS, `[[`, character(1), "title")
                  ))),
      uiOutput("viz_iframe_ui")
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  filtered <- reactive({
    df <- INTERVIEWS
    if (length(input$f_interview)) {
      df <- df[df$Interview %in% input$f_interview, , drop = FALSE]
    }
    if (length(input$f_theme)) {
      df <- df[as.character(df$Theme) %in% input$f_theme, , drop = FALSE]
    }
    if (length(input$f_code)) {
      df <- df[df$Code %in% input$f_code, , drop = FALSE]
    }
    q <- input$f_search %||% ""
    if (nzchar(trimws(q))) {
      df <- df[grepl(q, df$`Data Extract`, ignore.case = TRUE), , drop = FALSE]
    }
    df
  })

  output$filter_count <- renderText({
    sprintf("%s of %s extracts shown", nrow(filtered()), nrow(INTERVIEWS))
  })

  filtered_orgs <- reactive({
    df <- ORGS
    if (!identical(input$org_sector, "all")) {
      df <- df[df$Sector == input$org_sector, , drop = FALSE]
    }
    if (!identical(input$org_location, "all")) {
      df <- df[df$Location == input$org_location, , drop = FALSE]
    }
    df
  })

  plotly_dark <- function(p) {
    ggplotly(p, tooltip = "text") |>
      layout(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(0,0,0,0)",
        font = list(color = "#e2e8f0"),
        legend = list(orientation = "h", y = -0.15)
      )
  }

  output$plot_themes <- renderPlotly({
    th <- ANALYSIS$themes
    td <- data.frame(
      theme = names(th),
      count = vapply(th, function(x) x$count, numeric(1)),
      percentage = vapply(th, function(x) x$percentage, numeric(1)),
      stringsAsFactors = FALSE
    )
    td <- td[order(-td$count), ]
    p <- ggplot(td, aes(x = reorder(theme, count), y = count, fill = theme,
                        text = paste0(theme, ": ", count, " (", percentage, "%)"))) +
      geom_col(show.legend = FALSE) +
      scale_fill_manual(values = care_workers_theme_color(td$theme)) +
      coord_flip() +
      labs(x = NULL, y = "Entries") +
      theme_minimal(base_size = 13) +
      theme(panel.grid.minor = element_blank())
    plotly_dark(p)
  })

  output$plot_interviews <- renderPlotly({
    df <- INTERVIEWS |>
      count(Interview, name = "count")
    p <- ggplot(df, aes(x = reorder(Interview, count), y = count, fill = Interview,
                        text = paste(Interview, count, sep = ": "))) +
      geom_col(show.legend = FALSE) +
      scale_fill_brewer(palette = "Set2") +
      coord_flip() +
      labs(x = NULL, y = "Entries") +
      theme_minimal(base_size = 13)
    plotly_dark(p)
  })

  named_bar <- function(named_vec, title = NULL) {
    df <- data.frame(name = names(named_vec), count = unname(named_vec), stringsAsFactors = FALSE)
    df <- df[order(-df$count), ]
    p <- ggplot(df, aes(x = reorder(name, count), y = count, fill = name,
                        text = paste(name, count, sep = ": "))) +
      geom_col(show.legend = FALSE) +
      scale_fill_brewer(palette = "Pastel1") +
      coord_flip() +
      labs(x = NULL, y = "Mentions", title = title) +
      theme_minimal(base_size = 12)
    plotly_dark(p)
  }

  output$plot_countries <- renderPlotly({
    named_bar(ANALYSIS$countries)
  })

  output$plot_challenges <- renderPlotly({
    named_bar(ANALYSIS$challenges)
  })

  output$plot_behaviors <- renderPlotly({
    named_bar(ANALYSIS$behaviors)
  })

  output$org_map <- renderLeaflet({
    df <- filtered_orgs()
    pal <- colorFactor("Set2", domain = unique(ORGS$Sector))
    leaflet(df) |>
      addProviderTiles(providers$CartoDB.DarkMatter) |>
      setView(lng = 10.75, lat = 50.95, zoom = 8) |>
      addCircleMarkers(
        ~Longitude, ~Latitude,
        radius = 7,
        stroke = TRUE, weight = 1, opacity = 0.9,
        fillOpacity = 0.85,
        color = ~pal(Sector),
        label = ~Institutions,
        popup = ~paste0(
          "<strong>", Institutions, "</strong><br>",
          Location, " · ", Sector, "<br>",
          "<a href='", Website, "' target='_blank'>Website</a>"
        )
      ) |>
      addLegend("bottomright", pal = pal, values = ORGS$Sector, title = "Sector")
  })

  output$plot_org_locations <- renderPlotly({
    df <- ORGS |>
      count(Location, sort = TRUE) |>
      slice_head(n = 12)
    p <- ggplot(df, aes(x = reorder(Location, n), y = n, fill = Location)) +
      geom_col(show.legend = FALSE) +
      coord_flip() +
      labs(x = NULL, y = "Organizations") +
      theme_minimal(base_size = 12)
    plotly_dark(p)
  })

  output$plot_org_sectors <- renderPlotly({
    df <- ORGS |> count(Sector)
    p <- ggplot(df, aes(x = "", y = n, fill = Sector)) +
      geom_col(width = 1) +
      coord_polar("y") +
      scale_fill_brewer(palette = "Set2") +
      theme_void(base_size = 12) +
      theme(legend.position = "right")
    plotly_dark(p)
  })

  output$org_table <- renderReactable({
    reactable(
      filtered_orgs() |>
        select(Institutions, Location, Sector, Email, Website),
      searchable = TRUE,
      striped = TRUE,
      highlight = TRUE,
      defaultPageSize = 10,
      columns = list(
        Website = colDef(
          cell = function(value) {
            if (is.na(value) || !nzchar(value)) return("")
            htmltools::tags$a(href = value, target = "_blank", "Link")
          }
        )
      )
    )
  })

  output$plot_heatmap <- renderPlotly({
    df <- filtered()
    if (!nrow(df)) {
      return(plotly_empty(type = "scatter", mode = "markers") |>
               layout(title = list(text = "No data for current filters", font = list(color = "#94a3b8"))))
    }
    mat <- as.data.frame.matrix(table(df$Code, df$Interview))
    plot_ly(
      x = colnames(mat),
      y = rownames(mat),
      z = as.matrix(mat),
      type = "heatmap",
      colorscale = "Viridis"
    ) |>
      layout(
        xaxis = list(title = "Interview"),
        yaxis = list(title = "Code"),
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(0,0,0,0)",
        font = list(color = "#e2e8f0")
      )
  })

  output$plot_theme_stack <- renderPlotly({
    df <- filtered() |>
      count(Interview, Theme)
    p <- ggplot(df, aes(x = Interview, y = n, fill = Theme)) +
      geom_col(position = "stack") +
      scale_fill_manual(values = CARE_THEME_COLORS) +
      labs(x = NULL, y = "Entries", fill = NULL) +
      theme_minimal(base_size = 12) +
      theme(axis.text.x = element_text(angle = 30, hjust = 1))
    plotly_dark(p)
  })

  output$extract_table <- renderReactable({
    reactable(
      filtered() |>
        select(Interview, Code, `Code Name`, Theme, `Data Extract`),
      searchable = FALSE,
      striped = TRUE,
      highlight = TRUE,
      defaultPageSize = 8,
      columns = list(
        Theme = colDef(
          cell = function(value) {
            htmltools::tags$span(
              style = paste0(
                "background:", care_workers_theme_color(value),
                ";color:#fff;padding:2px 8px;border-radius:999px;font-size:11px"
              ),
              value
            )
          }
        ),
        `Data Extract` = colDef(minWidth = 320)
      )
    )
  })

  output$viz_iframe_ui <- renderUI({
    src <- input$viz_embed
    if (!nzchar(src)) {
      return(tags$p(class = "text-muted", "Choose a dashboard above to embed a live preview."))
    }
    tags$iframe(class = "viz-frame", src = src, title = "Research visualization")
  })
}

shinyApp(ui, server)
