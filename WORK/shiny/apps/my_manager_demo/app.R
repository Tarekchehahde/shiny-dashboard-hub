# =============================================================================
# my_manager_demo — executive pitch dashboard (DE/EN, month drill-down,
# MaStR-scale solar inverter intake simulation).
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(htmltools)
  library(dplyr)
  library(plotly)
  library(tibble)
})

source("../../R/ui_helpers.R")

HUB_URL <- mastr_hub_url()

.app_href <- function(id) {
  if (identical(Sys.getenv("MASTR_HUB_MODE", "paths"), "ports")) {
    ports <- c(
      most_visited = 3839L, health_wealth_nations = 3841L,
      lebanese_elections = 3842L, dummy_demo = 3840L,
      my_manager_demo = 3843L, deutschland_solar_radiation = 3844L
    )
    sprintf("http://localhost:%s/", ports[[id]])
  } else {
    sprintf("/%s/", id)
  }
}

# --- i18n --------------------------------------------------------------------

L <- function(lang, en, de) if (identical(lang, "de")) de else en

pretty_month <- function(ym, lang = "en") {
  d <- as.Date(paste0(ym, "-01"))
  if (identical(lang, "de")) {
    de_m <- c("Januar", "Februar", "März", "April", "Mai", "Juni",
              "Juli", "August", "September", "Oktober", "November", "Dezember")
    paste(de_m[as.integer(format(d, "%m"))], format(d, "%Y"))
  } else {
    format(d, "%B %Y")
  }
}

PIPELINE <- list(
  list(step = 1L, icon = "💬",
       en = list(title = "Request", short = "Stakeholder describes the business question.",
                 detail = "A team or client submits a dashboard idea: target audience, key metrics, data sources, and desired interactions (filters, drill-down, exports)."),
       de = list(title = "Anfrage", short = "Stakeholder beschreibt die Geschäftsfrage.",
                 detail = "Team oder Kunde reicht eine Dashboard-Idee ein: Zielgruppe, Kennzahlen, Datenquellen und gewünschte Interaktionen (Filter, Drill-down, Export).")),
  list(step = 2L, icon = "📋",
       en = list(title = "Scope & data", short = "We confirm feasibility, data access, and mock-ups.",
                 detail = "Analyst checks data availability (CSV, DB, API), agrees on layout, and produces a short spec — what users will see on day one."),
       de = list(title = "Scope & Daten", short = "Machbarkeit, Datenzugang und Mock-ups klären.",
                 detail = "Analyst prüft Datenverfügbarkeit (CSV, DB, API), einigt Layout ab und liefert ein kurzes Lastenheft — was Nutzer am Go-live sehen.")),
  list(step = 3L, icon = "🛠",
       en = list(title = "Build in RStudio", short = "Develop the Shiny app on the shared server.",
                 detail = "Dashboard-Code liegt in Git (`WORK/shiny/apps/<name>/`). RStudio Server auf dem VPS ist die IDE — kein lokales R nötig."),
       de = list(title = "Build in RStudio", short = "Shiny-App auf dem gemeinsamen Server entwickeln.",
                 detail = "Code in Git (`WORK/shiny/apps/<name>/`). RStudio Server auf dem VPS — Autoren brauchen kein lokales R.")),
  list(step = 4L, icon = "✓",
       en = list(title = "Review & UAT", short = "Client tests in the browser and gives feedback.",
                 detail = "Stakeholder öffnen Preview-URL, testen Filter, prüfen Zahlen und geben Freigabe vor Go-live."),
       de = list(title = "Review & UAT", short = "Kunde testet im Browser und gibt Feedback.",
                 detail = "Stakeholder öffnen Preview, klicken Filter, validieren Zahlen und signieren vor Go-live.")),
  list(step = 5L, icon = "🚀",
       en = list(title = "Deploy to hub", short = "One-click-style ops: systemd + nginx route.",
                 detail = "Die App erhält Port und URL-Pfad (z. B. `/sales_kpi/`). Neue Karte auf der Hub-Landingpage — andere Dashboards bleiben unberührt."),
       de = list(title = "Deploy zum Hub", short = "Ops wie per Knopfdruck: systemd + nginx.",
                 detail = "Eigener Port und Pfad (z. B. `/sales_kpi/`). Neue Karte auf dem Hub — ohne Neustart anderer Apps.")),
  list(step = 6L, icon = "👥",
       en = list(title = "Users browse & interact", short = "End users need only a browser bookmark.",
                 detail = "Kein R, kein Tableau Desktop, kein VPN für Viewer. Hub öffnen, Dashboard wählen, Sidebar-Filter wie in jeder Web-App."),
       de = list(title = "Nutzer browsen & interagieren", short = "Endnutzer brauchen nur ein Browser-Lesezeichen.",
                 detail = "Kein R, kein Tableau Desktop, kein VPN. Hub öffnen, Dashboard wählen, Filter nutzen — wie jede Web-App."))
)

