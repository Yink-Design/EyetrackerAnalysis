source("../../R/core.R", encoding = "UTF-8")
source("../../R/dynamic_aoi_video.R", encoding = "UTF-8")

v2_root <- "../../data/demo/V2/610FullTrialTest"
v2_asc <- file.path(v2_root, "EDF", "FM214601.asc")
v2_exp2 <- file.path(v2_root, "CSV", "610FullTrialTest_exp02_Experiment2Results.csv")
v2_aoi <- file.path(v2_root, "AOI", "610FullTrialTest_DynamicAOI.csv")

testthat::test_that("formal V2 markers normalize trial_id and bare trial results", {
  msg <- parse_messages(c(
    "MSG 100 TRIALID Exp2_001",
    "MSG 101 EVENT EXP2_LOADING_START trial_id=Exp2_001 unix=1000 condition=E1_SPATIAL_PROGRESSIVE",
    "MSG 102 EVENT EXP2_OBJECT_STAGE_CHANGED trial_id=Exp2_001 object_index=2 previous_stage=0 new_stage=1 progress=0.25",
    "MSG 103 TRIAL_RESULT Exp2_001 selected=2 correct=1"
  ))
  testthat::expect_equal(msg[is_event == TRUE]$event_name, c("EXP2_LOADING_START", "EXP2_OBJECT_STAGE_CHANGED", "TRIAL_RESULT"))
  testthat::expect_equal(msg[event_name == "TRIAL_RESULT"]$trial_from_kv, "Exp2_001")
  testthat::expect_equal(msg[event_name == "EXP2_OBJECT_STAGE_CHANGED"]$object_index, 2)
  testthat::expect_equal(msg[event_name == "EXP2_OBJECT_STAGE_CHANGED"]$progress, 0.25)
})

testthat::test_that("formal V2 ASC builds both experiments and EXP2 phases", {
  testthat::skip_if_not(file.exists(v2_asc))
  parsed <- parse_asc(v2_asc, keep_samples = FALSE)
  testthat::expect_equal(nrow(parsed$trials), 10)
  testthat::expect_equal(parsed$trials[, .N, by = experiment][experiment == "EXP1"]$N, 6)
  testthat::expect_equal(parsed$trials[, .N, by = experiment][experiment == "EXP2"]$N, 4)
  testthat::expect_true(all(nzchar(parsed$trials$condition)))
  testthat::expect_true(all(parsed$trials[experiment == "EXP2"]$trial_end < parsed$metadata$end_time))
  exp2_phases <- parsed$phases[experiment == "EXP2"]
  testthat::expect_equal(exp2_phases[phase == "loading", .N], 4)
  testthat::expect_equal(exp2_phases[phase == "stage_1", .N], 2)
  testthat::expect_equal(exp2_phases[phase == "stage_2", .N], 2)
  testthat::expect_equal(exp2_phases[phase == "stage_3", .N], 4)
  testthat::expect_equal(exp2_phases[phase == "progressive_usable", .N], 2)
  testthat::expect_equal(exp2_phases[phase == "selection", .N], 4)
})

testthat::test_that("formal package inventory and EXP2 behavior align", {
  testthat::skip_if_not(dir.exists(v2_root))
  pkg <- read_formal_participant_package(v2_root, keep_samples = FALSE)
  testthat::expect_true(all(c("manifest", "asc", "exp1_behavior", "exp2_behavior", "dynamic_aoi", "screen_recording") %in% pkg$inventory$type))
  testthat::expect_equal(nrow(pkg$exp1_behavior), 12)
  testthat::expect_equal(nrow(pkg$exp2_behavior), 58)
  alignment <- exp2_alignment_report(pkg$parsed, pkg$exp2_behavior)
  testthat::expect_equal(alignment[asc_event_name == "EXP2_SUBMIT_SELECTION" & status == "ok", .N], 4)
  reports <- compute_reports(pkg$parsed)
  merged <- exp2_eye_behavior_report(reports, pkg$exp2_behavior)
  testthat::expect_equal(nrow(merged), 4)
  testthat::expect_equal(sum(merged$submit_correct, na.rm = TRUE), 3)
})

testthat::test_that("formal dynamic AOI uses unix-to-EyeLink alignment", {
  testthat::skip_if_not(file.exists(v2_asc) && file.exists(v2_aoi))
  parsed <- parse_asc(v2_asc, keep_samples = FALSE)
  raw <- data.table::fread(v2_aoi, encoding = "UTF-8")
  dynamic <- compute_formal_dynamic_aoi(parsed, raw)
  testthat::expect_equal(dynamic$alignment$time_basis, "unix_to_eyelink")
  testthat::expect_equal(dynamic$alignment$aligned_aoi_rows, 1407)
  testthat::expect_equal(sort(unique(dynamic$aoi$trial_id)), sort(c("T006", "Exp2_002", "Exp2_003", "Exp2_004")))
  testthat::expect_false("Exp2_001" %in% dynamic$aoi$trial_id)
})
