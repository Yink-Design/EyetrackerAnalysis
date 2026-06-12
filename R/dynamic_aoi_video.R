# Dynamic AOI video validation utilities
# Focus: verify UE screen-space dynamic AOI boxes against screen recordings.
# Eye data is optional; the validator can run with only a video and dynamic AOI CSV.

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) {
    if (is.null(x) || length(x) == 0 || all(is.na(x)) || identical(x, "")) y else x
  }
}

.daoi_need_pkg <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf("Package '%s' is required.", pkg), call. = FALSE)
  }
}

.daoi_as_num <- function(x) {
  x <- trimws(as.character(x))
  x[x %in% c("", ".", "...", "NA", "NaN", "null", "NULL")] <- NA_character_
  suppressWarnings(as.numeric(x))
}

.daoi_norm_names <- function(x) {
  y <- tolower(trimws(as.character(x)))
  y <- gsub("[^a-z0-9]+", "_", y)
  y <- gsub("^_+|_+$", "", y)
  y <- gsub("_+", "_", y)
  make.unique(y, sep = "_")
}

.daoi_pick_col <- function(dt, candidates) {
  if (is.null(dt) || ncol(dt) == 0) return(NA_character_)
  nms <- names(dt)
  hit <- intersect(candidates, nms)
  if (length(hit) > 0) return(hit[[1]])
  NA_character_
}

.daoi_get <- function(dt, candidates, default = NA_real_) {
  col <- .daoi_pick_col(dt, candidates)
  if (is.na(col)) return(rep(default, nrow(dt)))
  dt[[col]]
}

.daoi_table <- function(x) {
  if (is.null(x) || !is.data.frame(x)) return(data.table::data.table())
  data.table::copy(data.table::as.data.table(x))
}

.daoi_as_bool <- function(x, default = NA) {
  if (length(x) == 0) return(logical())
  if (is.logical(x)) return(x)
  z <- tolower(trimws(as.character(x)))
  out <- rep(default, length(z))
  out[z %in% c("1", "true", "t", "yes", "y", "visible", "valid", "on", "是", "真")] <- TRUE
  out[z %in% c("0", "false", "f", "no", "n", "hidden", "invalid", "off", "否", "假")] <- FALSE
  out
}

.daoi_empty <- function() {
  data.table::data.table(
    row_id = integer(), participant = character(), trial_id = character(), experiment_code = character(), condition = character(), phase = character(),
    aoi_scope = character(), aoi_group_id = character(), aoi_name = character(), shape_id = character(), time_ms = numeric(), start_ms = numeric(), end_ms = numeric(),
    x_min = numeric(), y_min = numeric(), x_max = numeric(), y_max = numeric(),
    projection_valid = logical(), is_clamped = logical(), enabled = logical(), visible = logical(), valid_aoi = logical(),
    invalid_reason = character(), warning_reason = character(), target_content_index = numeric(),
    target_display_index = numeric(), slot_permutation = character(), source_file = character()
  )
}

# Read a CSV/TXT table with tolerant UTF-8 handling.
read_dynamic_aoi_csv <- function(file, time_unit = c("ms", "sec"), source_file = basename(file)) {
  .daoi_need_pkg("data.table")
  time_unit <- match.arg(time_unit)
  raw <- data.table::fread(file, encoding = "UTF-8", na.strings = c("", "NA", "NaN", ".", "null", "NULL"))
  standardize_dynamic_aoi(raw, time_unit = time_unit, source_file = source_file)
}

standardize_dynamic_aoi <- function(x, time_unit = c("ms", "sec"), source_file = "") {
  .daoi_need_pkg("data.table")
  time_unit <- match.arg(time_unit)
  if (is.null(x) || nrow(x) == 0) return(.daoi_empty())
  dt <- data.table::copy(data.table::as.data.table(x))
  original_names <- names(dt)
  data.table::setnames(dt, .daoi_norm_names(names(dt)))

  n <- nrow(dt)
  get_chr <- function(cands, default = "") {
    col <- .daoi_pick_col(dt, cands)
    if (is.na(col)) rep(default, n) else as.character(dt[[col]])
  }
  get_num <- function(cands, default = NA_real_) .daoi_as_num(.daoi_get(dt, cands, default))

  participant <- get_chr(c("participant", "participant_id", "subject", "subj", "pid"))
  trial_id <- get_chr(c("trial_id", "trial", "trialid", "out_trial", "trial_name"))
  condition <- toupper(get_chr(c("condition", "loading_condition", "applied_loading_condition", "strategy", "loading_strategy")))
  experiment_code <- toupper(get_chr(c("experiment_code", "experiment", "exp")))
  experiment_code[!nzchar(experiment_code) & condition == "B"] <- "EXP1"
  experiment_code[!nzchar(experiment_code) & grepl("^E[1-4](_|$)", condition)] <- "EXP2"
  phase <- get_chr(c("phase", "phase_name"), "loading")
  aoi_group_id <- get_chr(c("aoi_group_id", "aoi_id", "aoi", "aoi_group", "name", "label"), "dynamic_aoi")
  aoi_scope <- get_chr(c("aoi_scope", "aoi_group_id", "aoi_id", "aoi"), "")
  aoi_scope[!nzchar(aoi_scope)] <- aoi_group_id[!nzchar(aoi_scope)]
  aoi_name <- get_chr(c("aoi_name", "aoi_label", "display_name"), "Dynamic AOI")
  shape_id <- get_chr(c("shape_id", "id", "row_id", "frame_id"), "")

  # Coordinate aliases from UE / post-processing CSVs.
  x_min <- get_num(c("x_min", "xmin", "min_x", "left", "screen_x_min", "aoi_x_min", "rect_x_min", "bbox_x_min"))
  y_min <- get_num(c("y_min", "ymin", "min_y", "top", "screen_y_min", "aoi_y_min", "rect_y_min", "bbox_y_min"))
  x_max <- get_num(c("x_max", "xmax", "max_x", "right", "screen_x_max", "aoi_x_max", "rect_x_max", "bbox_x_max"))
  y_max <- get_num(c("y_max", "ymax", "max_y", "bottom", "screen_y_max", "aoi_y_max", "rect_y_max", "bbox_y_max"))

  # Alternative representation: x/y/width/height.
  x <- get_num(c("x", "screen_x", "rect_x", "bbox_x"))
  y <- get_num(c("y", "screen_y", "rect_y", "bbox_y"))
  w <- get_num(c("width", "w", "screen_width", "rect_width", "bbox_width"))
  h <- get_num(c("height", "h", "screen_height", "rect_height", "bbox_height"))
  x_min <- ifelse(is.na(x_min) & is.finite(x), x, x_min)
  y_min <- ifelse(is.na(y_min) & is.finite(y), y, y_min)
  x_max <- ifelse(is.na(x_max) & is.finite(x_min) & is.finite(w), x_min + w, x_max)
  y_max <- ifelse(is.na(y_max) & is.finite(y_min) & is.finite(h), y_min + h, y_max)

  start_ms <- get_num(c("video_time_start_ms", "start_ms", "rel_start_ms", "relative_start_ms", "time_start_ms", "aoi_start_ms", "frame_start_ms", "start_time_ms"))
  end_ms <- get_num(c("video_time_end_ms", "end_ms", "rel_end_ms", "relative_end_ms", "time_end_ms", "aoi_end_ms", "frame_end_ms", "end_time_ms"))
  time_ms <- get_num(c("time_ms", "video_time_ms", "video_time_mid_ms", "rel_ms", "relative_ms", "relative_time_ms", "timestamp_ms", "elapsed_ms", "frame_time_ms", "time"))
  frame_index <- get_num(c("frame", "frame_index", "frame_id"))

  if (all(is.na(time_ms)) && any(is.finite(start_ms) | is.finite(end_ms))) {
    time_ms <- ifelse(is.finite(start_ms) & is.finite(end_ms), (start_ms + end_ms) / 2,
      ifelse(is.finite(start_ms), start_ms, end_ms)
    )
  }
  if (all(is.na(time_ms)) && any(is.finite(frame_index))) time_ms <- frame_index
  if (time_unit == "sec") {
    time_ms <- time_ms * 1000
    start_ms <- start_ms * 1000
    end_ms <- end_ms * 1000
  }
  start_ms <- ifelse(is.na(start_ms), time_ms, start_ms)
  end_ms <- ifelse(is.na(end_ms), time_ms, end_ms)

  projection_valid <- .daoi_as_bool(.daoi_get(dt, c("projection_valid", "projected", "valid_projection", "is_projected", "is_valid", "valid"), TRUE), TRUE)
  is_clamped <- .daoi_as_bool(.daoi_get(dt, c("is_clamped", "clamped", "screen_clamped", "edge_clamped"), FALSE), FALSE)
  enabled <- .daoi_as_bool(.daoi_get(dt, c("enabled", "enable", "active", "is_active"), TRUE), TRUE)
  visible <- .daoi_as_bool(.daoi_get(dt, c("visible", "is_visible", "shown", "is_shown"), NA), NA)
  visible[is.na(visible)] <- enabled[is.na(visible)] %||% TRUE
  target_content_index <- get_num(c("target_content_index"))
  target_display_index <- get_num(c("target_display_index"))
  slot_permutation <- get_chr(c("slot_permutation"))

  out <- data.table::data.table(
    row_id = seq_len(n), participant = participant, trial_id = trial_id, experiment_code = experiment_code, condition = condition, phase = phase,
    aoi_scope = aoi_scope, aoi_group_id = aoi_group_id, aoi_name = aoi_name, shape_id = ifelse(nzchar(shape_id), shape_id, paste0("row_", seq_len(n))),
    time_ms = time_ms, start_ms = start_ms, end_ms = end_ms,
    x_min = x_min, y_min = y_min, x_max = x_max, y_max = y_max,
    projection_valid = projection_valid, is_clamped = is_clamped, enabled = enabled, visible = visible,
    target_content_index = target_content_index, target_display_index = target_display_index, slot_permutation = slot_permutation,
    source_file = source_file
  )
  for (nm in c("participant", "trial_id", "experiment_code", "condition", "phase", "aoi_scope", "aoi_group_id", "aoi_name", "shape_id", "slot_permutation", "source_file")) {
    out[[nm]][is.na(out[[nm]])] <- ""
  }
  data.table::set(out, j = "width", value = abs(out$x_max - out$x_min))
  data.table::set(out, j = "height", value = abs(out$y_max - out$y_min))
  data.table::set(out, j = "area", value = abs(out$x_max - out$x_min) * abs(out$y_max - out$y_min))
  data.table::set(out, j = "invalid_reason", value = "")
  out[enabled != TRUE, invalid_reason := paste0(invalid_reason, ";disabled")]
  out[visible != TRUE, invalid_reason := paste0(invalid_reason, ";hidden")]
  out[projection_valid != TRUE, invalid_reason := paste0(invalid_reason, ";projection_invalid")]
  out[!is.finite(x_min) | !is.finite(y_min) | !is.finite(x_max) | !is.finite(y_max), invalid_reason := paste0(invalid_reason, ";missing_coordinates")]
  out[is.finite(width) & is.finite(height) & (width <= 0 | height <= 0), invalid_reason := paste0(invalid_reason, ";non_positive_area")]
  out[, invalid_reason := sub("^;", "", invalid_reason)]
  data.table::set(out, j = "valid_aoi", value = out$invalid_reason == "")
  data.table::set(out, j = "warning_reason", value = ifelse(out$is_clamped == TRUE, "clamped", ""))
  out[]
}

