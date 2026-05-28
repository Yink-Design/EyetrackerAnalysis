options(
  shiny.host = "127.0.0.1",
  shiny.port = 3838,
  shiny.maxRequestSize = 1024 * 1024^2
)

shiny::runApp(".", launch.browser = FALSE)
