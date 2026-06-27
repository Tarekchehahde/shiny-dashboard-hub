# =============================================================================
# lebanese_elections — R-native Shiny replica of Tarek Chehade's Tableau workbook.
# ggplot2 + ggforce circle packs, Leaflet map, plotly treemap.
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(ggplot2)
  library(ggforce)
  library(scales)
  library(leaflet)
  library(htmltools)
  library(plotly)
})

source("../../R/ui_helpers.R")

DATA_PATH <- file.path("data", "elections-data.csv")
GEO_PATH <- file.path("data", "casa_centroids.csv")

ELEC <- read.csv(DATA_PATH, stringsAsFactors = FALSE, check.names = FALSE) |>
  transmute(
    casa = `Electoral Area`,
    local_votes = as.integer(`Local votes`),
    expat_votes = as.integer(`Expat votes`),
    candidates = as.integer(Candidates)
  )

GEO <- read.csv(GEO_PATH, stringsAsFactors = FALSE)

ELEC <- ELEC |>
  left_join(GEO, by = "casa") |>
  mutate(casa = factor(casa, levels = ELEC$casa))

CASA_LEVELS <- levels(ELEC$casa)
LOCAL_RANGE <- range(ELEC$local_votes, na.rm = TRUE)
CAND_RANGE <- c(1L, 11L)

pal_local <- colorRampPalette(c("#e8f5e9", "#1b5e20"))(100)
pal_cand  <- colorRampPalette(c("#fce4ec", "#b71c1c"))(100)
pal_tree  <- colorRampPalette(c("#e0f7fa", "#006064"))(100)

scale_idx <- function(x, rng) {
  p <- (x - rng[1]) / diff(rng)
  p <- pmax(0, pmin(1, p))
  pmax(1L, pmin(100L, as.integer(p * 99 + 1)))
}

circle_pack_data <- function(df, size_col, color_col, palette, rng, selected = NULL) {
  areas <- data.frame(id = df$casa, area = pmax(as.numeric(df[[size_col]]), 1))
  lay <- if (requireNamespace("packcircles", quietly = TRUE)) {
    packcircles::circleLayout(areas$area)$layout
  } else {
    n <- nrow(areas)
    theta <- seq(0, 6 * pi, length.out = n)
    r <- sqrt(areas$area / max(areas$area)) * 15
    data.frame(x = r * cos(theta), y = r * sin(theta), radius = r * 0.35)
  }
  lay$id <- areas$id

  pad <- max(lay$radius) * 1.1
  lay$x <- (lay$x - min(lay$x) + pad) / (max(lay$x) - min(lay$x) + 2 * pad)
  lay$y <- (lay$y - min(lay$y) + pad) / (max(lay$y) - min(lay$y) + 2 * pad)
  max_r <- max(lay$radius)
  span <- min(diff(range(lay$x)), diff(range(lay$y)))
  lay$radius <- lay$radius / max_r * (span * 0.22)

  sel_chr <- if (is.null(selected) || !nzchar(selected)) NA_character_ else as.character(selected)

  df |>
    left_join(lay, by = c("casa" = "id")) |>
    mutate(
      fill = palette[scale_idx(.data[[color_col]], rng)],
      label = as.character(casa),
      selected = !is.na(sel_chr) & casa == sel_chr,
      stroke = if_else(selected, "#111827", "#ffffff"),
      stroke_w = if_else(selected, 1.2, 0.35)
    )
}

draw_circle_pack <- function(d, title) {
  ggplot(d, aes(x = x, y = y)) +
    ggforce::geom_circle(
      aes(x0 = x, y0 = y, r = radius, fill = fill, colour = stroke, linewidth = stroke_w),
      alpha = 0.92
    ) +
    geom_text(aes(label = label), size = 2.6, lineheight = 0.85, fontface = "bold") +
    scale_fill_identity() +
    scale_colour_identity() +
    scale_linewidth_identity() +
    coord_equal(expand = FALSE) +
    labs(title = title) +
    theme_void(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", hjust = 0, size = 13, margin = margin(b = 6)),
      plot.margin = margin(8, 8, 8, 8)
    )
}