validate_dynamic_aoi <- function(aoi, screen_width = 1920, screen_height = 1080, gap_threshold_ms = 250) {
  .daoi_need_pkg("data.table")
  aoi <- .daoi_table(aoi)
  if (nrow(aoi) == 0) {
    return(list(rows = data.table::data.table(), summary = data.table::data.table(), invalid_rows = data.table::data.table(), gaps = data.table::data.table()))
  }
  data.table::set(aoi, j = "outside_screen", value = aoi$x_max <= 0 | aoi$y_max <= 0 | aoi$x_min >= screen_width | aoi$y_min >= screen_height)
  data.table::set(aoi, j = "partly_outside_screen", value = !aoi$outside_screen & (aoi$x_min < 0 | aoi$y_min < 0 | aoi$x_max > screen_width | aoi$y_max > screen_height))
  aoi[outside_screen == TRUE, invalid_reason := ifelse(nzchar(invalid_reason), paste(invalid_reason, "outside_screen", sep = ";"), "outside_screen")]
  aoi[partly_outside_screen == TRUE, warning_reason := ifelse(nzchar(warning_reason), paste(warning_reason, "partly_outside_screen", sep = ";"), "partly_outside_screen")]
  data.table::set(aoi, j = "valid_aoi", value = aoi$invalid_reason == "")
  key_cols <- intersect(c("participant", "trial_id", "experiment_code", "condition", "phase", "aoi_scope", "aoi_group_id"), names(aoi))
  if (length(key_cols) == 0) key_cols <- "aoi_group_id"
  summary <- aoi[, .(
    n_rows = .N,
    n_valid = sum(valid_aoi, na.rm = TRUE),
    n_projection_invalid = sum(grepl("projection_invalid", invalid_reason), na.rm = TRUE),
    n_clamped = sum(is_clamped == TRUE, na.rm = TRUE),
    n_outside_screen = sum(grepl("outside_screen", invalid_reason), na.rm = TRUE),
    valid_ratio = round(sum(valid_aoi, na.rm = TRUE) / .N, 4),
    first_time_ms = suppressWarnings(min(time_ms, na.rm = TRUE)),
    last_time_ms = suppressWarnings(max(time_ms, na.rm = TRUE)),
    mean_area = suppressWarnings(mean(area[valid_aoi == TRUE], na.rm = TRUE)),
    median_area = suppressWarnings(stats::median(area[valid_aoi == TRUE], na.rm = TRUE))
  ), by = key_cols]
  summary[!is.finite(first_time_ms), first_time_ms := NA_real_]
  summary[!is.finite(last_time_ms), last_time_ms := NA_real_]

  valid <- aoi[valid_aoi == TRUE & is.finite(time_ms)]
  gaps <- data.table::data.table()
  if (nrow(valid) > 1) {
    data.table::setorderv(valid, c(key_cols, "time_ms"))
    gaps <- valid[, .(
      from_time_ms = head(time_ms, -1),
      to_time_ms = tail(time_ms, -1),
      gap_ms = diff(time_ms)
    ), by = key_cols][gap_ms > gap_threshold_ms]
  }
  list(rows = aoi[], summary = summary[], invalid_rows = aoi[nzchar(invalid_reason) | nzchar(warning_reason)], gaps = gaps[])
}

read_gaze_table <- function(file, time_unit = c("ms", "sec"), source_file = basename(file)) {
  .daoi_need_pkg("data.table")
  time_unit <- match.arg(time_unit)
  ext <- tolower(tools::file_ext(file))
  if (ext == "asc" && exists("parse_asc", mode = "function")) {
    parsed <- parse_asc(file)
    sm <- data.table::copy(parsed$samples)
    if (nrow(sm) == 0) return(data.table::data.table())
    out <- sm[, .(time_ms = time, gaze_x = gaze_x, gaze_y = gaze_y, pupil = pupil, valid_gaze = valid_gaze, source_file = source_file)]
    return(out[])
  }
  dt <- data.table::fread(file, encoding = "UTF-8", na.strings = c("", "NA", "NaN", "."))
  data.table::setnames(dt, .daoi_norm_names(names(dt)))
  n <- nrow(dt)
  get_num <- function(cands, default = NA_real_) .daoi_as_num(.daoi_get(dt, cands, default))
  time_ms <- get_num(c("time_ms", "time", "timestamp_ms", "rel_ms", "relative_time_ms", "video_time_ms", "elapsed_ms"))
  gaze_x <- get_num(c("gaze_x", "x", "gx", "screen_x", "fix_x", "current_fix_x"))
  gaze_y <- get_num(c("gaze_y", "y", "gy", "screen_y", "fix_y", "current_fix_y"))
  pupil <- get_num(c("pupil", "pupil_area", "pa", "pupil_size"))
  if (time_unit == "sec") time_ms <- time_ms * 1000
  data.table::data.table(time_ms = time_ms, gaze_x = gaze_x, gaze_y = gaze_y, pupil = pupil,
    valid_gaze = is.finite(gaze_x) & is.finite(gaze_y), source_file = source_file)
}

