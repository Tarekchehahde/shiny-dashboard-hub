# =============================================================================
# ui_helpers.R — shared bslib UI pieces used by every dashboard
# =============================================================================

suppressPackageStartupMessages({
  library(bslib)
  library(shiny)
  library(htmltools)
  library(ggplot2)
})

# Transtek-friendly palette (can be overridden per app).
MASTR_PALETTE <- list(
  primary = "#0B5ED7",
  accent  = "#10b981",
  warn    = "#f59e0b",
  danger  = "#ef4444",
  solar   = "#F59E0B",
  wind    = "#0EA5E9",
  biomass = "#65A30D",
  water   = "#06B6D4",
  geo     = "#B45309",
  nuclear = "#A855F7",
  fossil  = "#6B7280",
  storage = "#111827"
)

mastr_theme <- function(primary = MASTR_PALETTE$primary) {
  bslib::bs_theme(
    version = 5,
    bootswatch = "flatly",
    primary = primary,
    base_font = bslib::font_google("Inter"),
    heading_font = bslib::font_google("Inter"),
    "font-size-base" = "0.95rem"
  )
}

.mastr_ui_env <- new.env(parent = emptyenv())

.mastr_www_dir <- function() {
  candidates <- character()
  ofile <- tryCatch(normalizePath(sys.frame(1)$ofile, winslash = "/", mustWork = FALSE), error = function(e) NULL)
  if (length(ofile) && nzchar(ofile)) {
    candidates <- c(candidates, file.path(dirname(ofile), "..", "www"))
  }
  candidates <- c(
    candidates,
    file.path("..", "..", "www"),
    file.path(getwd(), "..", "..", "www"),
    "/opt/mastr-shiny/WORK/shiny/www"
  )
  for (d in unique(candidates)) {
    p <- file.path(d, "linkedin-qr-tarek-chehade.png")
    if (file.exists(p)) {
      return(normalizePath(d, winslash = "/", mustWork = FALSE))
    }
  }
  NULL
}

mastr_register_assets <- function() {
  if (isTRUE(.mastr_ui_env$assets_registered)) {
    return(invisible(NULL))
  }
  www <- .mastr_www_dir()
  if (!is.null(www)) {
    shiny::addResourcePath("mastr-assets", www)
    .mastr_ui_env$assets_registered <- TRUE
  }
  invisible(NULL)
}

mastr_creator_qr_src <- function() {
  www <- .mastr_www_dir()
  if (is.null(www)) {
    return(NULL)
  }
  "mastr-assets/linkedin-qr-tarek-chehade.png"
}