catalog_defs <- function(lang) {
  list(
    list(id = "most_visited",
         title = L(lang, "Most Visited", "Most Visited"),
         badge = L(lang, "Production", "Produktion"),
         desc = L(lang,
                  "MaStR solar build-out — filters, KPIs, YTD table.",
                  "MaStR Solar-Zubau — Filter, KPIs, YTD-Tabelle.")),
    list(id = "deutschland_solar_radiation",
         title = L(lang, "Solar Radiation Germany", "Solarstrahlung Deutschland"),
         badge = L(lang, "Live API", "Live API"),
         desc = L(lang,
                  "Live GHI map — Open-Meteo / DWD-based satellite models.",
                  "Live GHI-Karte — Open-Meteo / DWD-Satellitenmodelle.")),
    list(id = "lebanese_elections",
         title = L(lang, "Lebanese Elections", "Libanesische Wahlen"),
         badge = L(lang, "Tableau parity", "Tableau-Parität"),
         desc = L(lang,
                  "Interactive election maps — click-to-filter across views.",
                  "Interaktive Wahlkarten — Klick filtert alle Ansichten.")),
    list(id = "health_wealth_nations",
         title = L(lang, "Health & Wealth", "Gesundheit & Wohlstand"),
         badge = L(lang, "Animation", "Animation"),
         desc = L(lang,
                  "Gapminder-style bubble chart with year slider.",
                  "Gapminder-Bubble-Chart mit Jahr-Slider.")),
    list(id = "dummy_demo",
         title = L(lang, "Demo Dashboard", "Demo-Dashboard"),
         badge = L(lang, "Template", "Vorlage"),
         desc = L(lang,
                  "Simple KPI + chart pattern for new apps.",
                  "Einfaches KPI- + Chart-Muster für neue Apps."))
  )
}

# --- Simulated MaStR-scale solar inverter registrations (~385k units) --------

generate_inverter_stream <- function() {
  set.seed(202506)
  days <- seq(as.Date("2024-01-01"), as.Date("2025-12-31"), by = "day")
  n <- 385000L
  month_w <- c(0.035, 0.045, 0.075, 0.095, 0.11, 0.12, 0.125, 0.115,
               0.095, 0.075, 0.055, 0.06)
  w <- month_w[as.integer(format(days, "%m"))]
  w <- w / sum(w)
  reg_day <- sample(days, n, replace = TRUE, prob = w)
  capacity_kw <- pmin(pmax(rlnorm(n, log(8.5), 0.55), 0.5), 500)
  tibble(reg_date = reg_day, capacity_kw = capacity_kw) |>
    mutate(
      year_month = format(reg_date, "%Y-%m"),
      day = as.character(reg_date)
    ) |>
    group_by(day, year_month) |>
    summarise(
      n_units = n(),
      capacity_mw = sum(capacity_kw) / 1000,
      .groups = "drop"
    )
}

INVERTER_DAILY <- generate_inverter_stream()
MONTH_CHOICES <- sort(unique(INVERTER_DAILY$year_month), decreasing = TRUE)
DEFAULT_MONTH <- MONTH_CHOICES[1L]