build_dynamic_aoi_segments <- function(aoi_dt) {
  .daoi_need_pkg("data.table")
  aoi <- data.table::copy(data.table::as.data.table(aoi_dt))
  if (nrow(aoi) == 0) return(data.table::data.table())
  for (nm in c("participant", "trial_id", "experiment_code", "condition", "phase", "aoi_scope")) {
    if (!nm %in% names(aoi)) data.table::set(aoi, j = nm, value = "")
  }
  aoi <- aoi[toupper(condition) == "B" | grepl("^E[123](_|$)", toupper(condition))]
  if (nrow(aoi) == 0) return(data.table::data.table())
  keys <- c("participant", "trial_id", "experiment_code", "condition", "phase")
  segments <- aoi[, .(
    start_ms = suppressWarnings(min(c(start_ms, time_ms), na.rm = TRUE)),
    end_ms = suppressWarnings(max(c(end_ms, time_ms), na.rm = TRUE)),
    aoi_scopes = paste(sort(unique(aoi_scope[nzchar(aoi_scope)])), collapse = ", "),
    n_rows = .N,
    n_valid = sum(valid_aoi == TRUE, na.rm = TRUE),
    valid_ratio = round(sum(valid_aoi == TRUE, na.rm = TRUE) / .N, 4)
  ), by = keys]
  segments[!is.finite(start_ms), start_ms := NA_real_]
  segments[!is.finite(end_ms), end_ms := NA_real_]
  segments[, duration_ms := end_ms - start_ms]
  segments[, segment_id := paste(participant, trial_id, experiment_code, condition, phase, sep = "|")]
  segments[, segment_label := sprintf("%s | %s | %s | %.1fs-%.1fs", experiment_code, trial_id, condition, start_ms / 1000, end_ms / 1000)]
  data.table::setcolorder(segments, c("segment_id", keys, "segment_label", "start_ms", "end_ms", "duration_ms", "aoi_scopes", "n_rows", "n_valid", "valid_ratio"))
  segments[]
}

compute_dynamic_gaze_aoi_hits <- function(aoi, gaze, sample_period_ms = NULL) {
  .daoi_need_pkg("data.table")
  boxes <- data.table::copy(data.table::as.data.table(aoi))
  points <- data.table::copy(data.table::as.data.table(gaze))
  if (nrow(boxes) == 0 || nrow(points) == 0) return(list(hits = data.table::data.table(), summary = data.table::data.table()))
  points <- points[valid_gaze == TRUE & is.finite(video_time_ms) & is.finite(gaze_x) & is.finite(gaze_y)]
  boxes <- boxes[valid_aoi == TRUE & is.finite(start_ms) & is.finite(end_ms) & end_ms > start_ms]
  if (nrow(boxes) == 0 || nrow(points) == 0) return(list(hits = data.table::data.table(), summary = data.table::data.table()))
  if (is.null(sample_period_ms) || !is.finite(sample_period_ms)) {
    sample_period_ms <- suppressWarnings(stats::median(diff(sort(unique(points$video_time_ms))), na.rm = TRUE))
  }
  if (!is.finite(sample_period_ms) || sample_period_ms <= 0) sample_period_ms <- 1
  points[, `:=`(.gaze_start = video_time_ms, .gaze_end = video_time_ms)]
  boxes[, `:=`(.aoi_start = start_ms, .aoi_end = end_ms)]
  data.table::setkey(boxes, .aoi_start, .aoi_end)
  overlaps <- data.table::foverlaps(points, boxes, by.x = c(".gaze_start", ".gaze_end"), by.y = c(".aoi_start", ".aoi_end"), type = "within", nomatch = 0L)
  overlaps[, hit := gaze_x >= x_min & gaze_x <= x_max & gaze_y >= y_min & gaze_y <= y_max]
  keep <- intersect(c("video_time_ms", "gaze_x", "gaze_y", "pupil", "participant", "trial_id", "experiment_code", "condition", "aoi_scope", "aoi_group_id", "hit"), names(overlaps))
  hits <- overlaps[, ..keep]
  keys <- intersect(c("participant", "trial_id", "experiment_code", "condition", "aoi_scope", "aoi_group_id"), names(hits))
  summary <- hits[, .(
    dwell_time_sample_ms = sum(hit, na.rm = TRUE) * sample_period_ms,
    aoi_sample_count = sum(hit, na.rm = TRUE),
    aoi_sample_proportion = mean(hit, na.rm = TRUE),
    first_hit_time_ms = if (any(hit)) min(video_time_ms[hit], na.rm = TRUE) else NA_real_,
    ttff_ms = if (any(hit)) min(video_time_ms[hit], na.rm = TRUE) - min(video_time_ms, na.rm = TRUE) else NA_real_,
    mean_pupil_in_aoi = if (any(hit)) mean(pupil[hit], na.rm = TRUE) else NA_real_
  ), by = keys]
  list(hits = hits[], summary = summary[])
}

select_aoi_at_time <- function(aoi, time_ms, max_nearest_gap_ms = 120, valid_only = FALSE) {
  .daoi_need_pkg("data.table")
  aoi <- data.table::as.data.table(aoi)
  if (nrow(aoi) == 0 || !is.finite(time_ms)) return(aoi[0])
  cand <- aoi
  if (isTRUE(valid_only) && "valid_aoi" %in% names(cand)) cand <- cand[valid_aoi == TRUE]
  if (nrow(cand) == 0) return(cand)
  if (any(is.finite(cand$start_ms) & is.finite(cand$end_ms) & cand$end_ms > cand$start_ms)) {
    hit <- cand[is.finite(start_ms) & is.finite(end_ms) & time_ms >= start_ms & time_ms < end_ms]
    if (nrow(hit) > 0) return(hit[])
  }
  target_time_ms <- time_ms
  cand[, .dist := abs(get("time_ms") - target_time_ms)]
  hit <- cand[is.finite(.dist) & .dist <= max_nearest_gap_ms]
  hit[, .dist := NULL]
  hit[]
}

read_raster_image <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext == "png") {
    .daoi_need_pkg("png")
    return(png::readPNG(path))
  }
  if (ext %in% c("jpg", "jpeg")) {
    .daoi_need_pkg("jpeg")
    return(jpeg::readJPEG(path))
  }
  stop("Only PNG/JPG/JPEG frames are supported.", call. = FALSE)
}

extract_video_frame_ffmpeg <- function(video_file, time_sec, out_file, ffmpeg_path = "ffmpeg") {
  dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
  args <- c("-y", "-ss", sprintf("%.3f", time_sec), "-i", normalizePath(video_file, winslash = "/"), "-frames:v", "1", normalizePath(out_file, winslash = "/", mustWork = FALSE))
  res <- tryCatch(system2(ffmpeg_path, args = args, stdout = TRUE, stderr = TRUE), error = function(e) e)
  ok <- file.exists(out_file) && file.info(out_file)$size > 0
  attr(ok, "log") <- if (inherits(res, "error")) conditionMessage(res) else paste(res, collapse = "\n")
  ok
}

make_frame_plan <- function(aoi, interval_ms = 1000, max_frames = 20, valid_only = TRUE) {
  .daoi_need_pkg("data.table")
  aoi <- data.table::as.data.table(aoi)
  if (isTRUE(valid_only) && "valid_aoi" %in% names(aoi)) aoi <- aoi[valid_aoi == TRUE]
  times <- aoi$time_ms[is.finite(aoi$time_ms)]
  if (length(times) == 0) return(data.table::data.table(frame_id = integer(), time_ms = numeric(), time_sec = numeric(), frame_file = character()))
  lo <- min(times); hi <- max(times)
  if (!is.finite(lo) || !is.finite(hi) || hi < lo) return(data.table::data.table())
  seq_times <- seq(lo, hi, by = max(1, interval_ms))
  if (length(seq_times) > max_frames) seq_times <- seq(lo, hi, length.out = max_frames)
  data.table::data.table(frame_id = seq_along(seq_times), time_ms = seq_times, time_sec = seq_times / 1000, frame_file = "")
}