#' LinkedIn QR dock — slides away after 5s; reopen via edge tab.
#'
#' @param lang `"de"` or `"en"` for caption text.
mastr_creator_qr_styles <- function() {
  tags$style(HTML("
    .mastr-creator-qr-wrap {
      position: fixed; right: 0; bottom: 14px; z-index: 1040;
      display: flex; flex-direction: row; align-items: stretch;
      max-width: 100vw; pointer-events: none;
    }
    .mastr-creator-qr-wrap > * { pointer-events: auto; }
    .mastr-creator-qr {
      display: flex; align-items: center; gap: 10px;
      background: #fff; border: 1px solid #e5e7eb;
      border-radius: 10px 0 0 10px; border-right: none;
      padding: 8px 4px 8px 12px;
      box-shadow: 0 4px 18px rgba(15,23,42,.12);
      max-width: min(320px, calc(100vw - 52px));
      transition: transform 0.4s cubic-bezier(.4,0,.2,1), opacity 0.3s ease;
    }
    .mastr-creator-qr-wrap.is-collapsed .mastr-creator-qr {
      transform: translateX(100%);
      opacity: 0;
      pointer-events: none;
    }
    .mastr-creator-qr img { border-radius: 6px; flex-shrink: 0; object-fit: contain; }
    .mastr-creator-qr-text {
      display: flex; flex-direction: column; gap: 2px;
      font-size: 0.72rem; line-height: 1.25; color: #475569;
    }
    .mastr-creator-qr-text strong { font-size: 0.78rem; color: #0f172a; }
    .mastr-creator-qr-tab {
      flex-shrink: 0; align-self: center;
      border: 1px solid #e5e7eb; background: #fff;
      border-radius: 10px 0 0 10px;
      padding: 14px 7px; cursor: pointer;
      box-shadow: -2px 2px 12px rgba(15,23,42,.12);
      line-height: 1; color: #334155; font-size: 1.15rem;
    }
    .mastr-creator-qr-tab:hover { background: #f8fafc; color: #0f172a; }
    .mastr-creator-qr-tab:focus-visible {
      outline: 2px solid #2563eb; outline-offset: 2px;
    }
    .mastr-creator-qr-wrap:not(.is-collapsed) .mastr-creator-qr-tab {
      border-radius: 0; border-left: none; padding: 14px 5px;
      box-shadow: none;
    }
    @media (max-width: 767.98px) {
      .mastr-creator-qr-wrap { bottom: 8px; }
      .mastr-creator-qr { padding: 6px 4px 6px 8px; }
      .mastr-creator-qr img { width: 72px !important; height: 72px !important; }
      .mastr-creator-qr-wrap.is-collapsed .mastr-creator-qr-text,
      .mastr-creator-qr-text { display: none !important; }
    }
  "))
}

mastr_creator_qr_head <- function() {
  tags$head(tags$script(HTML("
    (function() {
      var AUTO_MS = 5000;
      function setQrCollapsed(wrap, collapsed) {
        wrap.classList.toggle('is-collapsed', collapsed);
        var tab = wrap.querySelector('.mastr-creator-qr-tab');
        var icon = wrap.querySelector('.mastr-creator-qr-tab-icon');
        if (tab) tab.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
        if (icon) icon.textContent = collapsed ? '\\u2039' : '\\u203A';
      }
      function attachQrDock(wrap) {
        if (!wrap || wrap.dataset.mastrQrInit) return;
        wrap.dataset.mastrQrInit = '1';
        var tab = wrap.querySelector('.mastr-creator-qr-tab');
        if (!tab) return;
        var autoTimer;
        function scheduleCollapse() {
          clearTimeout(autoTimer);
          autoTimer = setTimeout(function() { setQrCollapsed(wrap, true); }, AUTO_MS);
        }
        tab.addEventListener('click', function() {
          var collapsed = wrap.classList.contains('is-collapsed');
          setQrCollapsed(wrap, !collapsed);
          if (wrap.classList.contains('is-collapsed')) {
            clearTimeout(autoTimer);
          } else {
            scheduleCollapse();
          }
        });
        setQrCollapsed(wrap, false);
        scheduleCollapse();
      }
      function scanQrDocks() {
        document.querySelectorAll('.mastr-creator-qr-wrap').forEach(attachQrDock);
      }
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', scanQrDocks);
      } else {
        scanQrDocks();
      }
      if (window.jQuery) {
        jQuery(document).on('shiny:connected', function() {
          setTimeout(scanQrDocks, 50);
        });
      }
      if (window.MutationObserver) {
        var mo = new MutationObserver(function() { scanQrDocks(); });
        document.addEventListener('DOMContentLoaded', function() {
          mo.observe(document.body, { childList: true, subtree: true });
        });
        if (document.body) mo.observe(document.body, { childList: true, subtree: true });
      }
    })();
  ")))
}

mastr_creator_qr_ui <- function(lang = "en") {
  mastr_register_assets()
  src <- mastr_creator_qr_src()
  if (is.null(src)) {
    return(NULL)
  }
  is_de <- identical(lang, "de")
  tab_label <- if (is_de) "LinkedIn QR ein-/ausblenden" else "Show or hide LinkedIn QR"
  linkedin_url <- "https://www.linkedin.com/in/tarek-shehadi/"
  div(
    class = "mastr-creator-qr-wrap",
    div(
      class = "mastr-creator-qr",
      tags$a(
        href = linkedin_url,
        target = "_blank",
        rel = "noopener",
        tags$img(
          src = src,
          alt = if (is_de) "LinkedIn QR-Code Tarek Chehade" else "LinkedIn QR code Tarek Chehade",
          width = "96", height = "96",
          style = "object-fit: contain; display: block;"
        )
      ),
      div(
        class = "mastr-creator-qr-text",
        tags$strong("Tarek Chehade (Ing.)"),
        tags$span(
          if (is_de) {
            "Dashboard-Idee \u00b7 QR scannen \u2192 LinkedIn"
          } else {
            "Dashboard creator \u00b7 Scan to connect on LinkedIn"
          }
        )
      )
    ),
    tags$button(
      type = "button",
      class = "mastr-creator-qr-tab",
      `aria-expanded` = "true",
      `aria-label` = tab_label,
      tags$span(class = "mastr-creator-qr-tab-icon", "\u203A")
    )
  )
}

#' Hub URL for nginx path mode (production) or localhost ports (local dev).
mastr_hub_url <- function() {
  if (identical(Sys.getenv("MASTR_HUB_MODE", "paths"), "ports")) {
    "http://localhost:3838/"
  } else {
    "/"
  }
}

#' JS handler injected once per dashboard UI (via [mastr_page()]).
mastr_hub_nav_head <- function() {
  tags$head(tags$script(HTML(
    "Shiny.addCustomMessageHandler('mastrHubNavigate', function(msg) {
      if (msg && msg.url) window.location.href = msg.url;
    });"
  )))
}

#' Standard back-to-hub control — id is always `hub_back` for [mastr_hub_back_server()].
mastr_hub_back_link <- function(label = "\u2190 Back to hub") {
  actionLink("hub_back", label, class = "small text-decoration-none")
}

#' Wire `input$hub_back` to the hub landing page. Call once at top of server().
mastr_hub_back_server <- function(session) {
  observeEvent(session$input$hub_back, {
    if (identical(Sys.getenv("MASTR_HUB_MODE", "paths"), "ports")) {
      shiny::stopApp()
    } else {
      session$sendCustomMessage("mastrHubNavigate", list(url = mastr_hub_url()))
    }
  }, ignoreInit = TRUE)
}

#' Responsive layout CSS for phones and tablets (included in [mastr_page()]).
mastr_responsive_css <- function() {
  tags$style(HTML("
    /* Allow vertical scroll on tablets — page_fillable can clip content. */
    @media (max-width: 991.98px) {
      html, body { overflow-y: auto !important; }
      .html-fill-container, .html-fill-item { min-height: 0 !important; }
      .bslib-sidebar-layout > .main { min-width: 0; overflow-x: hidden; }
      .bslib-sidebar-layout > .sidebar { max-width: 100%; }
      h2.mb-0 { font-size: clamp(1.1rem, 4.5vw, 1.5rem); line-height: 1.25; }
      .text-muted.mb-0, .text-muted.mb-0 p { font-size: 0.88rem; line-height: 1.35; }
      .value-box { min-height: 96px !important; }
      .value-box .value-box-value { font-size: 1.35rem !important; }
      .value-box .value-box-title { white-space: normal !important; }
      .bslib-grid.grid > .bslib-grid-item { min-width: 0; }
      .kreis-map, .leaflet, .leaflet-container {
        min-height: min(52vh, 420px) !important;
        height: min(52vh, 420px) !important;
      }
      .plot-output img, .shiny-plot-output { max-width: 100%; height: auto !important; }
      .plotly, .js-plotly-plot { max-width: 100% !important; }
      .ReactTable { font-size: 0.82rem; }
      .erwicon-banner { font-size: 0.82rem; padding: 0.5rem 0.75rem; }
      .container-fluid { padding-left: 0.75rem; padding-right: 0.75rem; }
    }
  @media (max-width: 767.98px) {
      /* Stack KPI / chart columns on phones */
      .bslib-grid.grid {
        grid-template-columns: 1fr !important;
      }
      .bslib-grid.grid > .bslib-grid-item {
        grid-column: 1 / -1 !important;
      }
      .value-box .value-box-value { font-size: 1.2rem !important; }
      .card-body .plot-output, .card-body .shiny-plot-output,
      .card-body .leaflet, .card-body .reactable {
        min-height: 240px;
      }
      .btn, .action-button { min-height: 2.5rem; }
    }
    @media (max-width: 575.98px) {
      .py-2 { padding-top: 0.35rem !important; padding-bottom: 0.35rem !important; }
      .card-header { font-size: 0.85rem; }
    }
  "))
}

#' Page wrapper used by every dashboard.
#'
#' @param fluid If TRUE, the page scrolls vertically instead of fitting to the
#'   viewport (bslib::page_fluid). Use this for apps that include tables, maps
#'   or stacked cards that would otherwise get clipped by page_fillable's
#'   equal-height layout. Aggregate-only "at-a-glance" dashboards (01 Overview)
#'   keep the default `fluid = FALSE` for a single-screen feel.
#' @param footer Footer preset passed to [mastr_footer()]. Use `"mastr"` only for
#'   MaStR-backed dashboards (`most_visited` and related apps). Other hub apps
#'   should set an app-specific preset so the BNetzA line does not appear.
#' @param hub_back If TRUE, show a back-to-hub link in the page header (requires
#'   [mastr_hub_back_server()] in the server function).
#' @param creator_qr If TRUE, show a fixed LinkedIn QR badge (bottom-right).
#' @param creator_qr_lang `"de"` or `"en"` for QR caption text.
mastr_page <- function(title, subtitle = NULL, ...,
                       primary = MASTR_PALETTE$primary,
                       fluid = FALSE,
                       footer = "mastr",
                       hub_back = TRUE,
                       hub_back_label = "\u2190 Back to hub",
                       creator_qr = TRUE,
                       creator_qr_lang = "en") {
  page_fn <- if (isTRUE(fluid)) bslib::page_fluid else bslib::page_fillable
  page_fn(
    title = title,
    theme = mastr_theme(primary),
    if (isTRUE(hub_back)) mastr_hub_nav_head(),
    if (isTRUE(creator_qr)) mastr_creator_qr_head(),
    mastr_responsive_css(),
    if (isTRUE(creator_qr)) mastr_creator_qr_styles(),
    tags$style(HTML("
      .mastr-footer { font-size: 0.75rem; color: #6b7280; padding: 0.5rem 0; }
      .mastr-kpi { font-variant-numeric: tabular-nums; }
      /* KPI value boxes — reserve room for 3 lines and truncate overflow. */
      .value-box { min-height: 130px; }
      .value-box .value-box-title { font-size: 0.85rem; opacity: 0.9;
                                    white-space: nowrap; overflow: hidden;
                                    text-overflow: ellipsis; }
      .value-box .value-box-value { font-size: 1.75rem; line-height: 1.1;
                                    white-space: nowrap; overflow: hidden;
                                    text-overflow: ellipsis; }
      .value-box h3 { font-variant-numeric: tabular-nums; }
      /* Cards: a little more breathing room around headers and bodies. */
      .card-header { font-weight: 500; font-size: 0.92rem;
                     padding: 0.55rem 0.85rem; }
      .card-body { padding: 0.55rem 0.85rem; }
      /* Sidebar: the default slider tick labels frequently collide in a
         260-290px sidebar. Make them a touch smaller and allow wrapping. */
      .irs .irs-grid-text { font-size: 9px; }
      .irs .irs-min, .irs .irs-max, .irs .irs-from, .irs .irs-to,
      .irs .irs-single { font-size: 10px; padding: 1px 4px; }
      .bslib-sidebar-layout > .sidebar { padding-right: 0.5rem; }
      /* Plotly: neutralise the modeBar hover tint that can overlap chart
         titles, and give the legend a little top margin. */
      .plotly .modebar { background: transparent !important;
                         opacity: 0.35; transition: opacity 0.2s; }
      .plotly:hover .modebar { opacity: 1; }
      .plotly .legend { margin-top: 6px; }
      /* reactable: tighten the row striping and make headers look like
         the rest of the Inter typography. */
      .ReactTable .rt-thead .rt-th { font-weight: 600; font-size: 0.85rem; }
      .ReactTable .rt-tbody .rt-td { font-variant-numeric: tabular-nums; }
    ")),
    div(
      class = "py-2",
      div(
        class = "d-flex flex-wrap justify-content-between align-items-start gap-2",
        div(
          h2(title, class = "mb-0"),
          if (!is.null(subtitle)) {
            if (inherits(subtitle, "shiny.tag") || inherits(subtitle, "shiny.tag.list") ||
                inherits(subtitle, "html")) {
              div(subtitle, class = "text-muted mb-0")
            } else {
              p(subtitle, class = "text-muted mb-0")
            }
          }
        ),
        if (isTRUE(hub_back)) div(class = "pt-1", mastr_hub_back_link(hub_back_label))
      )
    ),
    ...,
    if (isTRUE(creator_qr)) mastr_creator_qr_ui(creator_qr_lang),
    mastr_footer(footer)
  )
}

mastr_footer <- function(footer = "mastr") {
  body <- switch(
    footer,
    mastr = {
      if (!exists("mastr_attribution", mode = "function")) {
        stop("footer = \"mastr\" requires source(\"../../R/mastr_data.R\") in the app.", call. = FALSE)
      }
      tagList(
        HTML(mastr_attribution()),
        " · ",
        tags$a(
          href = "https://www.marktstammdatenregister.de/MaStR/Datendownload",
          target = "_blank", "BNetzA MaStR"
        )
      )
    },
    lebanese_elections = tagList(
      "Data: Lebanese parliamentary election statistics (26 electoral casas) — ",
      "Tableau workbook by Tarek Chehade / Gherbal Initiative (2022). ",
      tags$a(
        href = "https://public.tableau.com/app/profile/tarek.chehade/viz/lebanese-elections/Dashboard1",
        target = "_blank", rel = "noopener", "Source viz"
      )
    ),
    gapminder = tagList(
      "Data: Gapminder / Jennifer Bryan teaching dataset (bundled CSV). ",
      tags$a(href = "https://www.gapminder.org/data/", target = "_blank", "Gapminder")
    ),
    demo = "Demo data only — not for operational decisions.",
    thueringen_demo = "erwicon connect 2026 \u00b7 Illustrative Demo-Daten \u2014 nicht f\u00fcr operative Entscheidungen.",
    pitch = "MyManager pitch demo · illustrative metrics only.",
    solar_radiation = tagList(
      "Data: Open-Meteo Forecast API (shortwave_radiation / GHI) — ",
      "DWD & satellite models. ",
      tags$a(href = "https://open-meteo.com/en/docs", target = "_blank", "Open-Meteo")
    ),
    thueringen_gewerbe = tagList(
      "erwicon connect 2026 \u00b7 Strompreis Energy-Charts + MaStR Gewerbe/Industrie Th\u00fcringen. ",
      if (!exists("mastr_attribution", mode = "function")) {
        "MaStR via BNetzA."
      } else {
        HTML(mastr_attribution())
      }
    ),
    thueringen = tagList(
      "erwicon connect 2026 \u00b7 Th\u00fcringen Kreis-Ranking \u00fcber PLZ (GeoNames). ",
      "Einwohner: Destatis-Sch\u00e4tzung. ",
      if (!exists("mastr_attribution", mode = "function")) {
        "MaStR via BNetzA."
      } else {
        HTML(mastr_attribution())
      }
    ),
    thueringen_fachkraefte = tagList(
      "erwicon connect 2026 \u00b7 Gemeldete Arbeitsstellen (STEA) & Besch\u00e4ftigung (BST), ",
      "Statistik der Bundesagentur f\u00fcr Arbeit, monatlich. ",
      tags$a(
        href = "https://statistik.arbeitsagentur.de/DE/Navigation/Service/API/API-Start-Nav.html",
        target = "_blank", rel = "noopener", "BA Statistik-API"
      )
    ),
    eu_electricity = tagList(
      "Data: Fraunhofer ISE Energy-Charts API (day-ahead prices). ",
      tags$a(href = "https://energy-charts.info/", target = "_blank", "Energy-Charts")
    ),
    hub = "Dashboard hub — select an app above.",
    minimal = NULL,
    stop("Unknown mastr_footer preset: ", footer, call. = FALSE)
  )
  if (is.null(body)) {
    return(NULL)
  }
  div(
    class = "mastr-footer text-center border-top mt-3 pt-2",
    body,
    " · ",
    tags$a(href = "https://github.com/Tarekchehahde/shiny-dashboard-hub", target = "_blank", "Source")
  )
}

# Shorthand value_box with tabular-numeric formatting.
#
# A fixed min_height is required because page_fillable() otherwise collapses
# the KPI row when the plots below request more height, which clips the title
# and caption lines inside the value box.
mastr_kpi <- function(title, value, subtitle = NULL,
                      color = "primary", icon = NULL,
                      min_height = "130px") {
  bslib::value_box(
    title = title,
    value = span(class = "mastr-kpi", value),
    subtitle,
    theme = color,
    showcase = icon,
    min_height = min_height,
    fill = FALSE
  )
}

# Format helpers
fmt_num <- function(x, digits = 0, suffix = "") {
  if (is.null(x) || length(x) == 0 || is.na(x)) return("–")
  paste0(formatC(x, big.mark = ".", decimal.mark = ",", format = "f", digits = digits),
         suffix)
}

fmt_mw <- function(kw) fmt_num(kw / 1000, 1, " MW")
fmt_gw <- function(kw) fmt_num(kw / 1e6, 2, " GW")

#' Empty ggplot with a centered message (loading / no data).
mastr_empty_plot <- function(message = "Keine Daten") {
  ggplot() +
    annotate("text", x = 0.5, y = 0.5, label = message) +
    coord_cartesian(xlim = c(0, 1), ylim = c(0, 1), expand = FALSE) +
    theme_void()
}
