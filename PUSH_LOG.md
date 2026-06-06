# Push Log

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