scale_screen_dt <- function(dt, frame_width, frame_height, screen_width = 1920, screen_height = 1080) {
  .daoi_need_pkg("data.table")
  out <- data.table::copy(data.table::as.data.table(dt))
  if (nrow(out) == 0) return(out)
  sx <- frame_width / screen_width
  sy <- frame_height / screen_height
  for (nm in intersect(c("x_min", "x_max", "gaze_x"), names(out))) out[[nm]] <- as.numeric(out[[nm]]) * sx
  for (nm in intersect(c("y_min", "y_max", "gaze_y"), names(out))) out[[nm]] <- as.numeric(out[[nm]]) * sy
  out
}

plot_dynamic_aoi_frame <- function(frame_file, aoi_rows = NULL, gaze_rows = NULL, time_ms = NA_real_,
                                   screen_width = 1920, screen_height = 1080,
                                   title = NULL) {
  .daoi_need_pkg("ggplot2")
  .daoi_need_pkg("data.table")
  img <- read_raster_image(frame_file)
  frame_height <- dim(img)[1]
  frame_width <- dim(img)[2]
  title <- title %||% sprintf("Dynamic AOI validation | %.0f ms", time_ms)
  p <- ggplot2::ggplot() +
    ggplot2::annotation_raster(as.raster(img), xmin = 0, xmax = frame_width, ymin = frame_height, ymax = 0) +
    ggplot2::coord_fixed(xlim = c(0, frame_width), ylim = c(frame_height, 0), expand = FALSE) +
    ggplot2::labs(x = "screen x", y = "screen y", title = title) +
    ggplot2::theme_void() +
    ggplot2::theme(plot.title = ggplot2::element_text(size = 11))

  if (!is.null(aoi_rows) && nrow(aoi_rows) > 0) {
    ar <- scale_screen_dt(aoi_rows, frame_width, frame_height, screen_width, screen_height)
    data.table::set(ar, j = "label", value = ifelse(nzchar(ar$aoi_name), ar$aoi_name, ar$aoi_group_id))
    p <- p +
      ggplot2::geom_rect(data = ar, ggplot2::aes(xmin = x_min, xmax = x_max, ymin = y_min, ymax = y_max, color = valid_aoi),
        fill = NA, linewidth = 1.0, inherit.aes = FALSE) +
      ggplot2::geom_text(data = ar, ggplot2::aes(x = x_min, y = y_min, label = label),
        hjust = 0, vjust = 1.2, size = 3, inherit.aes = FALSE) +
      ggplot2::scale_color_manual(values = c(`TRUE` = "#00B050", `FALSE` = "#E31A1C"), na.value = "#E31A1C", guide = "none")
  }
  if (!is.null(gaze_rows) && nrow(gaze_rows) > 0) {
    gr <- scale_screen_dt(gaze_rows, frame_width, frame_height, screen_width, screen_height)
    gr <- gr[is.finite(gaze_x) & is.finite(gaze_y)]
    if (nrow(gr) > 0) {
      data.table::setorder(gr, time_ms)
      gr[, order_id := seq_len(.N)]
      p <- p +
        ggplot2::geom_path(data = gr, ggplot2::aes(x = gaze_x, y = gaze_y), linewidth = 0.6, alpha = 0.75, inherit.aes = FALSE) +
        ggplot2::geom_point(data = gr, ggplot2::aes(x = gaze_x, y = gaze_y), size = 1.5, alpha = 0.85, inherit.aes = FALSE)
    }
  }
  p
}

.daoi_default_ffmpeg <- function() {
  local_ffmpeg <- "D:/Tools/ffmpeg/bin/ffmpeg.exe"
  if (file.exists(local_ffmpeg)) local_ffmpeg else "ffmpeg"
}

.daoi_apply_aoi_offset <- function(aoi, offset_ms = 0) {
  out <- data.table::copy(data.table::as.data.table(aoi))
  offset_ms <- suppressWarnings(as.numeric(offset_ms %||% 0))
  if (!is.finite(offset_ms)) offset_ms <- 0
  for (nm in intersect(c("time_ms", "start_ms", "end_ms"), names(out))) {
    data.table::set(out, j = nm, value = as.numeric(out[[nm]]) + offset_ms)
  }
  data.table::set(out, j = "aoi_video_offset_ms", value = offset_ms)
  out
}

.daoi_auto_gaze_offset <- function(gaze, current_offset = 0, force = FALSE) {
  gaze <- .daoi_table(gaze)
  times <- gaze$time_ms[is.finite(gaze$time_ms)]
  if (!length(times)) return(as.numeric(current_offset %||% 0))
  first_time <- min(times)
  if (isTRUE(force) || first_time > 1e6) first_time else as.numeric(current_offset %||% 0)
}

.daoi_prepare_video <- function(source, target, ffmpeg_path = .daoi_default_ffmpeg()) {
  copied <- file.copy(source, target, overwrite = TRUE)
  if (!isTRUE(copied) || tolower(tools::file_ext(target)) != "mp4") return(target)
  fast_target <- file.path(dirname(target), paste0(tools::file_path_sans_ext(basename(target)), "_faststart.mp4"))
  args <- c("-y", "-i", normalizePath(target, winslash = "/"), "-c", "copy", "-movflags", "+faststart", normalizePath(fast_target, winslash = "/", mustWork = FALSE))
  try(suppressWarnings(system2(ffmpeg_path, args = args, stdout = FALSE, stderr = FALSE)), silent = TRUE)
  if (file.exists(fast_target) && file.info(fast_target)$size > 0) fast_target else target
}

dynamic_aoi_validator_module_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::fluidRow(
    shiny::column(4,
      shiny::fileInput(ns("video_file"), "上传录屏视频（MP4/MOV/AVI/MKV）", accept = c(".mp4", ".mov", ".avi", ".mkv")),
      shiny::fileInput(ns("aoi_file"), "上传 UE 动态 AOI CSV", accept = c(".csv", ".txt")),
      shiny::fileInput(ns("gaze_file"), "可选：上传眼动 ASC 或 gaze CSV", accept = c(".asc", ".csv", ".txt")),
      shiny::selectInput(ns("experiment_filter"), "实验", choices = c("All" = ""), selected = ""),
      shiny::selectInput(ns("condition_filter"), "条件", choices = c("All" = ""), selected = ""),
      shiny::selectInput(ns("trial_filter"), "Trial", choices = c("All" = ""), selected = ""),
      shiny::selectInput(ns("scope_filter"), "AOI Scope", choices = c("All" = ""), selected = "", multiple = TRUE),
      shiny::selectInput(ns("segment_filter"), "加载段", choices = c("All" = ""), selected = ""),
      shiny::selectInput(ns("aoi_time_unit"), "AOI 时间单位", choices = c("毫秒 ms" = "ms", "秒 sec" = "sec"), selected = "ms"),
      shiny::selectInput(ns("gaze_time_unit"), "眼动 CSV 时间单位", choices = c("毫秒 ms" = "ms", "秒 sec" = "sec"), selected = "ms"),
      shiny::checkboxInput(ns("auto_gaze_offset"), "自动将绝对眼动时间对齐到视频起点", value = TRUE),
      shiny::numericInput(ns("gaze_offset_ms"), "眼动时间偏移 / ms", value = 0, step = 10),
      shiny::numericInput(ns("aoi_video_offset_ms"), "AOI 视频时间偏移 / ms", value = 0, step = 50),
      shiny::helpText("AOI 框比画面慢时填写负值；框比画面快时填写正值。"),
      shiny::numericInput(ns("aoi_offset_x"), "AOI 整体水平偏移 / px", value = 0, step = 5),
      shiny::numericInput(ns("aoi_offset_y"), "AOI 整体垂直偏移 / px", value = 0, step = 5),
      shiny::numericInput(ns("aoi_scale_x"), "AOI 横向缩放 / %", value = 100, min = 1, step = 1),
      shiny::numericInput(ns("aoi_scale_y"), "AOI 纵向缩放 / %", value = 100, min = 1, step = 1),
      shiny::helpText("偏移以原始录屏像素计算；缩放以画面中心为基准。"),
      shiny::numericInput(ns("screen_width"), "录屏坐标宽度", value = 1920, min = 1),
      shiny::numericInput(ns("screen_height"), "录屏坐标高度", value = 1080, min = 1),
      shiny::numericInput(ns("nearest_aoi_ms"), "AOI 最近帧容差 / ms", value = 120, min = 1, step = 10),
      shiny::numericInput(ns("gaze_window_ms"), "叠加眼动窗口 ±ms", value = 120, min = 1, step = 10),
      shiny::checkboxInput(ns("valid_only"), "只显示有效 AOI", value = TRUE),
      shiny::actionButton(ns("run_check"), "读取并开始动态验证", class = "btn-primary"),
      shiny::downloadButton(ns("download_segments"), "下载加载段"),
      shiny::downloadButton(ns("download_quality"), "下载 AOI 质量"),
      shiny::downloadButton(ns("download_hits"), "下载 gaze × AOI 明细"),
      shiny::downloadButton(ns("download_hit_summary"), "下载 gaze × AOI 汇总"),
      shiny::verbatimTextOutput(ns("status"))
    ),
    shiny::column(8,
      shiny::uiOutput(ns("dynamic_video_player")),
      shiny::h4("AOI 有效性"),
      DT::DTOutput(ns("quality_tbl")),
      shiny::h4("无效 / 风险 AOI"),
      DT::DTOutput(ns("invalid_tbl"))
    )
  )
}

