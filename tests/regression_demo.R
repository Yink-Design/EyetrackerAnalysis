source("R/core.R", encoding = "UTF-8")

parsed <- parse_asc("data/demo/FM164641.asc")
reports <- compute_reports(parsed)

stopifnot(nrow(parsed$samples) == 94009)
stopifnot(nrow(parsed$fixations) == 126)
stopifnot(nrow(parsed$saccades) == 125)
stopifnot(nrow(parsed$blinks) == 17)
stopifnot(nrow(parsed$messages) == 91)
stopifnot(nrow(parsed$trials) == 2)
stopifnot(parsed$metadata$sampling_rate == 2000)
stopifnot(parsed$metadata$eye == "RIGHT")
stopifnot(paste(parsed$metadata$display_coords, collapse = ",") == "0,0,1919,1079")

aoi <- normalize_aoi(data.table::fread("data/templates/aoi_template.csv", encoding = "UTF-8"))
aoi_report <- compute_aoi_report(parsed, aoi)
stopifnot(is.data.frame(aoi_report))
stopifnot(all(c("dwell_time_ms", "ttff_ms", "visit_count") %in% names(aoi_report)))

behavior <- read_behavior("data/templates/behavior_template.csv")
check <- behavior_check(parsed, behavior)
merged <- merge_eye_behavior_report(reports, behavior)
summary <- condition_summary(merged)
stopifnot(is.data.frame(check))
stopifnot(is.data.frame(merged))
stopifnot(is.data.frame(summary))

tmp <- tempfile(fileext = ".xlsx")
reports$aoi_report <- aoi_report
reports$behavior_check_report <- check
reports$merged_eye_behavior_report <- merged
reports$condition_summary <- summary
export_xlsx(reports, tmp)
stopifnot(file.exists(tmp))

cat("Demo regression passed.\n")
