testthat::test_that("interval clipping counts boundary-overlap events", {
  source("../../R/core.R", encoding = "UTF-8")
  events <- data.table::data.table(
    fixation_id = 1:2,
    eye = "R",
    start_time = c(90, 120),
    end_time = c(110, 140),
    duration = c(20, 20),
    x = c(1, 2),
    y = c(1, 2),
    mean_pupil = c(100, 110)
  )
  intervals <- data.table::data.table(
    participant = "p1",
    trial_id = "T001",
    condition = "A",
    duration_level = "short",
    phase = "loading",
    phase_instance = "loading_start_to_complete",
    question_id = NA_character_,
    phase_id = "T001__loading_start_to_complete",
    start_time = 100,
    end_time = 130
  )
  clipped <- clip_events_to_intervals(events, intervals, "fixation")

  testthat::expect_equal(nrow(clipped), 2)
  testthat::expect_equal(clipped$clipped_duration, c(10, 10))
  testthat::expect_equal(clipped$relative_start_time, c(0, 20))
})

testthat::test_that("DataViewer report writer creates expected sheets without DV files", {
  source("../../R/core.R", encoding = "UTF-8")
  parsed <- parse_asc("../../data/demo/FM164641.asc")
  reports <- compute_reports(parsed)
  out <- tempfile(fileext = ".xlsx")
  sheets <- compare_with_dataviewer(parsed, reports, out_file = out)

  testthat::expect_true(file.exists(out))
  testthat::expect_true(all(c("trial_mapping", "warnings") %in% names(sheets)))
  testthat::expect_true(nrow(sheets$warnings) > 0)
})
