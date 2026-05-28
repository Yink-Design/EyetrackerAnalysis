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

stopifnot("fixation_interval_report" %in% names(reports))
stopifnot("saccade_interval_report" %in% names(reports))
stopifnot("blink_interval_report" %in% names(reports))
stopifnot("phase_analysis_long" %in% names(reports))

compare_with_dataviewer(parsed, reports, out_file = "outputs/dv_alignment_report.xlsx")
stopifnot(file.exists("outputs/dv_alignment_report.xlsx"))

message("Demo parser and DataViewer-alignment scaffolding passed.")
