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
    row_id = integer(), participant = character(), trial_id = character(), condition = character(), phase = character(),
    aoi_group_id = character(), aoi_name = character(), shape_id = character(), time_ms = numeric(), start_ms = numeric(), end_ms = numeric(),
    x_min = numeric(), y_min = numeric(), x_max = numeric(), y_max = numeric(),
    projection_valid = logical(), is_clamped = logical(), enabled = logical(), visible = logical(), valid_aoi = logical(),
    invalid_reason = character(), source_file = character()
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
  dt <- data.table::as.data.table(x)
  original_names <- names(dt)
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

  start_ms <- get_num(c("start_ms", "rel_start_ms", "relative_start_ms", "time_start_ms", "aoi_start_ms", "frame_start_ms", "start_time_ms"))
  end_ms <- get_num(c("end_ms", "rel_end_ms", "relative_end_ms", "time_end_ms", "aoi_end_ms", "frame_end_ms", "end_time_ms"))
  time_ms <- get_num(c("time_ms", "rel_ms", "relative_ms", "relative_time_ms", "timestamp_ms", "video_time_ms", "elapsed_ms", "frame_time_ms", "time"))
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
    time_ms = time_ms, start_ms = start_ms, end_ms = end_ms,
    x_min = x_min, y_min = y_min, x_max = x_max, y_max = y_max,
    projection_valid = projection_valid, is_clamped = is_clamped, enabled = enabled, visible = visible,
    source_file = source_file
  )
  for (nm in c("participant", "trial_id", "condition", "phase", "aoi_group_id", "aoi_name", "shape_id", "source_file")) {
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

validate_dynamic_aoi <- function(aoi, screen_width = 1920, screen_height = 1080, gap_threshold_ms = 250) {
  .daoi_need_pkg("data.table")
  aoi <- data.table::copy(data.table::as.data.table(aoi))
  if (nrow(aoi) == 0) {
    return(list(summary = data.table::data.table(), invalid_rows = data.table::data.table(), gaps = data.table::data.table()))
  }
  aoi[, outside_screen := valid_aoi & (x_min < 0 | y_min < 0 | x_max > screen_width | y_max > screen_height)]
  aoi[outside_screen == TRUE, invalid_reason := ifelse(nzchar(invalid_reason), paste(invalid_reason, "outside_screen", sep = ";"), "outside_screen")]
  aoi[, valid_aoi := invalid_reason == ""]
  key_cols <- intersect(c("participant", "trial_id", "condition", "phase", "aoi_group_id"), names(aoi))
  if (length(key_cols) == 0) key_cols <- "aoi_group_id"
  summary <- aoi[, .(
    n_rows = .N,
    n_valid = sum(valid_aoi, na.rm = TRUE),
    n_projection_invalid = sum(grepl("projection_invalid", invalid_reason), na.rm = TRUE),
    n_clamped = sum(grepl("clamped", invalid_reason), na.rm = TRUE),
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
  names(dt) <- .daoi_norm_names(names(dt))
  n <- nrow(dt)
  get_num <- function(cands, default = NA_real_) .daoi_as_num(.daoi_get(dt, cands, default))
  time_ms <- get_num(c("time_ms", "time", "timestamp_ms", "rel_ms", "relative_time_ms", "video_time_ms", "elapsed_ms"))
  gaze_x <- get_num(c("gaze_x", "x", "gx", "screen_x", "fix_x", "CURRENT_FIX_X"))
  gaze_y <- get_num(c("gaze_y", "y", "gy", "screen_y", "fix_y", "CURRENT_FIX_Y"))
  pupil <- get_num(c("pupil", "pupil_area", "pa", "pupil_size"))
  if (time_unit == "sec") time_ms <- time_ms * 1000
  data.table::data.table(time_ms = time_ms, gaze_x = gaze_x, gaze_y = gaze_y, pupil = pupil,
    valid_gaze = is.finite(gaze_x) & is.finite(gaze_y), source_file = source_file)
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
  cand[, .dist := abs(time_ms - time_ms)]
  # The previous line is intentionally overwritten below to avoid NSE ambiguity.
  cand[, .dist := abs(get("time_ms") - time_ms)]
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
    ar[, label := ifelse(nzchar(aoi_name), aoi_name, aoi_group_id)]
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

# Lightweight standalone Shiny app.
dynamic_aoi_validator_app <- function() {
  .daoi_need_pkg("shiny")
  .daoi_need_pkg("DT")
  .daoi_need_pkg("data.table")
  .daoi_need_pkg("ggplot2")

  ui <- shiny::fluidPage(
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
        shiny::textInput("ffmpeg_path", "ffmpeg 路径", value = "ffmpeg"),
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
      shiny::showNotification("动态 AOI 读取完成。没有上传眼动文件也可查看 AOI 有效性和录屏叠加。", type = "message")
    })

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
    output$invalid_tbl <- DT::renderDT(DT::datatable(quality_rv()$invalid_rows, filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 12)))
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
