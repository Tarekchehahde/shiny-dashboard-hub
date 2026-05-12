# =============================================================================
# run_app_thesis_energy.R — SEPARATE launcher for thesis / research dashboards
# (battery tech, storage focus, lithium raw-materials context). Does not modify
# or reference production run_app.R or apps/01_* … 15_*.
#
# Usage (from THESIS/thesis_energy_mastr_shiny/ inside clone of Tarekchehahde/mastr-shiny):
#   shiny::runApp("run_app_thesis_energy.R")
#
# shiny::runGitHub(..., subdir = "THESIS/thesis_energy_mastr_shiny") loads app.R
# (menu only). Use this file for the two-step menu → app flow in RStudio.
# =============================================================================

source("thesis_menu_app.R", local = TRUE)

launched <- shinyApp(ui, server)
if (interactive()) {
  picked <- tryCatch(
    {
      options(thesis.menu.return_path = TRUE)
      runApp(launched)
    },
    finally = options(thesis.menu.return_path = NULL)
  )
  if (is.character(picked) && nzchar(picked)) {
    app_full <- file.path(getwd(), picked)
    if (!dir.exists(app_full)) {
      stop(
        "App not found at:\n  ", app_full,
        "\nSet working directory to THESIS/thesis_energy_mastr_shiny/ (repo mastr-shiny) then run:\n",
        "  shiny::runApp(\"run_app_thesis_energy.R\")",
        call. = FALSE
      )
    }
    message(sprintf(">> launching %s", picked))
    shiny::runApp(app_full)
  }
} else {
  launched
}
