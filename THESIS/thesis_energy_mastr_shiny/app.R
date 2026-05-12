# Entry for shiny::runGitHub(..., subdir = "THESIS/thesis_energy_mastr_shiny")
# (shinyAppDir requires app.R or server.R in the app directory.)
#
# This exposes the thesis menu only. For menu → child app chaining in RStudio,
# use: shiny::runApp("run_app_thesis_energy.R")

source("thesis_menu_app.R", local = TRUE)
shinyApp(ui, server)