pick_casa_from_click <- function(click, d) {
  if (is.null(click)) {
    return(NULL)
  }
  px <- click$x
  py <- click$y
  inside <- which(sqrt((d$x - px)^2 + (d$y - py)^2) <= d$radius * 1.05)
  if (length(inside) == 0) {
    dist <- sqrt((d$x - px)^2 + (d$y - py)^2) - d$radius
    inside <- which.min(dist)
    if (dist[inside] > 0.06) {
      return(NULL)
    }
    inside <- inside[1]
  } else {
    inside <- inside[which.max(d$radius[inside])]
  }
  as.character(d$casa[inside])
}

legend_bar <- function(title, low, high, palette) {
  grad <- paste0("linear-gradient(90deg, ", palette[1], " 0%, ", palette[100], " 100%)")
  tags$div(
    class = "mb-2",
    tags$div(class = "small fw-semibold mb-1", title),
    tags$div(
      style = paste0("height:14px;border-radius:3px;background:", grad, ";"),
      `aria-hidden` = "true"
    ),
    tags$div(
      class = "d-flex justify-content-between small text-muted mt-1",
      tags$span(format(low, big.mark = ",")),
      tags$span(format(high, big.mark = ","))
    )
  )
}

ui <- mastr_page(
  title = "Lebanese Elections",
  subtitle = paste(
    "2022 parliamentary data by electoral casa — circle packs, map, and treemap.",
    "Click any view to link filters across panels."
  ),
  fluid = TRUE,
  primary = "#006064",
  footer = "lebanese_elections",
  tags$style(HTML("
    .lebanon-map { border-radius: 8px; overflow: hidden; }
    .le-casa-table td, .le-casa-table th { font-size: 0.85rem; }
  ")),
  layout_sidebar(
    sidebar = sidebar(
      width = 300,
      title = "Explore",
      selectInput(
        "casa", "Electoral area (casa)",
        choices = c("All areas" = "", CASA_LEVELS),
        selected = ""
      ),
      selectInput(
        "map_metric", "Map colour & size",
        choices = c(
          "Local votes" = "local_votes",
          "Candidates" = "candidates",
          "Expat votes" = "expat_votes"
        ),
        selected = "local_votes"
      ),
      actionButton("reset_sel", "Clear selection", class = "btn-sm btn-outline-secondary w-100"),
      hr(),
      uiOutput("detail_box"),
      hr(),
      uiOutput("kpi_row"),
      hr(),
      p(class = "small text-muted mb-1",
        "Tip: click bubbles, map markers, or treemap tiles to filter all views."),
      tags$a(
        href = "https://public.tableau.com/app/profile/tarek.chehade/viz/lebanese-elections/Dashboard1",
        target = "_blank", rel = "noopener", class = "small d-block mb-2",
        "Original Tableau Public viz"
      )
    ),
    layout_columns(
      col_widths = c(5, 7),
      layout_columns(
        col_widths = c(12, 12),
        card(
          card_header("Density of local votes"),
          card_body(padding = 0, plotOutput("plot_local", height = "320px", click = "plot_local_click"))
        ),
        card(
          card_header("Density of candidates"),
          card_body(padding = 0, plotOutput("plot_candidates", height = "320px", click = "plot_candidates_click"))
        )
      ),
      layout_columns(
        col_widths = c(12, 12),
        card(
          card_header("Lebanon map — casas"),
          card_body(
            padding = 0,
            div(class = "lebanon-map", leafletOutput("map_lebanon", height = "320px"))
          )
        ),
        card(
          card_body(
            padding = "0.75rem",
            layout_columns(
              col_widths = c(8, 4),
              plotlyOutput("plot_treemap", height = "320px"),
              tags$div(
                class = "pt-2",
                legend_bar("Candidates", CAND_RANGE[1], CAND_RANGE[2], pal_cand),
                legend_bar("Local votes", LOCAL_RANGE[1], LOCAL_RANGE[2], pal_local),
                hr(),
                p(class = "small text-muted mb-0",
                  "Treemap area = local voters; colour = local voters (Tableau parity).")
              )
            )
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  selected <- reactiveVal(NULL)

  observeEvent(input$casa, {
    sel <- input$casa
    selected(if (nzchar(sel)) sel else NULL)
  }, ignoreInit = TRUE)

  observeEvent(input$reset_sel, {
    selected(NULL)
    updateSelectInput(session, "casa", selected = "")
  })

  observeEvent(input$plot_local_click, {
    d <- circle_pack_data(ELEC, "local_votes", "local_votes", pal_local, LOCAL_RANGE, selected())
    selected(pick_casa_from_click(input$plot_local_click, d))
  })
  observeEvent(input$plot_candidates_click, {
    d <- circle_pack_data(ELEC, "candidates", "candidates", pal_cand, CAND_RANGE, selected())
    selected(pick_casa_from_click(input$plot_candidates_click, d))
  })
  observeEvent(input$map_marker_click, {
    selected(input$map_marker_click$id)
  })
  observeEvent(event_data("plotly_click", source = "Casa Details"), {
    click <- event_data("plotly_click", source = "Casa Details")
    if (!is.null(click)) {
      selected(as.character(click$customdata))
    }
  })

  observeEvent(selected(), {
    sel <- selected()
    updateSelectInput(session, "casa", selected = if (is.null(sel)) "" else sel)
  }, ignoreInit = TRUE)

  output$detail_box <- renderUI({
    sel <- selected()
    if (is.null(sel) || !nzchar(sel)) {
      return(tags$p(class = "text-muted small", "Select a casa to see details."))
    }
    row <- ELEC |> filter(casa == sel)
    if (nrow(row) == 0) {
      return(NULL)
    }
    tagList(
      h6(sel, class = "mb-2"),
      tags$table(
        class = "table table-sm table-borderless mb-0 le-casa-table",
        tags$tr(tags$td("Local votes"), tags$td(class = "text-end fw-semibold", format(row$local_votes, big.mark = ","))),
        tags$tr(tags$td("Expat votes"), tags$td(class = "text-end fw-semibold", format(row$expat_votes, big.mark = ","))),
        tags$tr(tags$td("Candidates"), tags$td(class = "text-end fw-semibold", row$candidates)),
        tags$tr(tags$td("Total registered"), tags$td(class = "text-end fw-semibold",
          format(row$local_votes + row$expat_votes, big.mark = ",")))
      )
    )
  })

  output$kpi_row <- renderUI({
    df <- ELEC
    sel <- selected()
    if (!is.null(sel) && nzchar(sel)) {
      df <- df |> filter(casa == sel)
    }
    tagList(
      p(class = "small text-muted mb-1", if (is.null(sel) || !nzchar(sel)) "All casas" else paste("Selected:", sel)),
      tags$table(
        class = "table table-sm le-casa-table mb-0",
        tags$tr(tags$td("Casas"), tags$td(class = "text-end", nrow(df))),
        tags$tr(tags$td("Local votes"), tags$td(class = "text-end", format(sum(df$local_votes), big.mark = ","))),
        tags$tr(tags$td("Candidates"), tags$td(class = "text-end", sum(df$candidates)))
      )
    )
  })

  output$plot_local <- renderPlot({
    d <- circle_pack_data(ELEC, "local_votes", "local_votes", pal_local, LOCAL_RANGE, selected())
    print(draw_circle_pack(d, "Density of local votes"))
  }, res = 120)

  output$plot_candidates <- renderPlot({
    d <- circle_pack_data(ELEC, "candidates", "candidates", pal_cand, CAND_RANGE, selected())
    print(draw_circle_pack(d, "Density of candidates"))
  }, res = 120)

  map_palette <- reactive({
    metric <- input$map_metric
    rng <- switch(metric,
      local_votes = LOCAL_RANGE,
      candidates = CAND_RANGE,
      expat_votes = range(ELEC$expat_votes, na.rm = TRUE)
    )
    pal <- switch(metric,
      local_votes = pal_local,
      candidates = pal_cand,
      expat_votes = colorRampPalette(c("#fff3e0", "#e65100"))(100)
    )
    list(metric = metric, rng = rng, pal = pal)
  })

  output$map_lebanon <- renderLeaflet({
    mp <- map_palette()
    sel_chr <- selected()
    sel_chr <- if (is.null(sel_chr) || !nzchar(sel_chr)) NA_character_ else as.character(sel_chr)
    d <- ELEC |>
      mutate(
        metric_val = .data[[mp$metric]],
        fill = mp$pal[scale_idx(metric_val, mp$rng)],
        rad = rescale(sqrt(metric_val), to = c(6, 22)),
        highlight = !is.na(sel_chr) & casa == sel_chr,
        mk_weight = if_else(highlight, 3, 1),
        mk_color = if_else(highlight, "#111827", "#ffffff")
      )

    leaflet(d, options = leafletOptions(minZoom = 7, maxZoom = 11)) |>
      addProviderTiles(providers$CartoDB.Positron) |>
      setView(lng = 35.9, lat = 33.9, zoom = 8) |>
      addCircleMarkers(
        lng = ~lon, lat = ~lat,
        radius = ~rad,
        stroke = TRUE,
        weight = ~mk_weight,
        color = ~mk_color,
        fillColor = ~fill,
        fillOpacity = 0.85,
        opacity = 1,
        label = ~paste0(
          casa, "\nLocal: ", format(local_votes, big.mark = ","),
          " · Candidates: ", candidates
        ),
        layerId = ~casa
      )
  })

  observe({
    mp <- map_palette()
    sel_chr <- selected()
    sel_chr <- if (is.null(sel_chr) || !nzchar(sel_chr)) NA_character_ else as.character(sel_chr)
    d <- ELEC |>
      mutate(
        metric_val = .data[[mp$metric]],
        fill = mp$pal[scale_idx(metric_val, mp$rng)],
        rad = rescale(sqrt(metric_val), to = c(6, 22)),
        highlight = !is.na(sel_chr) & casa == sel_chr,
        mk_weight = if_else(highlight, 3, 1),
        mk_color = if_else(highlight, "#111827", "#ffffff")
      )
    leafletProxy("map_lebanon", data = d) |>
      clearMarkers() |>
      addCircleMarkers(
        lng = ~lon, lat = ~lat,
        radius = ~rad,
        stroke = TRUE,
        weight = ~mk_weight,
        color = ~mk_color,
        fillColor = ~fill,
        fillOpacity = 0.85,
        label = ~paste0(
          casa, "\nLocal: ", format(local_votes, big.mark = ","),
          " · Candidates: ", candidates
        ),
        layerId = ~casa
      )
  })

  output$plot_treemap <- renderPlotly({
    sel_chr <- selected()
    sel_chr <- if (is.null(sel_chr) || !nzchar(sel_chr)) NA_character_ else as.character(sel_chr)
    d <- ELEC |>
      mutate(
        fill = pal_tree[scale_idx(local_votes, LOCAL_RANGE)],
        line = ifelse(!is.na(sel_chr) & casa == sel_chr, "#111827", "#ffffff")
      )

    plot_ly(
      d,
      type = "treemap",
      labels = ~casa,
      parents = "",
      values = ~local_votes,
      marker = list(colors = ~fill, line = list(color = ~line, width = 2)),
      customdata = ~casa,
      source = "Casa Details",
      hovertemplate = ~paste0(
        "<b>", casa, "</b><br>",
        "Local votes: ", format(local_votes, big.mark = ","), "<br>",
        "Expat votes: ", format(expat_votes, big.mark = ","), "<br>",
        "Candidates: ", candidates, "<extra></extra>"
      )
    ) |>
      layout(
        title = list(text = "Casa Details", x = 0, font = list(size = 13)),
        margin = list(l = 8, r = 8, t = 36, b = 8)
      ) |>
      config(displayModeBar = FALSE) |>
      event_register("plotly_click")
  })
}

shinyApp(ui, server)
