# Standalone launcher for dynamic AOI video validation.
# Usage:
#   shiny::runApp("dynamic_aoi_validator_app.R")
# or:
#   source("dynamic_aoi_validator_app.R", encoding = "UTF-8")

options(shiny.maxRequestSize = 1024 * 1024^2)

required_packages <- c("shiny", "DT", "data.table", "ggplot2", "png", "jpeg")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages) > 0) {
  stop("Missing R packages: ", paste(missing_packages, collapse = ", "), ". Run source('install_dependencies.R') first.", call. = FALSE)
}

source("global.R", encoding = "UTF-8")
source("R/core.R", encoding = "UTF-8")
source("R/dynamic_aoi_video.R", encoding = "UTF-8")

dynamic_aoi_validator_app()
