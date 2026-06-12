source("../../R/dynamic_aoi_video.R", encoding = "UTF-8")

testthat::test_that("dynamic AOI helpers tolerate null tables without shallow-copy warnings", {
  warnings <- character()
  testthat::expect_equal(nrow(.daoi_table(NULL)), 0)
  withCallingHandlers(
    standardize_dynamic_aoi(data.frame(x_min = 1, y_min = 2, x_max = 3, y_max = 4)),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  testthat::expect_length(warnings, 0)
})

testthat::test_that("absolute EyeLink gaze times auto-align to video origin", {
  gaze <- data.table::data.table(time_ms = c(8108703, 8108704), gaze_x = 10, gaze_y = 20)
  offset <- .daoi_auto_gaze_offset(gaze)

  testthat::expect_equal(offset, 8108703)
  testthat::expect_equal(gaze$time_ms - offset, c(0, 1))
  testthat::expect_equal(.daoi_auto_gaze_offset(data.table::data.table(time_ms = c(0, 1))), 0)
  testthat::expect_equal(.daoi_auto_gaze_offset(data.table::data.table(time_ms = c(120000, 120001))), 0)
  testthat::expect_equal(.daoi_auto_gaze_offset(data.table::data.table(time_ms = c(120000, 120001)), force = TRUE), 120000)
})

testthat::test_that("unified dynamic AOI fields and video times are standardized", {
  raw <- data.table::data.table(
    participant = "X001", trial_id = "T01", condition = "e1",
    aoi_group_id = "exp2_target_object",
    video_time_start_ms = 100, video_time_end_ms = 200,
    x_min = 10, y_min = 10, x_max = 20, y_max = 20,
    projection_valid = 1, is_clamped = 1, enabled = 1, visible = 1
  )
  out <- standardize_dynamic_aoi(raw)

  testthat::expect_equal(out$experiment_code, "EXP2")
  testthat::expect_equal(out$aoi_scope, "exp2_target_object")
  testthat::expect_equal(out$time_ms, 150)
  testthat::expect_true(out$valid_aoi)
  testthat::expect_equal(out$warning_reason, "clamped")
})

testthat::test_that("segments only include dynamic conditions", {
  aoi <- standardize_dynamic_aoi(data.table::data.table(
    participant = "X001", trial_id = c("T1", "T2", "T3", "T4"),
    condition = c("B", "E1", "E3", "C"),
    aoi_group_id = c("b_preview_panel", "exp2_table_objects", "exp2_target_object", "static"),
    start_ms = c(0, 100, 200, 300), end_ms = c(50, 150, 250, 350),
    x_min = 0, y_min = 0, x_max = 100, y_max = 100
  ))
  segments <- build_dynamic_aoi_segments(aoi)

  testthat::expect_equal(sort(segments$condition), c("B", "E1", "E3"))
  testthat::expect_false("C" %in% segments$condition)
})

testthat::test_that("partly visible clamped AOIs remain valid", {
  aoi <- standardize_dynamic_aoi(data.table::data.table(
    aoi_group_id = c("partial", "outside"),
    x_min = c(-20, -200), y_min = c(10, 10), x_max = c(20, -100), y_max = c(50, 50),
    projection_valid = 1, is_clamped = 1, enabled = 1, visible = 1
  ))
  checked <- validate_dynamic_aoi(aoi, screen_width = 100, screen_height = 100)$rows

  testthat::expect_true(checked[aoi_group_id == "partial", valid_aoi])
  testthat::expect_false(checked[aoi_group_id == "outside", valid_aoi])
})

testthat::test_that("gaze AOI hits produce detail and summary", {
  aoi <- standardize_dynamic_aoi(data.table::data.table(
    participant = "X001", trial_id = "T1", condition = "B", aoi_group_id = "b_preview_panel",
    start_ms = 0, end_ms = 100, x_min = 0, y_min = 0, x_max = 100, y_max = 100
  ))
  gaze <- data.table::data.table(
    video_time_ms = c(10, 20), gaze_x = c(50, 150), gaze_y = c(50, 50),
    pupil = c(1000, 1100), valid_gaze = TRUE
  )
  result <- compute_dynamic_gaze_aoi_hits(aoi, gaze, sample_period_ms = 10)

  testthat::expect_equal(result$hits$hit, c(TRUE, FALSE))
  testthat::expect_equal(result$summary$aoi_sample_count, 1)
  testthat::expect_equal(result$summary$dwell_time_sample_ms, 10)
})
