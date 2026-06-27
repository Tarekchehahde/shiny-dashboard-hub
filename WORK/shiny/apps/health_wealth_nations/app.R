# =============================================================================
# health_wealth_nations — Gapminder / Hans Rosling inspired bubble chart.
# Classic "Health and Wealth of Nations": life expectancy vs GDP per capita,
# bubble size = population, colour = continent, animated over time.
# Data: gapminder (bundled CSV; original Gapminder / Jennifer Bryan).
# =============================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(plotly)
  library(dplyr)
})

source("../../R/ui_helpers.R")

GAP <- read.csv(
  file.path("data", "gapminder.csv"),
  stringsAsFactors = FALSE
) |>
  mutate(
    year = as.integer(year),
    continent = factor(continent),
    pop_mio = pop / 1e6
  )

YEAR_RANGE <- range(GAP$year, na.rm = TRUE)
CONTINENTS <- levels(GAP$continent)

# Gapminder-style continent colours
CONTINENT_COLORS <- c(
  "Africa" = "#E24A33",
  "Americas" = "#348ABD",
  "Asia" = "#988ED5",
  "Europe" = "#FBC15E",
  "Oceania" = "#8EBA42"
)

ui <- mastr_page(
  title = "Health and Wealth of Nations",
  subtitle = paste(
    "Inspired by Hans Rosling's Gapminder:",
    "life expectancy (health) vs GDP per capita (wealth),",
    "bubble size = population, animated through time."
  ),
  fluid = TRUE,
  footer = "gapminder",
  layout_sidebar(
    sidebar = sidebar(
      width = 280,
      title = "Controls",
      sliderInput(
        "year", "Year",
        min = YEAR_RANGE[1], max = YEAR_RANGE[2],
        value = YEAR_RANGE[2],
        step = 5, sep = "", animate = animationOptions(interval = 900, loop = TRUE)
      ),
      checkboxGroupInput(
        "continents", "Continents",
        choices = CONTINENTS,
        selected = CONTINENTS
      ),
      checkboxInput("log_x", "Log scale (GDP per capita)", TRUE),
      checkboxInput("show_labels", "Country labels (selected year)", FALSE),
      hr(),
      p(class = "small text-muted mb-1",
        strong("How to read:"), " Up/right = healthier & wealthier.",
        " Larger bubbles = more people.")
    ),
    layout_column_wrap(
      width = 1/3,
      value_box(
        title = "Countries",
        value = textOutput("kpi_n", inline = TRUE)
      ),
      value_box(
        title = "Median life expectancy",
        value = textOutput("kpi_life", inline = TRUE)
      ),
      value_box(
        title = "Median GDP / capita",
        value = textOutput("kpi_gdp", inline = TRUE)
      )
    ),
    card(
      card_header("Wealth vs health — animated bubble chart"),
      plotlyOutput("bubble", height = "520px")
    ),
    card(
      card_header(textOutput("table_title", inline = TRUE)),
      tableOutput("country_table")
    )
  )
)

server <- function(input, output, session) {
  mastr_hub_back_server(session)

  filtered <- reactive({
    GAP |>
      filter(
        year == input$year,
        continent %in% input$continents
      )
  })

  output$kpi_n <- renderText(nrow(filtered()))
  output$kpi_life <- renderText({
    sprintf("%.1f yrs", median(filtered()$lifeExp, na.rm = TRUE))
  })
  output$kpi_gdp <- renderText({
    sprintf("$%s", format(round(median(filtered()$gdpPercap, na.rm = TRUE)), big.mark = ","))
  })

  output$table_title <- renderText({
    sprintf("Snapshot %s — selected continents", input$year)
  })

  output$country_table <- renderTable({
    filtered() |>
      arrange(desc(gdpPercap)) |>
      transmute(
        Country = country,
        Continent = continent,
        `Life exp.` = round(lifeExp, 1),
        `GDP/cap` = round(gdpPercap, 0),
        `Pop (Mio)` = round(pop_mio, 2)
      )
  }, striped = TRUE, hover = TRUE, spacing = "s")

  output$bubble <- renderPlotly({
    d <- GAP |> filter(continent %in% input$continents)
    if (nrow(d) == 0) {
      return(plot_ly() |> layout(title = "No data for selected filters"))
    }

    max_pop <- max(d$pop, na.rm = TRUE)
    sizeref <- 2.0 * max_pop / (40^2)

    p <- plot_ly(
      d,
      x = ~gdpPercap,
      y = ~lifeExp,
      size = ~pop,
      color = ~continent,
      colors = CONTINENT_COLORS,
      frame = ~year,
      text = ~paste0(
        country, "<br>Year: ", year,
        "<br>Life exp: ", round(lifeExp, 1), " yrs",
        "<br>GDP/cap: $", format(round(gdpPercap), big.mark = ","),
        "<br>Pop: ", format(round(pop_mio, 1), big.mark = "."), " Mio"
      ),
      hoverinfo = "text",
      type = "scatter",
      mode = "markers",
      marker = list(
        sizemode = "area",
        sizeref = sizeref,
        sizemin = 3,
        opacity = 0.82,
        line = list(width = 0.5, color = "#ffffff")
      )
    ) |>
      layout(
        xaxis = list(
          title = "GDP per capita (USD, inflation-adjusted)",
          type = if (isTRUE(input$log_x)) "log" else "linear",
          gridcolor = "#eef2f7"
        ),
        yaxis = list(
          title = "Life expectancy (years)",
          gridcolor = "#eef2f7"
        ),
        legend = list(title = list(text = "Continent")),
        hovermode = "closest",
        margin = list(t = 40)
      ) |>
      animation_opts(frame = 900, transition = 300, redraw = FALSE)

    if (isTRUE(input$show_labels)) {
      snap <- d |> filter(year == input$year)
      p <- p |>
        add_trace(
          data = snap,
          x = ~gdpPercap,
          y = ~lifeExp,
          text = ~country,
          mode = "text",
          textposition = "top center",
          textfont = list(size = 9, color = "#374151"),
          showlegend = FALSE,
          hoverinfo = "skip"
        )
    }

    p
  })
}

shinyApp(ui, server)
