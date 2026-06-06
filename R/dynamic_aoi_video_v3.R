# Overrides for dynamic_aoi_video.R / v2.
# Fixes:
# 1) partially visible / clamped AOI rows remain valid if they still intersect the viewport;
# 2) select_aoi_at_time no longer shadows the time_ms column, avoiding historical boxes drawn on one video frame.

validate_dynamic_aoi <- function(aoi, screen_width = 1920, screen_height = 1080, gap_threshold_ms = 250) {
  .daoi_need_pkg("data.table")
  aoi <- data.table::copy(data.table::as.data.table(aoi))
  if (nrow(aoi) == 0) {
    return(list(summary = data.table::data.table(), invalid_rows = data.table::data.table(), gaps = data.table::data.table()))
  }
  if (!"invalid_reason" %in% names(aoi)) aoi[, invalid_reason := ""]

  # Rebuild validity from first principles. Clamping means "partially clipped to the screen";
  # it should be a warning, not an automatic invalidation. A half-visible B card is still an AOI.
  aoi[, invalid_reason := ""]
  aoi[enabled != TRUE, invalid_reason := paste0(invalid_reason, ";disabled")]
  aoi[visible != TRUE, invalid_reason := paste0(invalid_reason, ";hidden")]
  aoi[projection_valid != TRUE, invalid_reason := paste0(invalid_reason, ";projection_invalid")]
  aoi[!is.finite(x_min) | !is.finite(y_min) | !is.finite(x_max) | !is.finite(y_max), invalid_reason := paste0(invalid_reason, ";missing_coordinates")]

  aoi[, `:=`(
    width = abs(as.numeric(x_max) - as.numeric(x_min)),
    height = abs(as.numeric(y_max) - as.numeric(y_min))
  )]
  aoi[, area := width * height]
  aoi[is.finite(width) & is.finite(height) & (width <= 0 | height <= 0), invalid_reason := paste0(invalid_reason, ";non_positive_area")]

  # Mark outside-screen only when the clipped rectangle has no intersection with the viewport.
  aoi[, intersects_screen := is.finite(x_min) & is.finite(y_min) & is.finite(x_max) & is.finite(y_max) &
      pmax(x_min, 0) < pmin(x_max, screen_width) &
      pmax(y_min, 0) < pmin(y_max, screen_height)]
  aoi[projection_valid == TRUE & intersects_screen != TRUE, invalid_reason := paste0(invalid_reason, ";outside_screen")]
  aoi[, invalid_reason := sub("^;", "", invalid_reason)]
  aoi[, valid_aoi := invalid_reason == ""]

  key_cols <- intersect(c("participant", "trial_id", "condition", "phase", "aoi_group_id"), names(aoi))
  if (length(key_cols) == 0) key_cols <- "aoi_group_id"
  summary <- aoi[, .(
    n_rows = .N,
    n_valid = sum(valid_aoi, na.rm = TRUE),
    n_projection_invalid = sum(grepl("projection_invalid", invalid_reason), na.rm = TRUE),
    n_clamped = sum(is_clamped == TRUE, na.rm = TRUE),
    n_clamped_valid = sum(is_clamped == TRUE & valid_aoi == TRUE, na.rm = TRUE),
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
  list(summary = summary[], invalid_rows = aoi[nzchar(invalid_reason)], gaps = gaps[])
}

select_aoi_at_time <- function(aoi, target_time_ms, max_nearest_gap_ms = 120, valid_only = FALSE) {
  .daoi_need_pkg("data.table")
  aoi <- data.table::as.data.table(aoi)
  if (nrow(aoi) == 0 || !is.finite(target_time_ms)) return(aoi[0])
  cand <- data.table::copy(aoi)
  if (isTRUE(valid_only) && "valid_aoi" %in% names(cand)) cand <- cand[valid_aoi == TRUE]
  if (nrow(cand) == 0) return(cand)

  # Prefer interval rows: target frame is inside [start_ms, end_ms).
  if (any(is.finite(cand$start_ms) & is.finite(cand$end_ms) & cand$end_ms > cand$start_ms)) {
    hit <- cand[is.finite(start_ms) & is.finite(end_ms) & target_time_ms >= start_ms & target_time_ms < end_ms]
    if (nrow(hit) > 0) return(hit[])
  }

  # Fallback to nearest point sample. Use target_time_ms explicitly; do not shadow the time_ms column.
  cand[, .dist := abs(as.numeric(get("time_ms")) - target_time_ms)]
  hit <- cand[is.finite(.dist) & .dist <= max_nearest_gap_ms]
  hit[, .dist := NULL]
  hit[]
}