pipeline_step_ui <- function(s, lang) {
  t <- s[[if (identical(lang, "de")) "de" else "en"]]
  actionButton(
    inputId = paste0("pipe_step_", s$step),
    label = tagList(
      tags$span(class = "pipeline-icon", s$icon),
      tags$strong(sprintf("%d. %s", s$step, t$title)),
      tags$span(class = "d-block small text-muted mt-1 fw-normal", t$short)
    ),
    class = "pipeline-step w-100 text-start"
  )
}

catalog_card <- function(d, lang) {
  card(
    class = "h-100",
    card_header(
      tags$span(class = "badge bg-primary me-2", d$badge),
      d$title
    ),
    p(class = "text-muted small mb-2", d$desc),
    tags$a(
      class = "btn btn-sm btn-outline-primary",
      href = .app_href(d$id), target = "_self",
      L(lang, "Open live →", "Live öffnen →")
    )
  )
}

build_tabs_ui <- function(lang) {
  cat <- catalog_defs(lang)
  navset_card_tab(
    id = "main_tabs",
    height = "auto",
    nav_panel(
      L(lang, "Executive summary", "Executive Summary"),
      layout_column_wrap(
        width = 1/4,
        value_box(title = L(lang, "For viewers", "Für Viewer"),
                  value = L(lang, "Browser only", "Nur Browser"), theme = "primary"),
        value_box(title = L(lang, "For authors", "Für Autoren"),
                  value = "RStudio Server", theme = "info"),
        value_box(title = L(lang, "Delivery", "Lieferzeit"),
                  value = L(lang, "Days–weeks", "Tage–Wochen"), theme = "success"),
        value_box(title = L(lang, "Hosting", "Hosting"),
                  value = L(lang, "Our VPS / cloud", "Unser VPS / Cloud"), theme = "warning")
      ),
      card(
        card_header(L(lang, "Why fund this?", "Warum investieren?")),
        layout_columns(
          col_widths = c(6, 6),
          tags$ul(
            tags$li(strong(L(lang, "Central catalogue", "Zentraler Katalog")),
                    L(lang, " — one URL; managers pick the dashboard they need.",
                      " — eine URL; Manager wählen das passende Dashboard.")),
            tags$li(strong(L(lang, "Interactive by default", "Interaktiv standardmäßig")),
                    L(lang, " — filters, tooltips, linked charts (not static PDFs).",
                      " — Filter, Tooltips, verknüpfte Charts (keine statischen PDFs).")),
            tags$li(strong("R ecosystem"), " — ",
                    L(lang, "reuse existing R scripts and company analyses.",
                      "bestehende R-Skripte und Analysen wiederverwenden.")),
            tags$li(strong(L(lang, "Controlled access", "Kontrollierter Zugang")),
                    L(lang, " — SSO, VPN, or internal DNS later.",
                      " — SSO, VPN oder internes DNS später möglich.")),
            tags$li(strong(L(lang, "Tableau migration path", "Tableau-Migrationspfad")),
                    L(lang, " — we replicated a public Tableau workbook as Shiny.",
                      " — öffentliches Tableau-Workbook bereits als Shiny nachgebaut."))
          ),
          tags$div(
            class = "p-3 bg-light rounded",
            h6(L(lang, "What you are seeing right now", "Was Sie gerade sehen")),
            tags$ol(class = "mb-0",
              tags$li(L(lang,
                        paste0("A Linux server (IONOS VPS) running ", code("nginx"), " + ", code("Shiny"), "."),
                        paste0("Linux-Server (IONOS VPS) mit ", code("nginx"), " + ", code("Shiny"), "."))),
              tags$li(L(lang,
                        "Each dashboard is an independent R app with its own URL.",
                        "Jedes Dashboard ist eine eigenständige R-App mit eigener URL.")),
              tags$li(L(lang,
                        "This page is itself a Shiny app — proof the stack works for storytelling.",
                        "Diese Seite ist selbst eine Shiny-App — der Stack eignet sich auch für Storytelling."))
            )
          )
        )
      )
    ),
    nav_panel(
      L(lang, "How users navigate", "Nutzer-Navigation"),
      layout_columns(
        col_widths = c(7, 5),
        card(
          card_header(L(lang, "Typical user journey (no R knowledge required)",
                        "Typische Nutzerreise (ohne R-Kenntnisse)")),
          div(class = "journey-step",
              strong("1. "), L(lang, "Open the hub", "Hub öffnen"),
              " — ", tags$code(HUB_URL)),
          div(class = "journey-step",
              strong("2. "), L(lang, "Choose a dashboard", "Dashboard wählen"),
              " — ", L(lang, "click ", "Klick auf "), em("Open dashboard"), "."),
          div(class = "journey-step",
              strong("3. "), L(lang, "Use sidebar controls", "Sidebar-Steuerung"),
              " — ", L(lang, "dropdowns, sliders update charts instantly.",
                       "Dropdowns, Slider aktualisieren Charts sofort.")),
          div(class = "journey-step",
              strong("4. "), L(lang, "Explore visuals", "Visuals erkunden"),
              " — ", L(lang, "hover for details; click to filter linked views.",
                       "Hover für Details; Klick filtert verknüpfte Ansichten.")),
          div(class = "journey-step",
              strong("5. "), L(lang, "Return to hub", "Zurück zum Hub"),
              " — ", em("← Back to hub"), " / ", L(lang, "Browser-Zurück.", "Browser-Zurück.")),
          tags$a(class = "btn btn-outline-primary btn-sm ms-2", href = HUB_URL,
                 L(lang, "Open hub in new tab", "Hub in neuem Tab"))
        ),
        card(
          card_header(L(lang, "Hub landing page (concept)", "Hub-Landingpage (Konzept)")),
          tags$div(class = "border rounded p-3 bg-white",
            p(class = "fw-semibold mb-2", "Dashboard Hub"),
            p(class = "small text-muted mb-3",
              L(lang, "Select a dashboard below.", "Dashboard unten auswählen.")),
            layout_column_wrap(
              width = 1/2,
              card(card_header("Example A"), p(class = "small", "KPIs + trends"),
                   tags$span(class = "btn btn-primary btn-sm", "Open")),
              card(card_header("Example B"), p(class = "small", "Maps + filters"),
                   tags$span(class = "btn btn-primary btn-sm", "Open"))
            )
          ),
          p(class = "small text-muted mt-2 mb-0",
            L(lang,
              paste0("On our server this is live — see the ", strong("Live catalog"), " tab."),
              paste0("Auf unserem Server live — Tab ", strong("Live-Katalog"), " öffnen.")))
        )
      )
    ),
    nav_panel(
      L(lang, "Solar inverter intake", "Solar-Wechselrichter Zugang"),
      layout_sidebar(
        sidebar = sidebar(
          width = 300,
          title = L(lang, "Month perspective", "Monatsperspektive"),
          selectInput(
            "month_sel", L(lang, "Registration month", "Registrierungsmonat"),
            choices = setNames(
              MONTH_CHOICES,
              vapply(MONTH_CHOICES, function(x) pretty_month(x, lang), character(1))
            ),
            selected = DEFAULT_MONTH
          ),
          sliderInput(
            "growth", L(lang, "Scenario uplift (%)", "Szenario-Aufschlag (%)"),
            min = -15, max = 30, value = 0, step = 5
          ),
          checkboxInput(
            "show_prior", L(lang, "Compare prior month", "Vormonat vergleichen"), TRUE
          ),
          hr(),
          p(class = "small text-muted mb-1",
            L(lang, "Simulated stream (~385k units, 2024–2025).",
              "Simulierter Datenstrom (~385k Einheiten, 2024–2025).")),
          tags$a(
            href = "https://github.com/OpenEnergyPlatform/open-MaStR",
            target = "_blank", rel = "noopener",
            class = "small d-block mb-1",
            "open-MaStR (GitHub) ↗"
          ),
          tags$a(
            href = "https://www.marktstammdatenregister.de/MaStR/Datendownload",
            target = "_blank", rel = "noopener",
            class = "small d-block",
            "BNetzA MaStR download ↗"
          )
        ),
        layout_column_wrap(
          width = 1/3,
          value_box(
            title = L(lang, "Units this month", "Einheiten diesen Monat"),
            value = textOutput("inv_kpi_units", inline = TRUE), theme = "primary"
          ),
          value_box(
            title = L(lang, "Capacity added (MW)", "Zubau Kapazität (MW)"),
            value = textOutput("inv_kpi_mw", inline = TRUE), theme = "warning"
          ),
          value_box(
            title = L(lang, "vs prior month", "vs. Vormonat"),
            value = textOutput("inv_kpi_delta", inline = TRUE), theme = "info"
          )
        ),
        card(
          card_header(textOutput("inv_chart_title", inline = TRUE)),
          plotlyOutput("inv_daily_plot", height = "340px")
        ),
        card(
          class = "mt-2",
          card_header(L(lang, "Why this matters for managers", "Warum das für Manager relevant ist")),
          p(class = "mb-0 small",
            L(lang,
              paste0("Germany's MaStR registry records every solar unit. Real bulk data is available via ",
                     strong("open-MaStR"), " (millions of rows). This tab simulates that scale so stakeholders ",
                     "can filter by ", strong("month"), ", compare periods, and stress-test KPI layouts ",
                     "before connecting production parquet/API feeds."),
              paste0("Deutschlands MaStR erfasst jede Solaranlage. Bulk-Daten über ",
                     strong("open-MaStR"), " (Millionen Zeilen). Dieser Tab simuliert dieses Volumen — ",
                     strong("Monatsfilter"), ", Periodenvergleich und KPI-Layouts vor Anbindung an Produktionsdaten.")))
        )
      )
    ),
    nav_panel(
      L(lang, "Delivery pipeline", "Delivery-Pipeline"),
      layout_columns(
        col_widths = c(5, 7),
        card(
          card_header(L(lang, "From client request to live dashboard",
                        "Von der Anfrage zum Live-Dashboard")),
          p(class = "small text-muted mb-3",
            L(lang, "Click a step to see what happens behind the scenes.",
              "Schritt anklicken — was im Hintergrund passiert.")),
          !!!lapply(PIPELINE, pipeline_step_ui, lang = lang)
        ),
        card(
          card_header(textOutput("pipe_title", inline = TRUE)),
          uiOutput("pipe_detail"),
          hr(),
          p(class = "small text-muted mb-0",
            strong(L(lang, "What the client sees at the end:", "Was der Kunde am Ende sieht:")), " ",
            L(lang,
              "a new card on the hub, a dedicated URL, and the same interactive experience as the demos.",
              "neue Hub-Karte, eigene URL, gleiche Interaktivität wie in den Demos."))
        )
      )
    ),
    nav_panel(
      L(lang, "Live catalog", "Live-Katalog"),
      p(class = "text-muted mb-3",
        L(lang,
          "Dashboards running on this server today — open any to validate interactivity.",
          "Heute auf diesem Server — beliebiges Dashboard öffnen und Interaktivität prüfen.")),
      layout_column_wrap(
        width = 1/3,
        gap = "1rem",
        !!!lapply(cat, catalog_card, lang = lang)
      )
    )
  )
}