dynamic_aoi_validator_module_server <- function(id, package_reactive = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    aoi_raw_rv <- shiny::reactiveVal(data.table::data.table())
    aoi_rv <- shiny::reactiveVal(data.table::data.table())
    gaze_raw_rv <- shiny::reactiveVal(data.table::data.table())
    gaze_rv <- shiny::reactiveVal(data.table::data.table())
    segments_rv <- shiny::reactiveVal(data.table::data.table())
    quality_rv <- shiny::reactiveVal(list(summary = data.table::data.table(), invalid_rows = data.table::data.table(), gaps = data.table::data.table()))
    video_url_rv <- shiny::reactiveVal(NULL)
    video_dir <- file.path(tempdir(), paste0("dynamic_aoi_video_", as.integer(stats::runif(1, 1, 1e9))))
    dir.create(video_dir, recursive = TRUE, showWarnings = FALSE)
    video_prefix <- paste0("dynamic-aoi-video-", as.integer(stats::runif(1, 1, 1e9)))
    shiny::addResourcePath(video_prefix, video_dir)

    filtered_aoi <- shiny::reactive({
      out <- .daoi_table(aoi_rv())
      if (!nrow(out)) return(out)
      if (nzchar(input$experiment_filter %||% "")) out <- out[experiment_code == input$experiment_filter]
      if (nzchar(input$condition_filter %||% "")) out <- out[condition == input$condition_filter]
      if (nzchar(input$trial_filter %||% "")) out <- out[trial_id == input$trial_filter]
      scopes <- input$scope_filter %||% ""
      scopes <- scopes[nzchar(scopes)]
      if (length(scopes) > 0) out <- out[aoi_scope %in% scopes]
      if (nzchar(input$segment_filter %||% "")) {
        seg <- .daoi_table(segments_rv())
        if (nrow(seg) > 0 && "segment_id" %in% names(seg)) seg <- seg[segment_id == input$segment_filter]
        if (nrow(seg) > 0) out <- out[
          participant == seg$participant[[1]] & trial_id == seg$trial_id[[1]] &
          experiment_code == seg$experiment_code[[1]] & condition == seg$condition[[1]] & phase == seg$phase[[1]]
        ]
      }
      out[]
    })

    gaze_hits <- shiny::reactive(compute_dynamic_gaze_aoi_hits(filtered_aoi(), gaze_rv()))

    rebuild_aoi <- function() {
      raw <- .daoi_table(aoi_raw_rv())
      if (!nrow(raw)) return(invisible(NULL))
      adjusted <- .daoi_apply_aoi_offset(raw, input$aoi_video_offset_ms)
      quality <- validate_dynamic_aoi(adjusted, screen_width = input$screen_width, screen_height = input$screen_height)
      rows <- .daoi_table(quality$rows %||% adjusted)
      aoi_rv(rows)
      quality_rv(quality)
      invisible(rows)
    }

    rebuild_gaze <- function() {
      gaze <- .daoi_table(gaze_raw_rv())
      if (nrow(gaze) > 0) data.table::set(gaze, j = "video_time_ms", value = gaze$time_ms - (input$gaze_offset_ms %||% 0))
      gaze_rv(gaze)
      invisible(gaze)
    }

    write_player_rows <- function(dt, file_name, columns) {
      out <- .daoi_table(dt)
      keep <- intersect(columns, names(out))
      out <- out[, ..keep]
      target <- file.path(video_dir, file_name)
      con <- file(target, open = "wb")
      on.exit(close(con), add = TRUE)
      jsonlite::stream_out(as.data.frame(out), con, verbose = FALSE)
      paste0("/", video_prefix, "/", file_name)
    }

    send_player_data <- function() {
      shiny::isolate({
        gaze <- data.table::copy(gaze_rv())
        if (nrow(gaze) > 100000) gaze <- gaze[unique(round(seq(1, .N, length.out = 100000)))]
        aoi_url <- write_player_rows(
          filtered_aoi(),
          "dynamic-aoi.ndjson",
          c("experiment_code", "condition", "trial_id", "aoi_scope", "aoi_group_id", "aoi_name", "shape_id", "time_ms", "start_ms", "end_ms", "x_min", "y_min", "x_max", "y_max", "valid_aoi")
        )
        gaze_url <- write_player_rows(
          gaze,
          "dynamic-gaze.ndjson",
          c("video_time_ms", "gaze_x", "gaze_y")
        )
        session$sendCustomMessage("dynamic-aoi-player-data", list(
          id = ns("player"),
          videoId = ns("video"),
          canvasId = ns("canvas"),
          statusId = ns("time"),
          aoiUrl = aoi_url,
          gazeUrl = gaze_url,
          screenWidth = input$screen_width %||% 1920,
          screenHeight = input$screen_height %||% 1080,
          aoiOffsetX = input$aoi_offset_x %||% 0,
          aoiOffsetY = input$aoi_offset_y %||% 0,
          aoiScaleX = input$aoi_scale_x %||% 100,
          aoiScaleY = input$aoi_scale_y %||% 100,
          seekId = ns("seek"),
          backId = ns("back"),
          forwardId = ns("forward"),
          nearestMs = input$nearest_aoi_ms %||% 120,
          gazeWindowMs = input$gaze_window_ms %||% 120,
          validOnly = isTRUE(input$valid_only)
        ))
      })
    }

    output$dynamic_video_player <- shiny::renderUI({
      video_url <- video_url_rv()
      if (is.null(video_url)) return(shiny::helpText("上传录屏视频与动态 AOI CSV 后，视频会在这里连续播放并实时绘制 AOI。"))
      shiny::tagList(
        shiny::tags$div(style = "position:relative; width:100%; background:#111; line-height:0;",
          shiny::tags$video(id = ns("video"), src = video_url, controls = NA, preload = "auto", style = "display:block; width:100%; height:auto; max-height:72vh;"),
          shiny::tags$canvas(id = ns("canvas"), style = "position:absolute; inset:0; width:100%; height:100%; pointer-events:none;")
        ),
        shiny::tags$div(class = "dynamic-aoi-seek-controls",
          shiny::tags$button(id = ns("back"), type = "button", class = "btn btn-default", title = "后退 5 秒", "\u23ea"),
          shiny::tags$input(id = ns("seek"), type = "range", min = "0", max = "1", step = "0.01", value = "0"),
          shiny::tags$button(id = ns("forward"), type = "button", class = "btn btn-default", title = "前进 5 秒", "\u23e9")
        ),
        shiny::tags$p(shiny::tags$b("当前视频时间："), shiny::tags$span(id = ns("time"), "0 ms"))
      )
    })

    shiny::observeEvent(input$run_check, {
      shiny::req(input$aoi_file, input$video_file)
      aoi <- read_dynamic_aoi_csv(input$aoi_file$datapath, time_unit = input$aoi_time_unit, source_file = input$aoi_file$name)
      aoi_raw_rv(aoi)
      rebuild_aoi()
      segments <- build_dynamic_aoi_segments(aoi)
      segments_rv(segments)
      shiny::updateSelectInput(session, "experiment_filter", choices = c("All" = "", sort(unique(aoi$experiment_code[nzchar(aoi$experiment_code)]))))
      shiny::updateSelectInput(session, "condition_filter", choices = c("All" = "", sort(unique(aoi$condition[nzchar(aoi$condition)]))))
      shiny::updateSelectInput(session, "trial_filter", choices = c("All" = "", sort(unique(aoi$trial_id[nzchar(aoi$trial_id)]))))
      shiny::updateSelectInput(session, "scope_filter", choices = c("All" = "", sort(unique(aoi$aoi_scope[nzchar(aoi$aoi_scope)]))))
      segment_choices <- if (nrow(segments) > 0) stats::setNames(segments$segment_id, segments$segment_label) else character()
      shiny::updateSelectInput(session, "segment_filter", choices = c("All" = "", segment_choices))
      if (!is.null(input$gaze_file)) {
        gaze <- read_gaze_table(input$gaze_file$datapath, time_unit = input$gaze_time_unit, source_file = input$gaze_file$name)
        gaze_raw_rv(gaze)
        if (isTRUE(input$auto_gaze_offset)) {
          auto_offset <- .daoi_auto_gaze_offset(gaze, input$gaze_offset_ms, force = tolower(tools::file_ext(input$gaze_file$name)) == "asc")
          shiny::updateNumericInput(session, "gaze_offset_ms", value = auto_offset)
          if (nrow(gaze) > 0) data.table::set(gaze, j = "video_time_ms", value = gaze$time_ms - auto_offset)
          gaze_rv(gaze)
          session$sendCustomMessage("dynamic-aoi-player-notice", list(id = ns("player"), text = sprintf("眼动时间已自动对齐：减去 %.0f ms", auto_offset)))
        } else {
          rebuild_gaze()
        }
      } else {
        gaze_raw_rv(data.table::data.table())
        gaze_rv(data.table::data.table())
      }
      ext <- tools::file_ext(input$video_file$name)
      target <- file.path(video_dir, paste0("video", if (nzchar(ext)) paste0(".", ext) else ""))
      prepared <- .daoi_prepare_video(input$video_file$datapath, target)
      video_url_rv(paste0("/", video_prefix, "/", utils::URLencode(basename(prepared), reserved = TRUE)))
      later::later(send_player_data, delay = 0.3)
      shiny::showNotification("动态 AOI 视频验证已加载。", type = "message")
    })

    if (!is.null(package_reactive)) shiny::observeEvent(package_reactive(), {
      pkg <- package_reactive()
      if (is.null(pkg) || is.null(pkg$dynamic_aoi) || nrow(pkg$dynamic_aoi) == 0) return()
      aoi <- standardize_dynamic_aoi(pkg$dynamic_aoi, time_unit = "ms", source_file = "formal_package_dynamic_aoi.csv")
      aoi_raw_rv(aoi)
      rebuild_aoi()
      segments <- build_dynamic_aoi_segments(aoi)
      segments_rv(segments)
      shiny::updateSelectInput(session, "experiment_filter", choices = c("All" = "", sort(unique(aoi$experiment_code[nzchar(aoi$experiment_code)]))))
      shiny::updateSelectInput(session, "condition_filter", choices = c("All" = "", sort(unique(aoi$condition[nzchar(aoi$condition)]))))
      shiny::updateSelectInput(session, "trial_filter", choices = c("All" = "", sort(unique(aoi$trial_id[nzchar(aoi$trial_id)]))))
      shiny::updateSelectInput(session, "scope_filter", choices = c("All" = "", sort(unique(aoi$aoi_scope[nzchar(aoi$aoi_scope)]))))
      segment_choices <- if (nrow(segments) > 0) stats::setNames(segments$segment_id, segments$segment_label) else character()
      shiny::updateSelectInput(session, "segment_filter", choices = c("All" = "", segment_choices))
      gaze <- .daoi_table(pkg$parsed$samples)
      if (nrow(gaze) > 0) {
        data.table::setnames(gaze, intersect(c("time", "gaze_x", "gaze_y", "pupil", "valid_gaze"), names(gaze)),
          intersect(c("time_ms", "gaze_x", "gaze_y", "pupil", "valid_gaze"), c("time_ms", "gaze_x", "gaze_y", "pupil", "valid_gaze")))
        gaze <- gaze[, .(time_ms, gaze_x, gaze_y, pupil, valid_gaze)]
        gaze_raw_rv(gaze)
        auto_offset <- .daoi_auto_gaze_offset(gaze, 0, force = TRUE)
        shiny::updateNumericInput(session, "gaze_offset_ms", value = auto_offset)
        gaze[, video_time_ms := time_ms - auto_offset]
        gaze_rv(gaze)
      }
      video_rows <- pkg$inventory[type == "screen_recording"]
      if (nrow(video_rows) > 0) {
        source <- file.path(pkg$root, video_rows$relative_path[[1]])
        ext <- tools::file_ext(source)
        target <- file.path(video_dir, paste0("formal_package_video", if (nzchar(ext)) paste0(".", ext) else ""))
        prepared <- .daoi_prepare_video(source, target)
        video_url_rv(paste0("/", video_prefix, "/", utils::URLencode(basename(prepared), reserved = TRUE)))
      }
      later::later(send_player_data, delay = 0.3)
      shiny::showNotification("正式数据包已自动载入动态 AOI 验证页。", type = "message")
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$aoi_video_offset_ms, {
      if (nrow(.daoi_table(aoi_raw_rv())) > 0) {
        rebuild_aoi()
        send_player_data()
      }
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$gaze_offset_ms, {
      if (nrow(.daoi_table(gaze_raw_rv())) > 0) {
        rebuild_gaze()
        send_player_data()
      }
    }, ignoreInit = TRUE)

    shiny::observeEvent(input$segment_filter, {
      seg <- .daoi_table(segments_rv())
      if (nrow(seg) > 0 && "segment_id" %in% names(seg)) seg <- seg[segment_id == input$segment_filter]
      if (nrow(seg) > 0 && is.finite(seg$start_ms[[1]])) {
        session$sendCustomMessage("dynamic-aoi-player-seek", list(id = ns("player"), timeMs = seg$start_ms[[1]] + (input$aoi_video_offset_ms %||% 0)))
      }
    }, ignoreInit = TRUE)

    shiny::observeEvent(list(
      input$screen_width, input$screen_height,
      input$aoi_offset_x, input$aoi_offset_y, input$aoi_scale_x, input$aoi_scale_y,
      input$nearest_aoi_ms, input$gaze_window_ms, input$valid_only,
      input$experiment_filter, input$condition_filter, input$trial_filter, input$scope_filter, input$segment_filter
    ), {
      if (nrow(.daoi_table(aoi_raw_rv())) > 0) rebuild_aoi()
      if (nrow(.daoi_table(aoi_rv())) > 0) send_player_data()
    }, ignoreInit = TRUE)

    output$status <- shiny::renderPrint({
      cat("AOI rows:", nrow(.daoi_table(aoi_rv())), "\n")
      cat("Displayed AOI rows:", nrow(filtered_aoi()), "\n")
      cat("Dynamic loading segments:", nrow(.daoi_table(segments_rv())), "\n")
      cat("AOI video offset ms:", input$aoi_video_offset_ms %||% 0, "\n")
      cat("AOI spatial adjustment:", sprintf("x=%s px, y=%s px, scale=%s%% x %s%%", input$aoi_offset_x %||% 0, input$aoi_offset_y %||% 0, input$aoi_scale_x %||% 100, input$aoi_scale_y %||% 100), "\n")
      cat("Gaze rows:", nrow(.daoi_table(gaze_rv())), "\n")
      gaze <- .daoi_table(gaze_rv())
      if (nrow(gaze) > 0 && "video_time_ms" %in% names(gaze)) cat("Gaze video-time range ms:", paste(round(range(gaze$video_time_ms, na.rm = TRUE)), collapse = " to "), "\n")
      aoi <- filtered_aoi()
      if (nrow(aoi) > 0) cat("AOI video-time range ms:", paste(round(range(aoi$time_ms, na.rm = TRUE)), collapse = " to "), "\n")
      cat("Video loaded:", !is.null(video_url_rv()), "\n")
    })
    output$quality_tbl <- DT::renderDT(DT::datatable(quality_rv()$summary, filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 6)))
    output$invalid_tbl <- DT::renderDT({
      invalid <- quality_rv()$invalid_rows
      if (nrow(invalid) > 5000) invalid <- head(invalid, 5000)
      DT::datatable(invalid, filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 6))
    })
    output$download_segments <- shiny::downloadHandler(
      filename = function() "dynamic_aoi_segments.csv",
      content = function(file) data.table::fwrite(segments_rv(), file)
    )
    output$download_quality <- shiny::downloadHandler(
      filename = function() "dynamic_aoi_quality.csv",
      content = function(file) data.table::fwrite(quality_rv()$summary, file)
    )
    output$download_hits <- shiny::downloadHandler(
      filename = function() "dynamic_gaze_aoi_hits.csv",
      content = function(file) data.table::fwrite(gaze_hits()$hits, file)
    )
    output$download_hit_summary <- shiny::downloadHandler(
      filename = function() "dynamic_gaze_aoi_summary.csv",
      content = function(file) data.table::fwrite(gaze_hits()$summary, file)
    )
  })
}

