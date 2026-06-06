testthat::test_that("dynamic AOI video offset shifts all AOI time columns", {
  source("../../R/dynamic_aoi_video.R", encoding = "UTF-8")
  raw <- data.table::data.table(
    time_ms = 2000,
    start_ms = 1500,
    end_ms = 2500
  )

  adjusted <- .daoi_apply_aoi_offset(raw, -1000)

  testthat::expect_equal(adjusted$time_ms, 1000)
  testthat::expect_equal(adjusted$start_ms, 500)
  testthat::expect_equal(adjusted$end_ms, 1500)
  testthat::expect_equal(adjusted$aoi_video_offset_ms, -1000)
  testthat::expect_equal(raw$time_ms, 2000)
})