ui <- page_fluid(
  title = "MyManager Demo",
  theme = mastr_theme("#1e3a5f"),
  tags$head(tags$script(HTML(
    "Shiny.addCustomMessageHandler('navigate', function(msg) { window.location.href = msg.url; });"
  ))),
  mastr_creator_qr_head(),
  mastr_creator_qr_styles(),
  tags$style(HTML("
    .mgr-hero { background: linear-gradient(135deg, #1e3a5f 0%, #2563eb 100%);
                color: #fff; border-radius: 12px; padding: 1.75rem 2rem; }
    .mgr-hero h1 { font-size: 1.75rem; font-weight: 600; }
    .pipeline-step { display: block; width: 100%; text-align: left;
      border: 2px solid #e5e7eb; border-radius: 10px; padding: 0.75rem 1rem;
      margin-bottom: 0.5rem; background: #fff; cursor: pointer; transition: all .15s; }
    .pipeline-step:hover { border-color: #2563eb; background: #f8fafc; }
    .pipeline-step.active { border-color: #2563eb; background: #eff6ff;
      box-shadow: 0 0 0 3px rgba(37,99,235,.15); }
    .pipeline-icon { font-size: 1.25rem; margin-right: 0.35rem; }
    .journey-step { border-left: 3px solid #2563eb; padding-left: 1rem; margin-bottom: 1rem; }
    .mgr-footer { font-size: 0.8rem; color: #6b7280; }
    .lang-switch .btn { min-width: 2.5rem; }
    .lang-switch .form-check-label { color: #fff; }
  ")),
  div(class = "container-fluid py-3",
    div(
      class = "mgr-hero mb-4",
      layout_columns(
        col_widths = c(7, 3, 2),
        div(
          h1(textOutput("hero_title", inline = TRUE)),
          p(class = "mb-2 opacity-90", textOutput("hero_sub", inline = TRUE)),
          tags$a(class = "btn btn-light btn-sm me-2", href = HUB_URL, target = "_self",
                 textOutput("hero_hub_btn", inline = TRUE)),
          tags$span(class = "small opacity-75",
                    textOutput("hero_date", inline = TRUE))
        ),
        div(
          class = "text-end",
          p(class = "small mb-1 opacity-75", textOutput("hero_kpi_label", inline = TRUE)),
          h3(textOutput("kpi_apps", inline = TRUE), class = "mb-0"),
          p(class = "small mb-0 opacity-75", textOutput("hero_kpi_sub", inline = TRUE))
        ),
        div(
          class = "text-end lang-switch",
          p(class = "small mb-1 opacity-75", "Language / Sprache"),
          radioButtons(
            "lang", NULL,
            choices = c("EN" = "en", "DE" = "de"),
            selected = "en",
            inline = TRUE
          )
        )
      )
    ),
    uiOutput("tabs_ui"),
    uiOutput("creator_qr"),
    hr(),
    p(class = "mgr-footer text-center mb-0",
      "MyManager demo · Shiny + RStudio Server · ",
      tags$a(href = HUB_URL, "Hub"), " · ",
      tags$a(href = "https://github.com/Tarekchehahde/shiny-dashboard-hub",
             target = "_blank", "Source repo"))
  )
)

`%||%` <- function(x, y) if (is.null(x)) y else x

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  lang <- reactive({
    if (identical(input$lang, "de")) "de" else "en"
  })

  active_step <- reactiveVal(1L)
  lapply(PIPELINE, function(s) {
    observeEvent(input[[paste0("pipe_step_", s$step)]], active_step(s$step), ignoreInit = TRUE)
  })

  output$hero_title <- renderText({
    L(lang(), "Interactive R Dashboard Platform", "Interaktive R-Dashboard-Plattform")
  })
  output$hero_sub <- renderText({
    L(lang(),
      "Proposal for company-hosted Shiny dashboards — one hub, many apps, browser-only for users.",
      "Vorschlag für firmeninterne Shiny-Dashboards — ein Hub, viele Apps, nur Browser für Nutzer.")
  })
  output$hero_hub_btn <- renderText({
    L(lang(), "Open dashboard hub", "Dashboard-Hub öffnen")
  })
  output$hero_date <- renderText({
    paste(L(lang(), "Presentation demo · ", "Präsentationsdemo · "),
          format(Sys.Date(), if (identical(lang(), "de")) "%d.%m.%Y" else "%d %b %Y"))
  })
  output$hero_kpi_label <- renderText({
    L(lang(), "This server today", "Dieser Server heute")
  })
  output$hero_kpi_sub <- renderText({
    L(lang(), "live dashboards + this pitch page", "Live-Dashboards + diese Pitch-Seite")
  })
  output$kpi_apps <- renderText(as.character(length(catalog_defs(lang())) + 1L))

  output$tabs_ui <- renderUI({
    build_tabs_ui(lang())
  })

  output$creator_qr <- renderUI({
    mastr_creator_qr_ui(lang())
  })

  month_data <- reactive({
    req(input$month_sel)
    g <- 1 + (input$growth %||% 0) / 100
    cur <- INVERTER_DAILY |> filter(year_month == input$month_sel) |>
      mutate(n_units = round(n_units * g), capacity_mw = capacity_mw * g)
    ym_idx <- match(input$month_sel, MONTH_CHOICES)
    prior_ym <- if (!is.na(ym_idx) && ym_idx < length(MONTH_CHOICES)) {
      MONTH_CHOICES[ym_idx + 1L]
    } else {
      NA_character_
    }
    prior <- if (!is.na(prior_ym)) {
      INVERTER_DAILY |> filter(year_month == prior_ym) |>
        summarise(units = sum(n_units), mw = sum(capacity_mw), .groups = "drop")
    } else {
      tibble(units = NA_real_, mw = NA_real_)
    }
    list(cur = cur, prior = prior, prior_ym = prior_ym, g = g)
  })

  output$inv_kpi_units <- renderText({
    format(sum(month_data()$cur$n_units), big.mark = ",", scientific = FALSE)
  })
  output$inv_kpi_mw <- renderText({
    sprintf("%.1f", sum(month_data()$cur$capacity_mw))
  })
  output$inv_kpi_delta <- renderText({
    cur_u <- sum(month_data()$cur$n_units)
    prior_u <- month_data()$prior$units
    if (is.na(prior_u) || prior_u == 0) return("—")
    pct <- (cur_u - prior_u) / prior_u * 100
    sprintf("%+.1f%%", pct)
  })

  output$inv_chart_title <- renderText({
    L(lang(),
      paste("Daily inverter registrations —", pretty_month(input$month_sel, "en")),
      paste("Tägliche WR-Registrierungen —", pretty_month(input$month_sel, "de")))
  })

  output$inv_daily_plot <- renderPlotly({
    md <- month_data()
    df <- md$cur
    req(nrow(df) > 0)
    p <- plot_ly(
      df, x = ~day, y = ~n_units, type = "bar",
      marker = list(color = "#f59e0b"),
      hovertemplate = paste0(
        L(lang(), "Day", "Tag"), ": %{x}<br>",
        L(lang(), "Units", "Einheiten"), ": %{y}<extra></extra>"
      )
    ) |>
      layout(
        xaxis = list(title = NULL, tickangle = -45),
        yaxis = list(title = L(lang(), "Units / day", "Einheiten / Tag")),
        margin = list(b = 80, t = 20),
        showlegend = FALSE
      )
    if (isTRUE(input$show_prior) && !is.na(md$prior_ym)) {
      prior_df <- INVERTER_DAILY |> filter(year_month == md$prior_ym)
      if (nrow(prior_df) > 0) {
        avg_prior <- mean(prior_df$n_units) * md$g
        p <- p |>
          add_trace(
            y = rep(avg_prior, nrow(df)), type = "scatter", mode = "lines",
            line = list(color = "#2563eb", dash = "dash"),
            name = L(lang(), "Prior month avg", "Vormonat Ø"),
            hoverinfo = "skip"
          )
      }
    }
    p |> config(displayModeBar = FALSE)
  })

  output$pipe_title <- renderText({
    s <- PIPELINE[[active_step()]]
    t <- s[[if (identical(lang(), "de")) "de" else "en"]]
    sprintf("%s %d — %s",
            L(lang(), "Step", "Schritt"), s$step, t$title)
  })

  output$pipe_detail <- renderUI({
    s <- PIPELINE[[active_step()]]
    t <- s[[if (identical(lang(), "de")) "de" else "en"]]
    tagList(
      p(t$detail),
      if (s$step == 5L) {
        tags$pre(class = "bg-light p-2 rounded small mb-0",
          "systemctl enable mastr-new-app\nnginx location /new_app/ → port 384x\nhub/app.R → new card")
      } else if (s$step == 6L) {
        tags$a(class = "btn btn-primary", href = HUB_URL,
               L(lang(), "Open the live hub →", "Live-Hub öffnen →"))
      }
    )
  })
}

shinyApp(ui, server)