# Lightweight standalone Shiny app.
dynamic_aoi_validator_app <- function() {
  .daoi_need_pkg("shiny")
  .daoi_need_pkg("DT")
  .daoi_need_pkg("data.table")
  .daoi_need_pkg("ggplot2")

  ui <- shiny::fluidPage(
    shiny::tags$head(shiny::tags$script(src = "dynamic-aoi-player.js?v=20260610-blob-seek")),
    shiny::titlePanel("动态 AOI 录屏验证 / Dynamic AOI Video Validator"),
    shiny::sidebarLayout(
      shiny::sidebarPanel(
        shiny::fileInput("video_file", "上传录屏视频（MP4/MOV/AVI/MKV）", accept = c(".mp4", ".mov", ".avi", ".mkv")),
        shiny::fileInput("aoi_file", "上传 UE 动态 AOI CSV", accept = c(".csv", ".txt")),
        shiny::fileInput("gaze_file", "可选：上传眼动 ASC 或 gaze CSV", accept = c(".asc", ".csv", ".txt")),
        shiny::selectInput("aoi_time_unit", "AOI 时间单位", choices = c("毫秒 ms" = "ms", "秒 sec" = "sec"), selected = "ms"),
        shiny::selectInput("gaze_time_unit", "眼动 CSV 时间单位", choices = c("毫秒 ms" = "ms", "秒 sec" = "sec"), selected = "ms"),
        shiny::numericInput("gaze_offset_ms", "眼动时间偏移：gaze_time - offset = video_rel_ms", value = 0, step = 10),
        shiny::numericInput("screen_width", "UE 录屏坐标宽度", value = 1920, min = 1),
        shiny::numericInput("screen_height", "UE 录屏坐标高度", value = 1080, min = 1),
        shiny::numericInput("frame_interval_ms", "抽帧间隔 / ms", value = 1000, min = 100, step = 100),
        shiny::numericInput("max_frames", "最多抽帧数", value = 20, min = 1, max = 200),
        shiny::numericInput("gaze_window_ms", "叠加眼动窗口 ±ms", value = 120, min = 1, step = 10),
        shiny::numericInput("nearest_aoi_ms", "无时间窗时 AOI 最近帧容差 / ms", value = 120, min = 1, step = 10),
        shiny::textInput("ffmpeg_path", "ffmpeg 路径", value = .daoi_default_ffmpeg()),
        shiny::checkboxInput("valid_only", "预览时只显示有效 AOI（projection_valid=1 且未 clamped）", value = TRUE),
        shiny::actionButton("run_check", "读取并抽帧验证", class = "btn-primary"),
        shiny::hr(),
        shiny::downloadButton("download_aoi_quality", "下载 AOI 有效性报告 CSV"),
        shiny::downloadButton("download_overlay_png", "下载当前叠加图 PNG")
      ),
      shiny::mainPanel(
        shiny::tabsetPanel(
          shiny::tabPanel("状态", shiny::br(), shiny::verbatimTextOutput("status")),
          shiny::tabPanel("AOI 有效性", shiny::br(), DT::DTOutput("quality_tbl"), shiny::h4("无效 / 风险 AOI 行"), DT::DTOutput("invalid_tbl"), shiny::h4("有效 AOI 时间断点"), DT::DTOutput("gap_tbl")),
          shiny::tabPanel("动态视频预览", shiny::br(), shiny::uiOutput("dynamic_video_player")),
          shiny::tabPanel("录屏叠加预览", shiny::br(), shiny::selectInput("frame_select", "预览帧", choices = character()), shiny::plotOutput("overlay_plot", height = 650)),
          shiny::tabPanel("标准化 AOI", shiny::br(), DT::DTOutput("aoi_tbl")),
          shiny::tabPanel("眼动数据", shiny::br(), shiny::helpText("未上传眼动文件也可以完成 AOI 验证。上传后会在预览图中叠加 gaze 轨迹。"), DT::DTOutput("gaze_tbl"))
        )
      )
    )
  )

  server <- function(input, output, session) {
    aoi_rv <- shiny::reactiveVal(data.table::data.table())
    quality_rv <- shiny::reactiveVal(list(summary = data.table::data.table(), invalid_rows = data.table::data.table(), gaps = data.table::data.table()))
    gaze_rv <- shiny::reactiveVal(data.table::data.table())
    frames_rv <- shiny::reactiveVal(data.table::data.table())
    last_plot_rv <- shiny::reactiveVal(NULL)
    video_url_rv <- shiny::reactiveVal(NULL)
    video_dir <- file.path(tempdir(), paste0("dynamic_aoi_video_", as.integer(stats::runif(1, 1, 1e9))))
    dir.create(video_dir, recursive = TRUE, showWarnings = FALSE)
    video_prefix <- paste0("dynamic-aoi-video-", as.integer(stats::runif(1, 1, 1e9)))
    shiny::addResourcePath(video_prefix, video_dir)

    write_player_rows <- function(dt, file_name, columns) {
      out <- data.table::copy(data.table::as.data.table(dt))
      keep <- intersect(columns, names(out))
      out <- out[, ..keep]
      target <- file.path(video_dir, file_name)
      con <- file(target, open = "wb")
      on.exit(close(con), add = TRUE)
      jsonlite::stream_out(as.data.frame(out), con, verbose = FALSE)
      paste0("/", video_prefix, "/", file_name)
    }

    send_player_data <- function() {
      shiny::isolate({
        gaze <- data.table::copy(gaze_rv())
        if (nrow(gaze) > 100000) gaze <- gaze[unique(round(seq(1, .N, length.out = 100000)))]
        aoi_url <- write_player_rows(
          aoi_rv(), "dynamic-aoi.ndjson",
          c("aoi_group_id", "aoi_name", "shape_id", "time_ms", "start_ms", "end_ms", "x_min", "y_min", "x_max", "y_max", "valid_aoi")
        )
        gaze_url <- write_player_rows(gaze, "dynamic-gaze.ndjson", c("video_time_ms", "gaze_x", "gaze_y"))
        session$sendCustomMessage("dynamic-aoi-player-data", list(
          id = "dynamic-aoi-player",
          videoId = "dynamic_aoi_video",
          canvasId = "dynamic_aoi_canvas",
          statusId = "dynamic_aoi_time",
          aoiUrl = aoi_url,
          gazeUrl = gaze_url,
          screenWidth = input$screen_width %||% 1920,
          screenHeight = input$screen_height %||% 1080,
          nearestMs = input$nearest_aoi_ms %||% 120,
          gazeWindowMs = input$gaze_window_ms %||% 120,
          validOnly = isTRUE(input$valid_only)
        ))
      })
    }

    output$dynamic_video_player <- shiny::renderUI({
      video_url <- video_url_rv()
      if (is.null(video_url)) {
        return(shiny::helpText("上传录屏视频和动态 AOI CSV，然后点击“读取并抽帧验证”。视频会在此处连续播放并实时叠加 AOI。"))
      }
      shiny::tagList(
        shiny::tags$div(
          style = "position:relative; width:100%; background:#111; line-height:0;",
          shiny::tags$video(
            id = "dynamic_aoi_video", src = video_url, controls = NA, preload = "metadata",
            style = "display:block; width:100%; height:auto; max-height:72vh;"
          ),
          shiny::tags$canvas(
            id = "dynamic_aoi_canvas",
            style = "position:absolute; inset:0; width:100%; height:100%; pointer-events:none;"
          )
        ),
        shiny::tags$p(shiny::tags$b("当前视频时间："), shiny::tags$span(id = "dynamic_aoi_time", "0 ms"))
      )
    })

    shiny::observeEvent(input$run_check, {
      shiny::req(input$aoi_file)
      aoi <- read_dynamic_aoi_csv(input$aoi_file$datapath, time_unit = input$aoi_time_unit, source_file = input$aoi_file$name)
      q <- validate_dynamic_aoi(aoi, screen_width = input$screen_width, screen_height = input$screen_height)
      aoi_rv(aoi)
      quality_rv(q)

      if (!is.null(input$gaze_file)) {
        gaze <- tryCatch(read_gaze_table(input$gaze_file$datapath, time_unit = input$gaze_time_unit, source_file = input$gaze_file$name), error = function(e) {
          shiny::showNotification(paste("眼动文件读取失败：", conditionMessage(e)), type = "warning")
          data.table::data.table()
        })
        if (nrow(gaze) > 0) gaze[, video_time_ms := time_ms - input$gaze_offset_ms]
        gaze_rv(gaze)
      } else {
        gaze_rv(data.table::data.table())
      }

      if (!is.null(input$video_file)) {
        ext <- tools::file_ext(input$video_file$name)
        target <- file.path(video_dir, paste0("video", if (nzchar(ext)) paste0(".", ext) else ""))
        file.copy(input$video_file$datapath, target, overwrite = TRUE)
        video_url_rv(paste0("/", video_prefix, "/", utils::URLencode(basename(target), reserved = TRUE)))
      } else {
        video_url_rv(NULL)
      }

      frame_plan <- make_frame_plan(aoi, interval_ms = input$frame_interval_ms, max_frames = input$max_frames, valid_only = FALSE)
      if (!is.null(input$video_file) && nrow(frame_plan) > 0) {
        out_dir <- file.path(tempdir(), paste0("daoi_frames_", as.integer(Sys.time())))
        dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
        for (i in seq_len(nrow(frame_plan))) {
          out_file <- file.path(out_dir, sprintf("frame_%03d_%07dms.png", i, round(frame_plan$time_ms[i])))
          ok <- extract_video_frame_ffmpeg(input$video_file$datapath, frame_plan$time_sec[i], out_file, ffmpeg_path = input$ffmpeg_path)
          if (isTRUE(ok)) frame_plan$frame_file[i] <- out_file
        }
        frame_plan <- frame_plan[nzchar(frame_file) & file.exists(frame_file)]
      }
      frames_rv(frame_plan)
      labels <- if (nrow(frame_plan) > 0) stats::setNames(seq_len(nrow(frame_plan)), sprintf("%03d | %.0f ms", frame_plan$frame_id, frame_plan$time_ms)) else character()
      shiny::updateSelectInput(session, "frame_select", choices = labels, selected = if (length(labels) > 0) labels[[1]] else character())
      later::later(send_player_data, delay = 0.2)
      shiny::showNotification("动态 AOI 读取完成。没有上传眼动文件也可查看 AOI 有效性和录屏叠加。", type = "message")
    })

    shiny::observeEvent(list(input$screen_width, input$screen_height, input$nearest_aoi_ms, input$gaze_window_ms, input$valid_only), {
      if (nrow(aoi_rv()) > 0) send_player_data()
    }, ignoreInit = TRUE)

    selected_frame <- shiny::reactive({
      fr <- frames_rv()
      idx <- suppressWarnings(as.integer(input$frame_select))
      if (is.null(idx) || is.na(idx) || nrow(fr) < idx) return(fr[0])
      fr[idx]
    })

    current_overlay_plot <- shiny::reactive({
      fr <- selected_frame()
      if (nrow(fr) == 0 || !file.exists(fr$frame_file)) return(NULL)
      t <- fr$time_ms[1]
      ar <- select_aoi_at_time(aoi_rv(), t, max_nearest_gap_ms = input$nearest_aoi_ms, valid_only = isTRUE(input$valid_only))
      gz <- gaze_rv()
      if (nrow(gz) > 0 && "video_time_ms" %in% names(gz)) {
        gz <- gz[is.finite(video_time_ms) & abs(video_time_ms - t) <= input$gaze_window_ms]
        gz[, time_ms := video_time_ms]
      }
      plot_dynamic_aoi_frame(fr$frame_file[1], ar, gz, t, input$screen_width, input$screen_height,
        title = sprintf("AOI / gaze overlay | %.0f ms | AOI rows: %d | gaze points: %d", t, nrow(ar), nrow(gz)))
    })

    output$status <- shiny::renderPrint({
      cat("AOI rows:", nrow(aoi_rv()), "\n")
      cat("Gaze rows:", nrow(gaze_rv()), "\n")
      cat("Extracted frames:", nrow(frames_rv()), "\n")
      if (nrow(frames_rv()) == 0) cat("如未抽帧，请确认已上传视频且 ffmpeg 可用。AOI 有效性表仍可使用。\n")
    })
    output$quality_tbl <- DT::renderDT(DT::datatable(quality_rv()$summary, filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 12)))
    output$invalid_tbl <- DT::renderDT({
      invalid <- quality_rv()$invalid_rows
      if (nrow(invalid) > 5000) invalid <- head(invalid, 5000)
      DT::datatable(invalid, filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 12))
    })
    output$gap_tbl <- DT::renderDT(DT::datatable(quality_rv()$gaps, filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 12)))
    output$aoi_tbl <- DT::renderDT(DT::datatable(aoi_rv(), filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 12)))
    output$gaze_tbl <- DT::renderDT(DT::datatable(head(gaze_rv(), 1000), filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 12)))
    output$overlay_plot <- shiny::renderPlot({
      p <- current_overlay_plot()
      if (is.null(p)) {
        plot.new(); text(0.5, 0.5, "尚无叠加帧。请上传录屏视频、AOI CSV，并点击读取。")
      } else {
        last_plot_rv(p); print(p)
      }
    })
    output$download_aoi_quality <- shiny::downloadHandler(
      filename = function() sprintf("dynamic_aoi_quality_%s.csv", format(Sys.time(), "%Y%m%d_%H%M%S")),
      content = function(file) data.table::fwrite(quality_rv()$summary, file)
    )
    output$download_overlay_png <- shiny::downloadHandler(
      filename = function() sprintf("dynamic_aoi_overlay_%s.png", format(Sys.time(), "%Y%m%d_%H%M%S")),
      content = function(file) {
        p <- current_overlay_plot()
        if (is.null(p)) stop("No overlay plot available.", call. = FALSE)
        ggplot2::ggsave(file, p, width = 12, height = 7, dpi = 150)
      }
    )
  }
  shiny::shinyApp(ui, server)
}
