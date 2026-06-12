# Push Log

## 2026-06-11 - Formal experiment V2 implementation

- Extended ASC marker parsing for `trial_id=`, bare EXP2 `TRIAL_RESULT`, EXP2 payload fields, and experiment-aware Trial/Event tables.
- Added EXP2 loading, stage 1/2/3, progressive-usable, selection, and trial-total phases.
- Added local formal-participant directory loading through `DataCollectionManifest.csv`, while retaining legacy file uploads.
- Added separate EXP1 and EXP2 behavior alignment/merged reports and condition summaries.
- Added formal dynamic AOI analysis using `RECORDING_TIME_REFERENCE` Unix-to-EyeLink alignment; video-preview offsets remain isolated from formal reports.
- Added Experiment filtering, experiment-aware static AOI binding, package inventory/warnings, EXP2 report tables, dynamic AOI formal reports, and automatic package loading in the validator.
- Added `tests/testthat/test_formal_v2.R`.

### Validation

- Full V2 package: 989,877 samples, 10 trials, 52 phases, 58 EXP2 alignment rows, 4 EXP2 selection merges.
- Full formal report generation and XLSX export completed successfully.
- `testthat::test_dir("tests/testthat")`
- `Rscript tests/regression_demo.R`
- `source("app.R")`
- `node --check www/dynamic-aoi-player.js`

## 2026-06-11 - Formal experiment V2 data audit

### Scope

- Audited the formal-output sample under `data/demo/V2/610FullTrialTest/`.
- Confirmed that one participant package now contains manifest, behavior CSV, dynamic AOI, EDF/ASC, EyeLink marker log, screen-recording log, and MKV recording files.
- This section records the pre-implementation audit; the migration was completed in the implementation entry above.

### Experiment flow and markers

- The formal run is one continuous EyeLink recording with `EXPERIMENT_RUN_MODE EXP1_THEN_EXP2`.
- EXP1 contains six trials, `T001` through `T006`, and keeps the current marker family:
  `LOADING_START`, `LOADING_COMPLETE`, `PROGRESSIVE_USABLE`, `VIEWER_ENTER`,
  `QUESTION_START`, `QUESTION_SUBMIT`, `VIEWER_EXIT`, and `TRIAL_RESULT`.
- EXP2 contains four trials, `Exp2_001` through `Exp2_004`, and introduces a separate marker family:
  `EXP2_LOADING_START`, `EXP2_OBJECT_STAGE_CHANGED`, `EXP2_STAGE_1_START`,
  `EXP2_STAGE_2_START`, `EXP2_PROGRESSIVE_USABLE`, `EXP2_STAGE_3_START`,
  `EXP2_LOADING_COMPLETE`, `EXP2_PENDING_SELECTION`, and `EXP2_SUBMIT_SELECTION`.
- EXP2 trial variables add spatial/progressive flags, target display/content indices,
  slot permutation, sequence group/index, and target label.
- The session ends with `EXPERIMENT_END_SCREEN_SHOWN` followed by `FORMAL_RECORDING_END`.

### Observed package structure

- `DataCollectionManifest.csv`: 10 successful collection/copy records; includes duplicate
  fallback entries for the EDF and screen recording.
- EXP1 result CSV: 12 question-level rows across 6 trials and conditions
  `A`, `A_PLUS`, `B`, `C`, and `C_MINUS`.
- EXP2 result CSV: 58 event-level rows across 4 trials and conditions
  `E1_SPATIAL_PROGRESSIVE`, `E2_FIXED_PROGRESSIVE`,
  `E3_SPATIAL_NONPROGRESSIVE`, and `E4_FIXED_NONPROGRESSIVE`.
- Dynamic AOI CSV: 1,407 rows. It contains EXP1/B AOIs for `T006` and EXP2 AOIs for
  E1, E2, and E3 trials; E4 has no dynamic AOI rows.
- Dynamic AOI groups are `b_preview_panel`, `exp2_table_objects`, and
  `exp2_target_object`, with 201 time slices per group/trial.
- `ScreenRecordingLog.csv` is cumulative and contains historical recordings, so it must
  be filtered to the participant/session instead of treated as a participant-only file.

### Current compatibility gaps

- `R/core.R::build_phases()` only recognizes the EXP1 marker family, so EXP2 currently
  receives `trial_total` but no loading, progressive, stage, or selection phases.
- Parsed trial rows do not retain the `experiment` variable or the new EXP2 trial
  variables, preventing explicit EXP1/EXP2 separation in downstream tables.
- Parsed event rows retain only the existing small key-value subset and do not expose
  EXP2 fields such as `stage`, `progress`, object-stage changes, target indices, or
  selection correctness.
- Trial-end detection expects `EVENT TRIAL_RESULT`, while EXP2 emits bare
  `TRIAL_RESULT Exp2_*`; EXP2 trial ends therefore fall back to the next trial/session end.
- Existing UI event choices and metrics are still modeled around EXP1 loading/question
  phases and require an EXP2-specific phase/metric mapping.
- Formal timing has multiple valid anchors: EyeLink event time, UE relative time, Unix
  time, and video-relative time. The end-event CSV is written after the EyeLink
  `EXPERIMENT_END_SCREEN_SHOWN` marker, so it must not replace the ASC marker as the
  EyeLink phase boundary.

## 2026-06-06 - Dynamic AOI next steps

- Implemented the unified participant-level dynamic AOI CSV contract.
- Added experiment, condition, Trial, AOI Scope, and B/E1/E3 loading-segment filters.
- Changed clamped AOIs from invalid rows to visible warnings when they intersect the screen.
- Added loading-segment detection, video seeking, gaze × AOI hit computation, and four CSV exports.
- Consolidated the standalone validator onto `R/dynamic_aoi_video.R` instead of loading v2/v3/v4 overrides.
- Fixed ASC gaze overlays by automatically mapping absolute EyeLink timestamps to the video origin.
- Added a reliable custom seek slider, 5-second jump controls, MP4 faststart preparation, and full video preload.

## 2026-06-06

### Dynamic AOI video validation

- Integrated the dynamic AOI validator into the main Shiny navigation.
- Added continuous video playback with real-time AOI and optional gaze overlays.
- Streamed large AOI and gaze datasets through NDJSON resources to avoid oversized Shiny websocket messages.
- Added AOI video-time offset with immediate refresh.
- Added AOI X/Y translation and independent horizontal/vertical scaling for viewport alignment.
- Added cache-busting and stale-request protection so calibration changes apply immediately.
- Added the local ffmpeg default path `D:/Tools/ffmpeg/bin/ffmpeg.exe` when available.
- Capped invalid AOI preview rows to keep DataTables responsive.
- Removed shallow-copy warnings from dynamic AOI standardization.

### Validation

- `source("app.R")`
- `node --check www/dynamic-aoi-player.js`
- `Rscript tests/regression_demo.R`
- `testthat::test_dir("tests/testthat")`
