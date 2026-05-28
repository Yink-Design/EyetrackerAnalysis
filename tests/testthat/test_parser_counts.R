testthat::test_that("demo ASC parser counts stay stable", {
  source("../../R/core.R", encoding = "UTF-8")
  parsed <- parse_asc("../../data/demo/FM164641.asc")

  testthat::expect_equal(nrow(parsed$samples), 94009)
  testthat::expect_equal(nrow(parsed$fixations), 126)
  testthat::expect_equal(nrow(parsed$saccades), 125)
  testthat::expect_equal(nrow(parsed$blinks), 17)
  testthat::expect_equal(nrow(parsed$messages), 91)
  testthat::expect_equal(nrow(parsed$trials), 2)
  testthat::expect_equal(parsed$metadata$sampling_rate, 2000)
  testthat::expect_equal(parsed$metadata$eye, "RIGHT")
  testthat::expect_equal(paste(parsed$metadata$display_coords, collapse = ","), "0,0,1919,1079")
})
