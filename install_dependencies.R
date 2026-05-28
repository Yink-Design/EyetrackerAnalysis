# Install dependencies for EyeLink ASC Analyzer CN
packages <- c(
  "shiny",
  "DT",
  "data.table",
  "ggplot2",
  "openxlsx",
  "jsonlite",
  "zip",
  "ragg",
  "ggforce",
  "png",
  "jpeg",
  "plotly",
  "readxl",
  "testthat"
)
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  install.packages(missing, repos = "https://cloud.r-project.org")
}
message("Dependency check finished.")
