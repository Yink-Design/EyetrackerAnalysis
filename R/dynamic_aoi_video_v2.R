# Overrides for dynamic_aoi_video.R.
# This version prefers UE-generated video_time_start_ms / video_time_end_ms / time_ms,
# so AOI rows exported by Gallery v0.2.9.5 align directly to the screen recording timeline.

standardize_dynamic_aoi <- function(x, time_unit = c("ms", "sec"), source_file = "") {
  .daoi_need_pkg("data.table")
  time_unit <- match.arg(time_unit)
  if (is.null(x) || nrow(x) == 0) return(.daoi_empty())
  dt <- data.table::as.data.table(x)
  names(dt) <- .daoi_norm_names(names(dt))

  n <- nrow(dt)
  get_chr <- function(cands, default = "") {
    col <- .daoi_pick_col(dt, cands)
    if (is.na(col)) rep(default, n) else as.character(dt[[col]])
  }
  get_num <- function(cands, default = NA_real_) .daoi_as_num(.daoi_get(dt, cands, default))

  participant <- get_chr(c("participant", "participant_id", "subject", "subj", "pid"))
  trial_id <- get_chr(c("trial_id", "trial", "trialid", "out_trial", "trial_name"))
  condition <- get_chr(c("condition", "loading_condition", "applied_loading_condition", "strategy", "loading_strategy"))
  phase <- get_chr(c("phase", "phase_name"), "loading")
  aoi_group_id <- get_chr(c("aoi_group_id", "aoi_id", "aoi", "aoi_group", "name", "label"), "dynamic_aoi")
  aoi_name <- get_chr(c("aoi_name", "aoi_label", "display_name"), "Dynamic AOI")
  shape_id <- get_chr(c("shape_id", "id", "row_id", "frame_id"), "")
  reference_id <- get_chr(c("reference_id", "time_reference", "time_mode"), "")

  x_min <- get_num(c("x_min", "xmin", "min_x", "left", "screen_x_min", "aoi_x_min", "rect_x_min", "bbox_x_min"))
  y_min <- get_num(c("y_min", "ymin", "min_y", "top", "screen_y_min", "aoi_y_min", "rect_y_min", "bbox_y_min"))
  x_max <- get_num(c("x_max", "xmax", "max_x", "right", "screen_x_max", "aoi_x_max", "rect_x_max", "bbox_x_max"))
  y_max <- get_num(c("y_max", "ymax", "max_y", "bottom", "screen_y_max", "aoi_y_max", "rect_y_max", "bbox_y_max"))

  x <- get_num(c("x", "screen_x", "rect_x", "bbox_x"))
  y <- get_num(c("y", "screen_y", "rect_y", "bbox_y"))
  w <- get_num(c("width", "w", "screen_width", "rect_width", "bbox_width"))
  h <- get_num(c("height", "h", "screen_height", "rect_height", "bbox_height"))
  x_min <- ifelse(is.na(x_min) & is.finite(x), x, x_min)
  y_min <- ifelse(is.na(y_min) & is.finite(y), y, y_min)
  x_max <- ifelse(is.na(x_max) & is.finite(x_min) & is.finite(w), x_min + w, x_max)
  y_max <- ifelse(is.na(y_max) & is.finite(y_min) & is.finite(h), y_min + h, y_max)

  # New Gallery AOI CSV columns are already video-relative.
  start_ms <- get_num(c("video_time_start_ms", "video_start_ms", "start_ms", "recording_start_ms", "screen_recording_start_ms", "rel_start_ms", "relative_start_ms", "time_start_ms", "aoi_start_ms", "frame_start_ms", "start_time_ms"))
  end_ms <- get_num(c("video_time_end_ms", "video_end_ms", "end_ms", "recording_end_ms", "screen_recording_end_ms", "rel_end_ms", "relative_end_ms", "time_end_ms", "aoi_end_ms", "frame_end_ms", "end_time_ms"))
  time_ms <- get_num(c("time_ms", "video_time_ms", "recording_time_ms", "screen_recording_time_ms", "video_time_mid_ms", "rel_ms", "relative_ms", "relative_time_ms", "timestamp_ms", "elapsed_ms", "frame_time_ms", "time"))
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

  out <- data.table::data.table(
    row_id = seq_len(n), participant = participant, trial_id = trial_id, condition = condition, phase = phase,
    aoi_group_id = aoi_group_id, aoi_name = aoi_name, shape_id = ifelse(nzchar(shape_id), shape_id, paste0("row_", seq_len(n))),
    reference_id = reference_id,
    time_ms = time_ms, start_ms = start_ms, end_ms = end_ms,
    x_min = x_min, y_min = y_min, x_max = x_max, y_max = y_max,
    projection_valid = projection_valid, is_clamped = is_clamped, enabled = enabled, visible = visible,
    source_file = source_file
  )
  for (nm in c("participant", "trial_id", "condition", "phase", "aoi_group_id", "aoi_name", "shape_id", "reference_id", "source_file")) {
    out[[nm]][is.na(out[[nm]])] <- ""
  }
  out[, `:=`(
    width = abs(x_max - x_min),
    height = abs(y_max - y_min),
    area = abs(x_max - x_min) * abs(y_max - y_min)
  )]
  out[, invalid_reason := ""]
  out[enabled != TRUE, invalid_reason := paste0(invalid_reason, ";disabled")]
  out[visible != TRUE, invalid_reason := paste0(invalid_reason, ";hidden")]
  out[projection_valid != TRUE, invalid_reason := paste0(invalid_reason, ";projection_invalid")]
  out[is_clamped == TRUE, invalid_reason := paste0(invalid_reason, ";clamped")]
  out[!is.finite(x_min) | !is.finite(y_min) | !is.finite(x_max) | !is.finite(y_max), invalid_reason := paste0(invalid_reason, ";missing_coordinates")]
  out[is.finite(width) & is.finite(height) & (width <= 0 | height <= 0), invalid_reason := paste0(invalid_reason, ";non_positive_area")]
  out[, invalid_reason := sub("^;", "", invalid_reason)]
  out[, valid_aoi := invalid_reason == ""]
  out[]
}
