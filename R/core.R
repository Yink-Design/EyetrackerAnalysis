# Core functions for EyeLink ASC Analyzer CN

need_pkg <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop(sprintf("Package '%s' is required.", pkg), call. = FALSE)
}

as_num <- function(x) {
  x <- trimws(as.character(x)); x[x %in% c(".", "...", "", "NA", "NaN")] <- NA_character_
  suppressWarnings(as.numeric(x))
}

first_non_na <- function(x, default = NA) {
  x <- x[!is.na(x) & as.character(x) != ""]
  if (length(x) == 0) default else x[[1]]
}

safe_mean <- function(x) { x <- as.numeric(x); if (length(x) == 0 || all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE) }
safe_sum <- function(x) { x <- as.numeric(x); if (length(x) == 0 || all(is.na(x))) 0 else sum(x, na.rm = TRUE) }
safe_max <- function(x) { x <- as.numeric(x); if (length(x) == 0 || all(is.na(x))) NA_real_ else max(x, na.rm = TRUE) }

interval_overlaps <- function(event_start, event_end, window_start, window_end) {
  event_start < window_end & event_end > window_start
}

clip_interval <- function(event_start, event_end, window_start, window_end) {
  clipped_start <- pmax(event_start, window_start)
  clipped_end <- pmin(event_end, window_end)
  clipped_duration <- pmax(0, clipped_end - clipped_start)
  data.table::data.table(
    clipped_start = clipped_start,
    clipped_end = clipped_end,
    clipped_duration = clipped_duration,
    relative_start = clipped_start - window_start,
    relative_end = clipped_end - window_start
  )
}

apply_sample_validity <- function(samples, pupil_valid_requires_gaze = TRUE, pupil_min_value = 0) {
  need_pkg("data.table")
  if (is.null(samples) || nrow(samples) == 0) return(samples)
  dt <- data.table::copy(samples)
  dt[, valid_gaze := is.finite(gaze_x) & is.finite(gaze_y)]
  dt[, valid_pupil := is.finite(pupil) & pupil > pupil_min_value]
  dt[, valid_sample := if (isTRUE(pupil_valid_requires_gaze)) valid_gaze & valid_pupil else valid_pupil]
  dt
}

parse_kv <- function(text) {
  toks <- strsplit(text, "\\s+")[[1]]
  toks <- toks[grepl("^[A-Za-z0-9_.:-]+=", toks)]
  out <- list()
  for (tok in toks) {
    p <- regexpr("=", tok, fixed = TRUE)[1]
    if (p > 1) out[[substr(tok, 1, p - 1)]] <- substr(tok, p + 1, nchar(tok))
  }
  out
}

kv_get <- function(kv, key, default = NA_character_) {
  if (is.null(kv[[key]])) default else kv[[key]]
}

empty_dt <- function(cols) {
  need_pkg("data.table")
  dt <- data.table::data.table(matrix(nrow = 0, ncol = length(cols)))
  names(dt) <- cols
  dt
}

safe_utf8 <- function(x) {
  if (!is.character(x)) return(x)
  y <- iconv(x, from = "", to = "UTF-8", sub = "byte")
  y[is.na(y) & !is.na(x)] <- "<invalid encoding>"
  y
}

sanitize_dt_utf8 <- function(dt) {
  if (is.null(dt) || !is.data.frame(dt) || nrow(dt) == 0) return(dt)
  out <- data.table::copy(data.table::as.data.table(dt))
  for (nm in names(out)) if (is.character(out[[nm]])) out[, (nm) := safe_utf8(get(nm))]
  out
}

sanitize_list_utf8 <- function(x) {
  if (is.list(x)) {
    for (nm in names(x)) {
      if (is.character(x[[nm]])) x[[nm]] <- safe_utf8(x[[nm]])
      if (is.list(x[[nm]]) && !is.data.frame(x[[nm]])) x[[nm]] <- sanitize_list_utf8(x[[nm]])
    }
  }
  x
}

read_lines_with_encoding <- function(file, encoding) {
  warned <- FALSE
  lines <- tryCatch(
    withCallingHandlers(
      readLines(file, warn = FALSE, encoding = encoding),
      warning = function(w) {
        warned <<- TRUE
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) character()
  )
  list(lines = lines, warned = warned)
}

read_lines_raw_utf8_safe <- function(file) {
  size <- file.info(file)$size
  if (is.na(size) || size <= 0) return(character())
  raw <- readBin(file, what = "raw", n = size)
  txt <- rawToChar(raw)
  Encoding(txt) <- "bytes"
  lines <- strsplit(txt, "\n", fixed = TRUE, useBytes = TRUE)[[1]]
  sub("\r$", "", lines, useBytes = TRUE)
}

read_asc_lines <- function(file) {
  has_trials <- function(x) any(grepl("^MSG\\s+[0-9]+\\s+TRIALID\\s+", x), na.rm = TRUE)
  score_lines <- function(x) sum(!is.na(x)) + ifelse(has_trials(x), 1000000, 0)

  utf8 <- read_lines_with_encoding(file, "UTF-8")
  if (!utf8$warned && length(utf8$lines) > 0) return(utf8$lines)

  gb18030 <- read_lines_with_encoding(file, "GB18030")
  latin1 <- read_lines_with_encoding(file, "latin1")
  raw <- read_lines_raw_utf8_safe(file)
  fallback <- list(gb18030$lines, latin1$lines, raw, utf8$lines)
  fallback[[which.max(vapply(fallback, score_lines, numeric(1)))]]
}

parse_asc <- function(file, keep_samples = TRUE, progress = NULL) {
  need_pkg("data.table")
  if (is.function(progress)) progress("读取 ASC 文本", 0.02)
  lines <- read_asc_lines(file)
  if (is.function(progress)) progress("解析 metadata", 0.08)
  metadata <- parse_metadata(lines, file)
  if (is.function(progress)) progress("解析 MSG / TRIALID / TRIAL_VAR", 0.14)
  messages <- parse_messages(lines)
  if (is.function(progress)) progress("解析 gaze samples", 0.20)
  samples <- if (keep_samples) parse_samples(lines, progress = function(value) {
    if (is.function(progress)) progress(sprintf("解析 gaze samples %.0f%%", value * 100), 0.20 + value * 0.42)
  }) else empty_dt(c("sample_index", "time", "gaze_x", "gaze_y", "pupil", "valid_gaze", "valid_pupil", "valid_sample"))
  if (is.function(progress)) progress("解析 EFIX / ESACC / EBLINK", 0.66)
  fixations <- parse_fixations(lines)
  saccades <- parse_saccades(lines)
  blinks <- parse_blinks(lines)
  parsed <- list(metadata = metadata, messages = messages, samples = samples, fixations = fixations, saccades = saccades, blinks = blinks)
  if (is.function(progress)) progress("构建 trial", 0.76)
  parsed <- build_trials(parsed)
  if (is.function(progress)) progress("构建 phase", 0.84)
  parsed <- build_phases(parsed)
  if (is.function(progress)) progress("归属 trial / phase", 0.92)
  parsed <- assign_trial_phase(parsed)
  parsed$metadata$participant <- first_non_na(parsed$trials$participant, parsed$metadata$participant)
  parsed$metadata <- sanitize_list_utf8(parsed$metadata)
  for (nm in c("messages", "events", "trials", "phases", "samples", "fixations", "saccades", "blinks")) {
    parsed[[nm]] <- sanitize_dt_utf8(parsed[[nm]])
  }
  if (is.function(progress)) progress("ASC 解析完成", 1)
  parsed
}

parse_metadata <- function(lines, file) {
  h <- lines[seq_len(min(length(lines), 300))]
  start_line <- first_non_na(grep("^START", lines, value = TRUE), NA_character_)
  end_line <- first_non_na(grep("^END", lines, value = TRUE), NA_character_)
  rate_line <- first_non_na(grep("^SAMPLES.*RATE", lines, value = TRUE), first_non_na(grep("^EVENTS.*RATE", lines, value = TRUE), NA_character_))
  sampling_rate <- NA_real_
  if (!is.na(rate_line)) {
    m <- regmatches(rate_line, regexec("RATE\\s+([0-9.]+)", rate_line))[[1]]
    if (length(m) >= 2) sampling_rate <- as.numeric(m[2])
  }
  start_time <- if (!is.na(start_line)) as_num(strsplit(trimws(start_line), "\\s+")[[1]][2]) else NA_real_
  end_time <- if (!is.na(end_line)) as_num(strsplit(trimws(end_line), "\\s+")[[1]][2]) else NA_real_
  eye <- ifelse(grepl("\\bRIGHT\\b", start_line), "RIGHT", ifelse(grepl("\\bLEFT\\b", start_line), "LEFT", NA_character_))
  display_coords <- c(x_min = NA_real_, y_min = NA_real_, x_max = NA_real_, y_max = NA_real_)
  display_line <- first_non_na(grep("DISPLAY_COORDS", lines, value = TRUE), NA_character_)
  if (!is.na(display_line)) {
    nums <- regmatches(display_line, gregexpr("-?[0-9]+", display_line))[[1]]
    if (length(nums) >= 5) display_coords <- setNames(as.numeric(tail(nums, 4)), c("x_min", "y_min", "x_max", "y_max"))
  }
  val_line <- first_non_na(grep("VALIDATION.*ERROR", lines, value = TRUE), NA_character_)
  val_status <- val_avg <- val_max <- NA
  if (!is.na(val_line)) {
    val_status <- ifelse(grepl("\\bPOOR\\b", val_line), "POOR", ifelse(grepl("\\bGOOD\\b", val_line), "GOOD", NA_character_))
    m <- regmatches(val_line, regexec("ERROR\\s+([0-9.]+)\\s+avg\\.\\s+([0-9.]+)\\s+max", val_line))[[1]]
    if (length(m) >= 3) { val_avg <- as.numeric(m[2]); val_max <- as.numeric(m[3]) }
  }
  list(source_file = basename(file), source_path = file, start_time = start_time, end_time = end_time,
       recording_duration_ms = ifelse(!is.na(start_time) && !is.na(end_time), end_time - start_time, NA_real_),
       sampling_rate = sampling_rate, sample_period_ms = ifelse(!is.na(sampling_rate), 1000 / sampling_rate, NA_real_), eye = eye,
       display_coords = display_coords, validation_status = val_status, validation_avg_error = val_avg, validation_max_error = val_max,
       converted_line = first_non_na(grep("^\\*\\* CONVERTED FROM", h, value = TRUE), ""),
       camera_line = first_non_na(grep("^\\*\\* CAMERA:", h, value = TRUE), ""),
       participant = NA_character_)
}

parse_messages <- function(lines) {
  need_pkg("data.table")
  msg_lines <- grep("^MSG\\s+", lines, value = TRUE)
  if (length(msg_lines) == 0) return(empty_dt(c("msg_index", "time", "text")))
  out <- lapply(seq_along(msg_lines), function(i) {
    m <- regmatches(msg_lines[i], regexec("^MSG\\s+([0-9]+)\\s*(.*)$", msg_lines[i]))[[1]]
    if (length(m) < 3) return(NULL)
    text <- trimws(m[3]); kv <- parse_kv(text)
    trialid_msg <- NA_character_
    if (grepl("^TRIALID\\s+", text)) trialid_msg <- strsplit(text, "\\s+")[[1]][2]
    is_trial_var <- grepl("^!V\\s+TRIAL_VAR\\s+", text)
    var_name <- var_value <- NA_character_
    if (is_trial_var) {
      mm <- regmatches(text, regexec("^!V\\s+TRIAL_VAR\\s+([^\\s]+)\\s+(.+)$", text))[[1]]
      if (length(mm) >= 3) { var_name <- mm[2]; var_value <- mm[3] }
    }
    is_event <- grepl("^EVENT\\s+", text)
    event_name <- if (is_event) strsplit(text, "\\s+")[[1]][2] else NA_character_
    data.table::data.table(msg_index = i, time = as.numeric(m[2]), text = text, trialid_msg = trialid_msg,
      is_trial_var = is_trial_var, var_name = var_name, var_value = var_value, is_event = is_event, event_name = event_name,
      trial_from_kv = kv_get(kv, "trial"), rel = as_num(kv_get(kv, "rel")), unix = as_num(kv_get(kv, "unix")),
      bjt = kv_get(kv, "bjt"), q = kv_get(kv, "q"), option = kv_get(kv, "option"), mode = kv_get(kv, "mode"))
  })
  data.table::rbindlist(out, fill = TRUE)
}

parse_samples <- function(lines, progress = NULL) {
  need_pkg("data.table")
  idx <- grep("^\\s*[0-9]+\\s+", lines)
  if (length(idx) == 0) return(empty_dt(c("sample_index", "time", "gaze_x", "gaze_y", "pupil", "valid_gaze", "valid_pupil", "valid_sample")))
  if (is.function(progress)) progress(0.05)
  sample_lines <- gsub("\\s+", " ", trimws(lines[idx]), perl = TRUE)
  if (is.function(progress)) progress(0.20)
  raw <- data.table::fread(
    text = paste(sample_lines, collapse = "\n"),
    header = FALSE,
    sep = " ",
    fill = TRUE,
    na.strings = c(".", "...", "", "NA", "NaN"),
    showProgress = FALSE,
    select = 1:4
  )
  if (is.function(progress)) progress(0.85)
  while (ncol(raw) < 4) raw[[paste0("V", ncol(raw) + 1L)]] <- NA_real_
  dt <- data.table::data.table(
    sample_index = seq_len(nrow(raw)),
    time = as_num(raw[[1]]),
    gaze_x = as_num(raw[[2]]),
    gaze_y = as_num(raw[[3]]),
    pupil = as_num(raw[[4]])
  )
  dt <- apply_sample_validity(dt, pupil_valid_requires_gaze = TRUE, pupil_min_value = 0)
  if (is.function(progress)) progress(1)
  dt
}

parse_fixations <- function(lines) {
  need_pkg("data.table")
  fx <- grep("^EFIX\\s+", lines, value = TRUE)
  if (length(fx) == 0) return(empty_dt(c("fixation_id", "eye", "start_time", "end_time", "duration", "x", "y", "mean_pupil")))
  data.table::rbindlist(lapply(seq_along(fx), function(i) { p <- strsplit(trimws(fx[i]), "\\s+")[[1]]; if (length(p) < 8) return(NULL); data.table::data.table(fixation_id = i, eye = p[2], start_time = as_num(p[3]), end_time = as_num(p[4]), duration = as_num(p[5]), x = as_num(p[6]), y = as_num(p[7]), mean_pupil = as_num(p[8])) }), fill = TRUE)
}

parse_saccades <- function(lines) {
  need_pkg("data.table")
  sc <- grep("^ESACC\\s+", lines, value = TRUE)
  if (length(sc) == 0) return(empty_dt(c("saccade_id", "eye", "start_time", "end_time", "duration", "start_x", "start_y", "end_x", "end_y", "amplitude", "peak_velocity", "direction")))
  data.table::rbindlist(lapply(seq_along(sc), function(i) { p <- strsplit(trimws(sc[i]), "\\s+")[[1]]; if (length(p) < 11) return(NULL); sx <- as_num(p[6]); sy <- as_num(p[7]); ex <- as_num(p[8]); ey <- as_num(p[9]); data.table::data.table(saccade_id = i, eye = p[2], start_time = as_num(p[3]), end_time = as_num(p[4]), duration = as_num(p[5]), start_x = sx, start_y = sy, end_x = ex, end_y = ey, amplitude = as_num(p[10]), peak_velocity = as_num(p[11]), direction = atan2(ey - sy, ex - sx) * 180 / pi) }), fill = TRUE)
}

parse_blinks <- function(lines) {
  need_pkg("data.table")
  bl <- grep("^EBLINK\\s+", lines, value = TRUE)
  if (length(bl) == 0) return(empty_dt(c("blink_id", "eye", "start_time", "end_time", "duration")))
  data.table::rbindlist(lapply(seq_along(bl), function(i) { p <- strsplit(trimws(bl[i]), "\\s+")[[1]]; if (length(p) < 5) return(NULL); data.table::data.table(blink_id = i, eye = p[2], start_time = as_num(p[3]), end_time = as_num(p[4]), duration = as_num(p[5])) }), fill = TRUE)
}

build_trials <- function(parsed) {
  need_pkg("data.table")
  msg <- data.table::copy(parsed$messages)
  if (nrow(msg) == 0) { parsed$events <- data.table::data.table(); parsed$trials <- data.table::data.table(); return(parsed) }
  current <- NA_character_; cur <- character(nrow(msg))
  for (i in seq_len(nrow(msg))) { if (!is.na(msg$trialid_msg[i]) && msg$trialid_msg[i] != "") current <- msg$trialid_msg[i]; cur[i] <- current }
  msg[, current_trial := cur]
  events <- msg[is_event == TRUE]
  if (nrow(events) > 0) events[, trial_id := ifelse(!is.na(trial_from_kv) & trial_from_kv != "", trial_from_kv, current_trial)]
  trial_msgs <- msg[!is.na(trialid_msg) & trialid_msg != "", .(trial_id = trialid_msg, trial_start = time)]
  global_participant <- first_non_na(msg[is_trial_var == TRUE & var_name == "participant"]$var_value, NA_character_)
  global_edf <- first_non_na(msg[is_trial_var == TRUE & var_name == "edf"]$var_value, NA_character_)
  if (nrow(trial_msgs) == 0 && nrow(events) > 0) trial_msgs <- events[!is.na(trial_id), .(trial_start = min(time)), by = trial_id]
  trials <- data.table::copy(trial_msgs)
  if (nrow(trials) > 0) {
    trials[, `:=`(participant = global_participant, edf = global_edf, condition = NA_character_, exhibit_id = NA_character_, exhibit_name = NA_character_)]
    for (i in seq_len(nrow(trials))) {
      vars <- msg[is_trial_var == TRUE & current_trial == trials$trial_id[i]]
      if (nrow(vars) > 0) for (j in seq_len(nrow(vars))) if (vars$var_name[j] %in% names(trials)) data.table::set(trials, i, vars$var_name[j], vars$var_value[j])
      ev <- events[trial_id == trials$trial_id[i]]
      candidates <- ev[event_name %in% c("TRIAL_RESULT", "VIEWER_EXIT"), time]
      next_start <- if (i < nrow(trials)) trials$trial_start[i + 1] - 1 else parsed$metadata$end_time
      trials$trial_end[i] <- if (length(candidates) > 0) max(candidates, na.rm = TRUE) else next_start
    }
    trials[, duration := trial_end - trial_start]
  }
  parsed$messages <- msg; parsed$events <- events; parsed$trials <- trials; parsed
}

add_phase <- function(rows, participant, trial_id, condition, phase, instance, start, end, q = NA_character_) {
  if (is.na(start) || is.na(end) || end < start) return(rows)
  rows[[length(rows) + 1]] <- data.table::data.table(participant = participant, trial_id = trial_id, condition = condition, phase = phase, phase_instance = instance, question_id = q, start_time = start, end_time = end, duration = end - start)
  rows
}

build_phases <- function(parsed) {
  need_pkg("data.table")
  rows <- list(); tr <- parsed$trials; evs <- parsed$events
  if (is.null(tr) || nrow(tr) == 0) { parsed$phases <- data.table::data.table(); return(parsed) }
  for (i in seq_len(nrow(tr))) {
    tid <- tr$trial_id[i]; ev <- evs[trial_id == tid]
    rows <- add_phase(rows, tr$participant[i], tid, tr$condition[i], "trial_total", "trial_total", tr$trial_start[i], tr$trial_end[i])
    ls <- first_non_na(ev[event_name == "LOADING_START"]$time, NA_real_); le <- first_non_na(ev[event_name == "LOADING_COMPLETE"]$time, NA_real_)
    rows <- add_phase(rows, tr$participant[i], tid, tr$condition[i], "loading", "loading_start_to_complete", ls, le)
    vs <- first_non_na(ev[event_name == "VIEWER_ENTER"]$time, NA_real_); ve <- first_non_na(ev[event_name == "VIEWER_EXIT"]$time, tr$trial_end[i])
    first_qs <- first_non_na(ev[event_name == "QUESTION_START"]$time, NA_real_)
    viewer_clean_end <- if (!is.na(first_qs)) first_qs else ve
    viewer_clean_start <- max(c(vs, le), na.rm = TRUE)
    if (is.finite(viewer_clean_start)) {
      rows <- add_phase(rows, tr$participant[i], tid, tr$condition[i], "viewer_clean", "viewer_loaded_to_question", viewer_clean_start, viewer_clean_end)
    }
    ps <- first_non_na(ev[event_name == "PROGRESSIVE_USABLE"]$time, NA_real_)
    rows <- add_phase(rows, tr$participant[i], tid, tr$condition[i], "progressive_usable", "progressive_usable_to_complete", ps, le)
    qs <- ev[event_name == "QUESTION_START"]
    if (nrow(qs) > 0) for (k in seq_len(nrow(qs))) {
      qend <- first_non_na(ev[event_name == "QUESTION_SUBMIT" & q == qs$q[k]]$time, NA_real_)
      rows <- add_phase(rows, tr$participant[i], tid, tr$condition[i], "question", paste0("question_", qs$q[k]), qs$time[k], qend, paste0("q", qs$q[k]))
    }
  }
  parsed$phases <- data.table::rbindlist(rows, fill = TRUE)
  parsed$phases[, phase_id := paste(trial_id, phase_instance, sep = "__")]
  parsed
}

assign_table <- function(dt, trials, phases, time_col) {
  if (is.null(dt) || nrow(dt) == 0) return(dt)
  dt <- data.table::copy(dt); dt[, `:=`(participant = NA_character_, trial_id = NA_character_, condition = NA_character_, phase = NA_character_, phase_instance = NA_character_)]
  times <- dt[[time_col]]
  for (i in seq_len(nrow(trials))) {
    hit <- times >= trials$trial_start[i] & times <= trials$trial_end[i]
    dt$participant[hit] <- trials$participant[i]; dt$trial_id[hit] <- trials$trial_id[i]; dt$condition[hit] <- trials$condition[i]
  }
  priority <- c(trial_total = 1, viewer_clean = 2, loading = 3, progressive_usable = 4, question = 5)
  phases[, priority := priority[phase]]; phases[is.na(priority), priority := 0]; phases <- phases[order(priority)]
  for (i in seq_len(nrow(phases))) {
    hit <- times >= phases$start_time[i] & times <= phases$end_time[i] & dt$trial_id == phases$trial_id[i]
    dt$phase[hit] <- phases$phase[i]; dt$phase_instance[hit] <- phases$phase_instance[i]
  }
  dt
}

assign_trial_phase <- function(parsed) {
  parsed$samples <- assign_table(parsed$samples, parsed$trials, parsed$phases, "time")
  parsed$fixations <- assign_table(parsed$fixations, parsed$trials, parsed$phases, "start_time")
  parsed$saccades <- assign_table(parsed$saccades, parsed$trials, parsed$phases, "start_time")
  parsed$blinks <- assign_table(parsed$blinks, parsed$trials, parsed$phases, "start_time")
  parsed
}

metadata_report <- function(parsed) {
  dc <- parsed$metadata$display_coords
  data.table::data.table(source_file = parsed$metadata$source_file, participant = parsed$metadata$participant, eye = parsed$metadata$eye, sampling_rate = parsed$metadata$sampling_rate, sample_period_ms = parsed$metadata$sample_period_ms, display_x_min = dc[["x_min"]], display_y_min = dc[["y_min"]], display_x_max = dc[["x_max"]], display_y_max = dc[["y_max"]], recording_start = parsed$metadata$start_time, recording_end = parsed$metadata$end_time, recording_duration_ms = parsed$metadata$recording_duration_ms, validation_status = parsed$metadata$validation_status, validation_avg_error = parsed$metadata$validation_avg_error, validation_max_error = parsed$metadata$validation_max_error)
}

quality_report <- function(parsed) {
  s <- apply_sample_validity(parsed$samples)
  data.table::data.table(source_file = parsed$metadata$source_file, participant = parsed$metadata$participant, sample_count = nrow(s), valid_sample_rate = if (nrow(s) > 0) mean(s$valid_sample, na.rm = TRUE) else NA_real_, missing_data_rate = if (nrow(s) > 0) 1 - mean(s$valid_sample, na.rm = TRUE) else NA_real_, fixation_count = nrow(parsed$fixations), saccade_count = nrow(parsed$saccades), blink_count = nrow(parsed$blinks), message_count = nrow(parsed$messages), event_count = nrow(parsed$events), trial_count = nrow(parsed$trials), validation_status = parsed$metadata$validation_status, validation_avg_error = parsed$metadata$validation_avg_error, validation_max_error = parsed$metadata$validation_max_error)
}

get_baseline <- function(samples, start, end, baseline_ms = 500, pupil_valid_requires_gaze = TRUE, pupil_min_value = 0) {
  samples <- apply_sample_validity(samples, pupil_valid_requires_gaze, pupil_min_value)
  pre <- samples[time >= start - baseline_ms & time < start & valid_sample == TRUE]
  if (nrow(pre) >= 5) return(mean(pre$pupil, na.rm = TRUE))
  early <- samples[time >= start & time < min(end, start + baseline_ms) & valid_sample == TRUE]
  if (nrow(early) >= 5) return(mean(early$pupil, na.rm = TRUE))
  NA_real_
}

trial_intervals <- function(parsed) {
  tr <- data.table::copy(parsed$trials)
  if (is.null(tr) || nrow(tr) == 0) return(data.table::data.table())
  tr[, `:=`(
    phase = "trial_total",
    phase_instance = "trial_total",
    question_id = NA_character_,
    start_time = trial_start,
    end_time = trial_end,
    duration = trial_end - trial_start,
    phase_id = paste(trial_id, "trial_total", sep = "__")
  )]
  tr
}

add_duration_level <- function(trials, phases) {
  tr <- data.table::copy(trials)
  if (is.null(tr) || nrow(tr) == 0) {
    return(empty_dt(c("trial_id", "participant", "condition", "trial_start", "trial_end", "duration", "duration_level", "actual_loading_ms")))
  }
  if (!"condition" %in% names(tr)) tr[, condition := NA_character_]
  if (is.null(phases) || nrow(phases) == 0 || !all(c("phase", "trial_id", "duration") %in% names(phases))) {
    ld <- empty_dt(c("trial_id", "actual_loading_ms"))
  } else {
    ld <- phases[phase == "loading", .(trial_id, actual_loading_ms = duration)]
  }
  tr <- merge(tr, ld, by = "trial_id", all.x = TRUE)
  tr[, duration_level := NA_character_]
  tr[!is.na(actual_loading_ms), duration_level := {
    r <- rank(actual_loading_ms, ties.method = "first")
    ifelse(r <= ceiling(.N / 2), "short", "long")
  }, by = condition]
  tr
}

clip_events_to_intervals <- function(events, intervals, event_type) {
  need_pkg("data.table")
  if (is.null(events) || nrow(events) == 0 || is.null(intervals) || nrow(intervals) == 0) return(data.table::data.table())
  id_col <- switch(event_type, fixation = "fixation_id", saccade = "saccade_id", blink = "blink_id", "event_id")
  ev <- data.table::copy(events)
  ivs <- data.table::copy(intervals)
  if (!"phase_id" %in% names(ivs)) ivs[, phase_id := paste(trial_id, ifelse("phase_instance" %in% names(ivs), phase_instance, "trial_total"), sep = "__")]
  if (!"duration_level" %in% names(ivs)) ivs[, duration_level := NA_character_]
  rows <- vector("list", nrow(ivs))
  for (i in seq_len(nrow(ivs))) {
    iv <- ivs[i]
    hit <- ev[interval_overlaps(start_time, end_time, iv$start_time, iv$end_time)]
    if (nrow(hit) == 0) next
    clip <- clip_interval(hit$start_time, hit$end_time, iv$start_time, iv$end_time)
    out <- data.table::data.table(
      event_type = event_type,
      event_id = hit[[id_col]],
      participant = iv$participant,
      trial_id = iv$trial_id,
      condition = iv$condition,
      duration_level = iv$duration_level,
      phase = if ("phase" %in% names(iv)) iv$phase else "trial_total",
      phase_instance = if ("phase_instance" %in% names(iv)) iv$phase_instance else "trial_total",
      question_id = if ("question_id" %in% names(iv)) iv$question_id else NA_character_,
      phase_id = iv$phase_id,
      window_start = iv$start_time,
      window_end = iv$end_time,
      window_duration = iv$end_time - iv$start_time,
      original_start_time = hit$start_time,
      original_end_time = hit$end_time,
      original_duration = hit$duration,
      clipped_start_time = clip$clipped_start,
      clipped_end_time = clip$clipped_end,
      clipped_duration = clip$clipped_duration,
      relative_start_time = clip$relative_start,
      relative_end_time = clip$relative_end
    )
    if ("eye" %in% names(hit)) out[, eye := hit$eye]
    if (event_type == "fixation") out[, `:=`(fixation_id = hit$fixation_id, x = hit$x, y = hit$y, mean_pupil = hit$mean_pupil)]
    if (event_type == "saccade") out[, `:=`(saccade_id = hit$saccade_id, start_x = hit$start_x, start_y = hit$start_y, end_x = hit$end_x, end_y = hit$end_y, amplitude = hit$amplitude, peak_velocity = hit$peak_velocity, direction = hit$direction)]
    if (event_type == "blink") out[, blink_id := hit$blink_id]
    rows[[i]] <- out
  }
  data.table::rbindlist(rows, fill = TRUE)
}

summarise_interval <- function(parsed, iv, level = "phase", baseline_ms = 500, clipped_fixations = NULL, clipped_saccades = NULL, clipped_blinks = NULL, pupil_valid_requires_gaze = TRUE, pupil_min_value = 0) {
  start <- if ("start_time" %in% names(iv)) iv$start_time else iv$trial_start
  end <- if ("end_time" %in% names(iv)) iv$end_time else iv$trial_end
  dur <- end - start
  phase_id <- if ("phase_id" %in% names(iv)) iv$phase_id else paste(if ("trial_id" %in% names(iv)) iv$trial_id else "", if ("phase_instance" %in% names(iv)) iv$phase_instance else "trial_total", sep = "__")
  sm <- apply_sample_validity(parsed$samples[time >= start & time < end], pupil_valid_requires_gaze, pupil_min_value)
  window_id <- phase_id
  fx <- if (!is.null(clipped_fixations) && nrow(clipped_fixations) > 0) clipped_fixations[phase_id == window_id] else data.table::data.table()
  sc <- if (!is.null(clipped_saccades) && nrow(clipped_saccades) > 0) clipped_saccades[phase_id == window_id] else data.table::data.table()
  bl <- if (!is.null(clipped_blinks) && nrow(clipped_blinks) > 0) clipped_blinks[phase_id == window_id] else data.table::data.table()
  base <- get_baseline(parsed$samples, start, end, baseline_ms, pupil_valid_requires_gaze, pupil_min_value)
  valid_sm <- sm[valid_sample == TRUE]
  vp <- valid_sm$pupil; delta <- vp - base
  slope <- NA_real_
  if (length(vp) > 5 && !all(is.na(delta))) { x <- (valid_sm$time - start) / 1000; fit <- tryCatch(lm(delta ~ x), error = function(e) NULL); if (!is.null(fit)) slope <- unname(coef(fit)[2]) }
  data.table::data.table(level = level, participant = if ("participant" %in% names(iv)) iv$participant else NA_character_, trial_id = if ("trial_id" %in% names(iv)) iv$trial_id else NA_character_, condition = if ("condition" %in% names(iv)) iv$condition else NA_character_, duration_level = if ("duration_level" %in% names(iv)) iv$duration_level else NA_character_, phase = if ("phase" %in% names(iv)) iv$phase else "trial_total", phase_instance = if ("phase_instance" %in% names(iv)) iv$phase_instance else "trial_total", question_id = if ("question_id" %in% names(iv)) iv$question_id else NA_character_, start_time = start, end_time = end, duration_ms = dur, duration_sec = dur / 1000, sample_count = nrow(sm), valid_sample_count = nrow(valid_sm), valid_sample_rate = if (nrow(sm) > 0) mean(sm$valid_sample, na.rm = TRUE) else NA_real_, missing_data_rate = if (nrow(sm) > 0) 1 - mean(sm$valid_sample, na.rm = TRUE) else NA_real_, fixation_count = nrow(fx), mean_fixation_duration = safe_mean(fx$clipped_duration), median_fixation_duration = if (nrow(fx) > 0) median(fx$clipped_duration, na.rm = TRUE) else NA_real_, total_fixation_duration = safe_sum(fx$clipped_duration), fixation_rate_per_sec = ifelse(dur > 0, nrow(fx) / (dur / 1000), NA_real_), first_fixation_latency = ifelse(nrow(fx) > 0, min(fx$relative_start_time, na.rm = TRUE), NA_real_), saccade_count = nrow(sc), mean_saccade_amplitude = safe_mean(sc$amplitude), total_scanpath_length = safe_sum(sc$amplitude), mean_peak_velocity = safe_mean(sc$peak_velocity), saccade_rate_per_sec = ifelse(dur > 0, nrow(sc) / (dur / 1000), NA_real_), blink_count = nrow(bl), blink_rate_per_sec = ifelse(dur > 0, nrow(bl) / (dur / 1000), NA_real_), total_blink_duration = safe_sum(bl$clipped_duration), mean_blink_duration = safe_mean(bl$clipped_duration), mean_pupil_area = safe_mean(vp), baseline_pupil_area = base, baseline_corrected_pupil_area = safe_mean(delta), peak_pupil_dilation = safe_max(delta), pupil_slope_per_sec = slope)
}

interval_report <- function(parsed, intervals, level, baseline_ms = 500, clipped_fixations = NULL, clipped_saccades = NULL, clipped_blinks = NULL, pupil_valid_requires_gaze = TRUE, pupil_min_value = 0) {
  if (is.null(intervals) || nrow(intervals) == 0) return(data.table::data.table())
  data.table::rbindlist(lapply(seq_len(nrow(intervals)), function(i) summarise_interval(parsed, intervals[i], level, baseline_ms, clipped_fixations, clipped_saccades, clipped_blinks, pupil_valid_requires_gaze, pupil_min_value)), fill = TRUE)
}

pupil_timeseries <- function(parsed, bin_ms = 100, baseline_ms = 500, interval_mode = c("phase", "full_trial"), align_to = c("window_start", "trial_start", "loading_start"), use_valid_sample = TRUE, pupil_valid_requires_gaze = TRUE, pupil_min_value = 0) {
  interval_mode <- match.arg(interval_mode)
  align_to <- match.arg(align_to)
  rows <- list()
  ivs <- if (interval_mode == "full_trial") trial_intervals(parsed) else data.table::copy(parsed$phases)
  if (nrow(ivs) == 0) return(data.table::data.table())
  tr_meta <- add_duration_level(parsed$trials, parsed$phases)[, .(trial_id, duration_level, trial_start)]
  ivs <- merge(ivs, tr_meta, by = "trial_id", all.x = TRUE, suffixes = c("", "_trial"))
  for (i in seq_len(nrow(ivs))) {
    iv <- ivs[i]
    sm <- apply_sample_validity(parsed$samples[time >= iv$start_time & time < iv$end_time], pupil_valid_requires_gaze, pupil_min_value)
    if (nrow(sm) == 0) next
    loading_start <- first_non_na(parsed$phases[trial_id == iv$trial_id & phase == "loading"]$start_time, iv$start_time)
    align_time <- switch(align_to, window_start = iv$start_time, trial_start = iv$trial_start, loading_start = loading_start)
    base <- get_baseline(parsed$samples, iv$start_time, iv$end_time, baseline_ms, pupil_valid_requires_gaze, pupil_min_value)
    sm[, rel_time := time - align_time]
    sm[, bin_start := floor(rel_time / bin_ms) * bin_ms]
    tb <- sm[, {
      good <- if (use_valid_sample) valid_sample == TRUE else rep(TRUE, .N)
      pupil_values <- pupil[good]
      .(bin_end = bin_start[1] + bin_ms, bin_mid = bin_start[1] + bin_ms / 2, sample_count = .N, valid_sample_count = sum(valid_sample, na.rm = TRUE), valid_rate = mean(valid_sample, na.rm = TRUE), mean_gaze_x = safe_mean(gaze_x[valid_gaze == TRUE]), mean_gaze_y = safe_mean(gaze_y[valid_gaze == TRUE]), mean_pupil_area = safe_mean(pupil_values), baseline_pupil_area = base, baseline_corrected_pupil_area = safe_mean(pupil_values - base))
    }, by = bin_start]
    tb[, `:=`(participant = iv$participant, trial_id = iv$trial_id, condition = iv$condition, duration_level = iv$duration_level, phase = iv$phase, phase_instance = iv$phase_instance, question_id = iv$question_id, bin_ms = bin_ms, interval_mode = interval_mode, align_to = align_to)]
    rows[[length(rows) + 1]] <- tb
  }
  data.table::rbindlist(rows, fill = TRUE)
}

phase_analysis_long <- function(reports, main_phase = "loading") {
  if (is.null(reports$phase_report) || nrow(reports$phase_report) == 0) return(data.table::data.table())
  x <- data.table::copy(reports$phase_report)
  x <- x[phase == main_phase]
  cols <- c("participant", "trial_id", "condition", "duration_level", "phase", "duration_ms", "fixation_count", "mean_fixation_duration", "saccade_count", "mean_saccade_amplitude", "blink_count", "blink_rate_per_sec", "mean_pupil_area", "baseline_corrected_pupil_area", "peak_pupil_dilation", "pupil_slope_per_sec")
  x[, actual_loading_ms := duration_ms]
  cols <- c("participant", "trial_id", "condition", "duration_level", "phase", "actual_loading_ms", setdiff(cols, c("participant", "trial_id", "condition", "duration_level", "phase", "duration_ms")))
  x[, ..cols]
}

compute_reports <- function(parsed, bin_ms = 100, baseline_ms = 500, pupil_valid_requires_gaze = TRUE, pupil_min_value = 0) {
  parsed$samples <- apply_sample_validity(parsed$samples, pupil_valid_requires_gaze, pupil_min_value)
  trial_iv <- trial_intervals(parsed)
  trial_meta <- add_duration_level(parsed$trials, parsed$phases)[, .(trial_id, duration_level, actual_loading_ms)]
  if (nrow(trial_iv) > 0) trial_iv <- merge(trial_iv, trial_meta, by = "trial_id", all.x = TRUE, suffixes = c("", "_meta"))
  phase_iv <- data.table::copy(parsed$phases)
  if (nrow(phase_iv) > 0) phase_iv <- merge(phase_iv, trial_meta, by = "trial_id", all.x = TRUE, suffixes = c("", "_meta"))
  fix_trial <- clip_events_to_intervals(parsed$fixations, trial_iv, "fixation")
  sac_trial <- clip_events_to_intervals(parsed$saccades, trial_iv, "saccade")
  blink_trial <- clip_events_to_intervals(parsed$blinks, trial_iv, "blink")
  fix_phase <- clip_events_to_intervals(parsed$fixations, phase_iv, "fixation")
  sac_phase <- clip_events_to_intervals(parsed$saccades, phase_iv, "saccade")
  blink_phase <- clip_events_to_intervals(parsed$blinks, phase_iv, "blink")
  reports <- list(
    metadata = metadata_report(parsed),
    quality_report = quality_report(parsed),
    trial_report = interval_report(parsed, trial_iv, "trial", baseline_ms, fix_trial, sac_trial, blink_trial, pupil_valid_requires_gaze, pupil_min_value),
    phase_report = interval_report(parsed, phase_iv, "phase", baseline_ms, fix_phase, sac_phase, blink_phase, pupil_valid_requires_gaze, pupil_min_value),
    fixation_report_raw = parsed$fixations,
    fixation_interval_report = fix_phase,
    saccade_report_raw = parsed$saccades,
    saccade_interval_report = sac_phase,
    blink_report_raw = parsed$blinks,
    blink_interval_report = blink_phase,
    pupil_timeseries = pupil_timeseries(parsed, bin_ms, baseline_ms, "phase", "window_start", TRUE, pupil_valid_requires_gaze, pupil_min_value),
    pupil_timeseries_dv20_full_trial = pupil_timeseries(parsed, 20, baseline_ms, "full_trial", "trial_start", TRUE, pupil_valid_requires_gaze, pupil_min_value),
    event_report = parsed$events,
    message_report = parsed$messages,
    metric_dictionary = metric_dictionary()
  )
  reports$fixation_report <- reports$fixation_interval_report
  reports$saccade_report <- reports$saccade_interval_report
  reports$blink_report <- reports$blink_interval_report
  reports$phase_analysis_long <- phase_analysis_long(reports, "loading")
  reports
}

metric_dictionary <- function() {
  data.table::data.table(category = c("数据质量","数据质量","Trial/Phase","Trial/Phase","注视","注视","AOI","AOI","AOI","眼跳","眼跳","眨眼","瞳孔","瞳孔","时间序列"), metric = c("valid_sample_rate","missing_data_rate","loading_duration","question_duration","fixation_count","mean_fixation_duration","dwell_time","ttff","ffd","saccade_count","total_scanpath_length","blink_rate","baseline_corrected_pupil","pupil_slope","timebin_mean_pupil"), cn_name = c("有效采样率","缺失率","加载时长","答题时长","注视次数","平均注视时长","停留时间","首次注视时间","首次注视时长","眼跳次数","扫视路径总长度","眨眼率","基线校正瞳孔变化","瞳孔变化斜率","分箱平均瞳孔"), definition = c("有效 gaze 与 pupil sample 占全部 sample 的比例。","无效或缺失 sample 的比例。","LOADING_START 到 LOADING_COMPLETE 的时间差。","QUESTION_START 到 QUESTION_SUBMIT 的时间差。","阶段内 EFIX 数量。","阶段内 fixation duration 平均值。","gaze 或 fixation 落在 AOI 内的累计时长。","阶段开始到第一次看向 AOI 的时间。","第一次落入 AOI 的 fixation duration。","阶段内 ESACC 数量。","阶段内所有 saccade amplitude 总和。","blink count / duration。","当前阶段 pupil area 减去基线 pupil area。","pupil area 随时间变化的线性斜率。","按固定时间窗计算的平均 pupil area。"), loading_hci_use = c("适合：数据质量控制","适合：数据质量控制","核心适合：加载体验基础变量","适合：任务效率","适合：视觉搜索/注意投入","适合：认知加工深度参考","核心适合：注意投入","核心适合：提示是否被快速注意","适合：首次处理深度","适合：视觉搜索活跃度","适合：视觉探索总量","辅助：注意/疲劳参考","核心适合：等待压力/负荷参考","适合：过程趋势","核心适合：加载过程曲线"))
}

normalize_aoi <- function(aoi) {
  need_pkg("data.table")
  req <- c("aoi_group_id","aoi_name","shape_id","reference_id","shape_type","x_min","y_min","x_max","y_max","center_x","center_y","radius","participant","trial_id","condition","phase","time_start","time_end","time_start_event","time_end_event","priority","enabled")
  for (nm in req) if (!nm %in% names(aoi)) aoi[[nm]] <- NA
  aoi <- data.table::as.data.table(aoi)[, ..req]
  for (nm in c("aoi_group_id","aoi_name","shape_id","reference_id","shape_type","participant","trial_id","condition","phase","time_start_event","time_end_event")) { aoi[[nm]] <- as.character(aoi[[nm]]); aoi[[nm]][is.na(aoi[[nm]])] <- "" }
  for (nm in c("x_min","y_min","x_max","y_max","center_x","center_y","radius","time_start","time_end","priority")) aoi[[nm]] <- as_num(aoi[[nm]])
  if (!is.logical(aoi$enabled)) aoi[, enabled := !(tolower(as.character(enabled)) %in% c("false","0","no","否"))]
  aoi[is.na(enabled), enabled := TRUE]; aoi[is.na(priority), priority := 0]
  aoi[shape_id == "", shape_id := paste0("shape_", seq_len(.N))]; aoi[aoi_group_id == "", aoi_group_id := shape_id]; aoi[aoi_name == "", aoi_name := aoi_group_id]
  aoi[, shape_type := tolower(shape_type)]
  aoi
}

point_in_shape <- function(x, y, shape) {
  if (shape$shape_type == "rectangle") return(!is.na(x) & !is.na(y) & x >= min(shape$x_min, shape$x_max, na.rm = TRUE) & x <= max(shape$x_min, shape$x_max, na.rm = TRUE) & y >= min(shape$y_min, shape$y_max, na.rm = TRUE) & y <= max(shape$y_min, shape$y_max, na.rm = TRUE))
  if (shape$shape_type == "circle") return(!is.na(x) & !is.na(y) & ((x - shape$center_x)^2 + (y - shape$center_y)^2 <= shape$radius^2))
  rep(FALSE, length(x))
}

assign_aoi <- function(points, aoi, time_col, x_col, y_col) {
  pts <- data.table::copy(points); pts[, `:=`(aoi_group = NA_character_, aoi_name = NA_character_)]
  if (nrow(pts) == 0 || nrow(aoi) == 0) return(pts)
  for (i in seq_len(nrow(aoi))) {
    sh <- aoi[i]; hit <- point_in_shape(pts[[x_col]], pts[[y_col]], sh)
    if (!is.na(sh$time_start)) hit <- hit & pts[[time_col]] >= sh$time_start
    if (!is.na(sh$time_end)) hit <- hit & pts[[time_col]] <= sh$time_end
    if (sh$participant != "" && "participant" %in% names(pts)) hit <- hit & pts$participant == sh$participant
    if (sh$trial_id != "" && "trial_id" %in% names(pts)) hit <- hit & pts$trial_id == sh$trial_id
    if (sh$condition != "" && "condition" %in% names(pts)) hit <- hit & pts$condition == sh$condition
    if (sh$phase != "" && sh$phase != "all" && "phase" %in% names(pts)) hit <- hit & pts$phase == sh$phase
    pts$aoi_group[hit] <- ifelse(is.na(pts$aoi_group[hit]) | pts$aoi_group[hit] == "", sh$aoi_group_id, paste(pts$aoi_group[hit], sh$aoi_group_id, sep = ";"))
    pts$aoi_name[hit] <- ifelse(is.na(pts$aoi_name[hit]) | pts$aoi_name[hit] == "", sh$aoi_name, paste(pts$aoi_name[hit], sh$aoi_name, sep = ";"))
  }
  pts
}

aoi_matches_value <- function(value, target) {
  value <- value %||% ""
  target <- target %||% ""
  vapply(strsplit(as.character(value), "\\s*[;,|]\\s*"), function(vals) {
    vals <- trimws(vals)
    length(vals) == 0 || any(vals == "") || any(tolower(vals) == "all") || target %in% vals
  }, logical(1))
}

aoi_for_phase <- function(aoi, ph) {
  if (nrow(aoi) == 0) return(aoi)
  aoi[
    aoi_matches_value(participant, ph$participant) &
      aoi_matches_value(trial_id, ph$trial_id) &
      aoi_matches_value(condition, ph$condition) &
      aoi_matches_value(phase, ph$phase)
  ]
}

resolve_aoi_event_time <- function(parsed, ph, spec, fallback = NA_real_) {
  spec <- trimws(spec %||% "")
  if (!nzchar(spec) || tolower(spec) %in% c("manual", "absolute")) return(fallback)
  if (spec == "phase_start") return(ph$start_time)
  if (spec == "phase_end") return(ph$end_time)
  if (spec == "trial_start") return(first_non_na(parsed$trials[trial_id == ph$trial_id]$trial_start, fallback))
  if (spec == "trial_end") return(first_non_na(parsed$trials[trial_id == ph$trial_id]$trial_end, fallback))
  ev <- parsed$events[trial_id == ph$trial_id]
  target_q <- NA_character_
  target_event <- spec
  m <- regmatches(spec, regexec("^(.+)_q([0-9]+)$", spec))[[1]]
  if (length(m) >= 3) {
    target_event <- m[2]
    target_q <- m[3]
  }
  hit <- ev[event_name == target_event]
  if (!is.na(target_q)) hit <- hit[q == target_q]
  first_non_na(hit$time, fallback)
}

compute_aoi_report <- function(parsed, aoi, method = "fixation") {
  aoi <- normalize_aoi(aoi); aoi <- aoi[enabled == TRUE]
  if (nrow(aoi) == 0) return(data.table::data.table())
  rows <- list(); sample_period <- parsed$metadata$sample_period_ms
  for (i in seq_len(nrow(parsed$phases))) {
    ph <- parsed$phases[i]
    phase_aoi <- aoi_for_phase(aoi, ph)
    if (nrow(phase_aoi) == 0) next
    fx <- parsed$fixations[interval_overlaps(start_time, end_time, ph$start_time, ph$end_time) & trial_id == ph$trial_id]
    sm <- apply_sample_validity(parsed$samples[time >= ph$start_time & time < ph$end_time & trial_id == ph$trial_id])
    assign_shapes <- data.table::copy(phase_aoi)
    for (j in seq_len(nrow(assign_shapes))) {
      if (nzchar(assign_shapes$time_start_event[j])) assign_shapes$time_start[j] <- resolve_aoi_event_time(parsed, ph, assign_shapes$time_start_event[j], assign_shapes$time_start[j])
      if (nzchar(assign_shapes$time_end_event[j])) assign_shapes$time_end[j] <- resolve_aoi_event_time(parsed, ph, assign_shapes$time_end_event[j], assign_shapes$time_end[j])
    }
    assign_shapes[, `:=`(participant = "", trial_id = "", condition = "", phase = "")]
    fx <- assign_aoi(fx, assign_shapes, "start_time", "x", "y"); sm <- assign_aoi(sm, assign_shapes, "time", "gaze_x", "gaze_y")
    for (g in unique(phase_aoi$aoi_group_id)) {
      pattern <- paste0("(^|;)", g, "($|;)")
      fhit <- if (nrow(fx) > 0) !is.na(fx$aoi_group) & grepl(pattern, fx$aoi_group) else logical()
      shit <- if (nrow(sm) > 0) !is.na(sm$aoi_group) & grepl(pattern, sm$aoi_group) else logical()
      fix_hit <- fx[fhit]; sam_hit <- sm[shit]
      visit_count <- if (length(fhit) > 0) sum(fhit & c(TRUE, !head(fhit, -1)), na.rm = TRUE) else 0
      ttff <- if (nrow(fix_hit) > 0) min(fix_hit$start_time) - ph$start_time else NA_real_
      rows[[length(rows) + 1]] <- data.table::data.table(participant = ph$participant, trial_id = ph$trial_id, condition = ph$condition, phase = ph$phase, phase_instance = ph$phase_instance, aoi_group_id = g, aoi_name = first_non_na(phase_aoi[aoi_group_id == g]$aoi_name, g), method = method, duration_ms = ph$duration, fixation_count = nrow(fix_hit), dwell_time_fixation_ms = safe_sum(fix_hit$duration), dwell_time_sample_ms = ifelse(!is.na(sample_period), nrow(sam_hit) * sample_period, NA_real_), dwell_time_ms = ifelse(method == "sample", ifelse(!is.na(sample_period), nrow(sam_hit) * sample_period, NA_real_), safe_sum(fix_hit$duration)), ttff_ms = ttff, first_fixation_duration_ms = if (nrow(fix_hit) > 0) fix_hit[which.min(start_time)]$duration else NA_real_, visit_count = visit_count, aoi_sample_count = nrow(sam_hit), aoi_sample_proportion = ifelse(nrow(sm) > 0, nrow(sam_hit) / nrow(sm), NA_real_), mean_pupil_in_aoi = safe_mean(sam_hit[valid_sample == TRUE]$pupil))
    }
  }
  data.table::rbindlist(rows, fill = TRUE)
}

read_behavior <- function(file) {
  b <- data.table::fread(file, encoding = "UTF-8")
  nms <- names(b)
  lower <- tolower(nms)
  rename_if_present <- function(from, to) {
    hit <- which(lower %in% tolower(from))[1]
    if (!is.na(hit) && !to %in% names(b)) data.table::setnames(b, nms[hit], to)
  }
  rename_if_present(c("ParticipantID", "participant_id"), "participant")
  rename_if_present(c("TrialID", "trial"), "trial_id")
  rename_if_present(c("LoadingCondition", "condition"), "condition")
  if (!"question_id" %in% names(b) && "QuestionIndex" %in% names(b)) b[, question_id := paste0("q", QuestionIndex)]
  if (!"question_id" %in% names(b) && "questionindex" %in% tolower(names(b))) {
    q_col <- names(b)[tolower(names(b)) == "questionindex"][1]
    b[, question_id := paste0("q", get(q_col))]
  }
  rename_if_present(c("QuestionStartUnixMs"), "question_start_unix")
  rename_if_present(c("QuestionSubmitUnixMs"), "question_submit_unix")
  rename_if_present(c("QuestionDuration"), "response_time_ms")
  rename_if_present(c("SelectedOptionLabel", "selected_answer"), "selected_answer")
  for (nm in c("participant","trial_id","condition","question_id","question_start_unix","question_submit_unix","response_time_ms","selected_answer","correct_answer","accuracy")) if (!nm %in% names(b)) b[[nm]] <- NA
  b[, question_start_unix := as_num(question_start_unix)]; b[, question_submit_unix := as_num(question_submit_unix)]; b[, response_time_ms := as_num(response_time_ms)]; b[, accuracy := as_num(accuracy)]
  b
}

behavior_check <- function(parsed, behavior) {
  ev <- parsed$events
  starts <- ev[event_name == "QUESTION_START", .(participant = parsed$metadata$participant, trial_id, question_id = paste0("q", q), asc_question_start_time = time, asc_question_start_unix = unix)]
  starts <- merge(starts, parsed$trials[, .(trial_id, condition)], by = "trial_id", all.x = TRUE)
  subs <- ev[event_name == "QUESTION_SUBMIT", .(trial_id, question_id = paste0("q", q), asc_question_submit_time = time, asc_question_submit_unix = unix, asc_selected_option = option)]
  ascq <- merge(starts, subs, by = c("trial_id", "question_id"), all = TRUE); ascq[, asc_response_time_ms := asc_question_submit_unix - asc_question_start_unix]
  chk <- merge(behavior, ascq, by = c("trial_id", "question_id"), all = TRUE, suffixes = c("_behavior", "_asc"))
  chk[, start_unix_diff_ms := question_start_unix - asc_question_start_unix]; chk[, submit_unix_diff_ms := question_submit_unix - asc_question_submit_unix]; chk[, rt_diff_ms := response_time_ms - asc_response_time_ms]
  chk[, status := ifelse(is.na(question_start_unix) | is.na(asc_question_start_unix), "missing_pair", ifelse(abs(start_unix_diff_ms) > 100 | abs(submit_unix_diff_ms) > 100, "timestamp_warning", "ok"))]
  chk
}

normalize_colnames <- function(x) {
  y <- tolower(trimws(as.character(x)))
  y <- gsub("[^a-z0-9]+", "_", y)
  y <- gsub("^_+|_+$", "", y)
  y <- gsub("_+", "_", y)
  make.unique(y, sep = "_")
}

read_dataviewer_report <- function(file) {
  need_pkg("data.table")
  ext <- tolower(tools::file_ext(file))
  if (ext %in% c("xls", "xlsx")) {
    need_pkg("readxl")
    x <- data.table::as.data.table(readxl::read_excel(file))
  } else if (ext %in% c("csv", "txt", "tsv")) {
    x <- data.table::fread(file, na.strings = c(".", "", "NA", "NaN"))
  } else {
    stop("Unsupported DataViewer report format: ", ext, call. = FALSE)
  }
  original <- names(x)
  names(x) <- normalize_colnames(names(x))
  attr(x, "column_map") <- data.table::data.table(original_name = original, normalized_name = names(x))
  x
}

pick_col <- function(dt, candidates) {
  hit <- intersect(candidates, names(dt))
  if (length(hit) == 0) NA_character_ else hit[[1]]
}

compare_numeric_metric <- function(ours, dv, by_cols, ours_col, dv_candidates, label, tolerance = 0) {
  if (is.null(dv) || nrow(dv) == 0 || !ours_col %in% names(ours)) return(data.table::data.table(metric = label, status = "missing_dv_or_ours"))
  dv_col <- pick_col(dv, dv_candidates)
  if (is.na(dv_col)) return(data.table::data.table(metric = label, status = "missing_dv_column"))
  common_by <- intersect(by_cols, intersect(names(ours), names(dv)))
  if (length(common_by) == 0) {
    ours2 <- data.table::copy(ours)[, row_id := seq_len(.N)]
    dv2 <- data.table::copy(dv)[, row_id := seq_len(.N)]
    common_by <- "row_id"
  } else {
    ours2 <- data.table::copy(ours)
    dv2 <- data.table::copy(dv)
  }
  out <- merge(ours2[, c(common_by, ours_col), with = FALSE], dv2[, c(common_by, dv_col), with = FALSE], by = common_by, all = TRUE)
  data.table::setnames(out, c(ours_col, dv_col), c("custom_value", "dv_value"))
  out[, `:=`(metric = label, diff = as.numeric(custom_value) - as.numeric(dv_value), tolerance = tolerance)]
  out[, status := fifelse(is.na(diff), "missing_pair", fifelse(abs(diff) <= tolerance, "ok", "diff"))]
  out[]
}

compare_with_dataviewer <- function(parsed, reports, dv_trial_file = NULL, dv_message_file = NULL, dv_fixation_file = NULL, dv_saccade_file = NULL, dv_timecourse_file = NULL, out_file = "outputs/dv_alignment_report.xlsx") {
  need_pkg("data.table")
  need_pkg("openxlsx")
  warnings <- list()
  read_optional <- function(file, name) {
    if (is.null(file) || is.na(file) || !nzchar(file)) {
      warnings[[length(warnings) + 1]] <<- data.table::data.table(item = name, warning = "No DataViewer file supplied.")
      return(data.table::data.table())
    }
    if (!file.exists(file)) {
      warnings[[length(warnings) + 1]] <<- data.table::data.table(item = name, warning = paste("File not found:", file))
      return(data.table::data.table())
    }
    tryCatch(read_dataviewer_report(file), error = function(e) {
      warnings[[length(warnings) + 1]] <<- data.table::data.table(item = name, warning = conditionMessage(e))
      data.table::data.table()
    })
  }
  dv_trial <- read_optional(dv_trial_file, "trial_report")
  dv_message <- read_optional(dv_message_file, "message_report")
  dv_fix <- read_optional(dv_fixation_file, "fixation_report")
  dv_sac <- read_optional(dv_saccade_file, "saccade_report")
  dv_time <- read_optional(dv_timecourse_file, "timecourse_report")

  trial_mapping <- data.table::copy(parsed$trials)
  trial_mapping[, custom_trial_order := seq_len(.N)]
  trial_mapping[, dataviewer_trial_index_expected := custom_trial_order + 1L]
  trial_mapping[, note := "DataViewer Trial 1 is usually UNDEFINED and is excluded from custom formal trials."]

  event_time_compare <- data.table::data.table()
  if (nrow(dv_message) > 0 && nrow(parsed$events) > 0) {
    dv_time_col <- pick_col(dv_message, c("time", "trial_time", "message_time", "timestamp"))
    dv_msg_col <- pick_col(dv_message, c("message", "text", "message_text", "event", "event_name"))
    if (!is.na(dv_time_col) && !is.na(dv_msg_col)) {
      ours <- parsed$events[, .(trial_id, event_name, custom_time = time)]
      dv <- dv_message[, .(dv_time = as.numeric(get(dv_time_col)), dv_text = as.character(get(dv_msg_col)))]
      dv[, event_name := sub("^.*\\b(EVENT\\s+)?([A-Z_]+).*$", "\\2", dv_text)]
      event_time_compare <- merge(ours, dv, by = "event_name", allow.cartesian = TRUE)
      event_time_compare[, diff_ms := custom_time - dv_time]
      event_time_compare[, status := fifelse(diff_ms == 0, "ok", "diff")]
    }
  }

  trial_metric_compare <- compare_numeric_metric(reports$trial_report, dv_trial, c("trial_id", "condition"), "duration_ms", c("duration", "trial_duration", "full_trial_period_duration"), "trial_duration", 1)
  fixation_count_compare <- compare_numeric_metric(reports$trial_report, dv_trial, c("trial_id", "condition"), "fixation_count", c("fixation_count", "number_of_fixations", "fix_count"), "fixation_count", 0)
  saccade_count_compare <- compare_numeric_metric(reports$trial_report, dv_trial, c("trial_id", "condition"), "saccade_count", c("saccade_count", "number_of_saccades", "sac_count"), "saccade_count", 0)
  blink_count_compare <- compare_numeric_metric(reports$trial_report, dv_trial, c("trial_id", "condition"), "blink_count", c("blink_count", "number_of_blinks"), "blink_count", 0)
  pupil_mean_compare <- compare_numeric_metric(reports$trial_report, dv_trial, c("trial_id", "condition"), "mean_pupil_area", c("average_pupil_size", "mean_pupil_area", "pupil_size_mean", "mean_pupil"), "pupil_mean", 1)

  timecourse_compare <- data.table::data.table()
  if (nrow(dv_time) > 0 && !is.null(reports$pupil_timeseries_dv20_full_trial)) {
    ours_ts <- reports$pupil_timeseries_dv20_full_trial
    timecourse_compare <- data.table::data.table(
      custom_bin_count = nrow(ours_ts),
      dv_bin_count = nrow(dv_time),
      bin_count_diff = nrow(ours_ts) - nrow(dv_time),
      note = "Use pupil_timeseries(..., bin_ms = 20, interval_mode = 'full_trial', align_to = 'trial_start') for DataViewer Full Trial Period comparison."
    )
  }

  if (nrow(dv_fix) > 0) warnings[[length(warnings) + 1]] <- data.table::data.table(item = "fixation_report", warning = paste("DV fixation rows read:", nrow(dv_fix), "custom raw rows:", nrow(reports$fixation_report_raw)))
  if (nrow(dv_sac) > 0) warnings[[length(warnings) + 1]] <- data.table::data.table(item = "saccade_report", warning = paste("DV saccade rows read:", nrow(dv_sac), "custom raw rows:", nrow(reports$saccade_report_raw)))
  warning_dt <- if (length(warnings) > 0) data.table::rbindlist(warnings, fill = TRUE) else data.table::data.table(item = "all", warning = "No warnings.")
  sheets <- list(
    trial_mapping = trial_mapping,
    event_time_compare = event_time_compare,
    trial_metric_compare = trial_metric_compare,
    fixation_count_compare = fixation_count_compare,
    saccade_count_compare = saccade_count_compare,
    blink_count_compare = blink_count_compare,
    pupil_mean_compare = pupil_mean_compare,
    timecourse_compare = timecourse_compare,
    warnings = warning_dt
  )
  dir.create(dirname(out_file), showWarnings = FALSE, recursive = TRUE)
  export_xlsx(sheets, out_file)
  attr(sheets, "out_file") <- out_file
  sheets
}

export_xlsx <- function(reports, file) {
  need_pkg("openxlsx")
  wb <- openxlsx::createWorkbook()
  for (nm in names(reports)) if (is.data.frame(reports[[nm]])) {
    sheet <- substr(gsub("[^A-Za-z0-9_]+", "_", nm), 1, 31)
    openxlsx::addWorksheet(wb, sheet)
    openxlsx::writeData(wb, sheet, sanitize_dt_utf8(reports[[nm]]))
  }
  openxlsx::saveWorkbook(wb, file, overwrite = TRUE); file
}

plot_timeline <- function(parsed, trial_id = "") {
  need_pkg("ggplot2")
  ph <- parsed$phases; ev <- parsed$events
  if (nzchar(trial_id)) { ph <- ph[ph$trial_id == trial_id]; ev <- ev[ev$trial_id == trial_id] }
  if (nrow(ph) == 0) return(ggplot2::ggplot() + ggplot2::ggtitle("无 phase 数据"))
  t0 <- min(ph$start_time); ph[, `:=`(rel_start = (start_time - t0) / 1000, rel_end = (end_time - t0) / 1000)]; ev[, rel_time := (time - t0) / 1000]
  ggplot2::ggplot() + ggplot2::geom_segment(data = ph, ggplot2::aes(x = rel_start, xend = rel_end, y = phase_instance, yend = phase_instance), linewidth = 1.2) + ggplot2::geom_point(data = ev, ggplot2::aes(x = rel_time, y = event_name), size = 1.8) + ggplot2::labs(x = "相对时间 / 秒", y = "事件 / 阶段", title = "事件时间线") + ggplot2::theme_minimal()
}

plot_scanpath <- function(parsed, trial_id = "", phase = "") {
  need_pkg("ggplot2")
  fx <- parsed$fixations
  if (nzchar(trial_id)) fx <- fx[fx$trial_id == trial_id]
  if (nzchar(phase)) fx <- fx[fx$phase == phase]
  dc <- parsed$metadata$display_coords
  if (nrow(fx) == 0) return(ggplot2::ggplot() + ggplot2::ggtitle("无注视数据"))
  fx[, order_id := seq_len(.N)]
  ggplot2::ggplot(fx, ggplot2::aes(x = x, y = y)) + ggplot2::geom_path(ggplot2::aes(group = 1), linewidth = 0.4) + ggplot2::geom_point(ggplot2::aes(size = duration), alpha = .7) + ggplot2::geom_text(ggplot2::aes(label = order_id), size = 2.5, vjust = -0.8) + ggplot2::coord_fixed(xlim = c(dc[["x_min"]], dc[["x_max"]]), ylim = c(dc[["y_max"]], dc[["y_min"]])) + ggplot2::labs(title = "Scanpath / 注视路径", x = "x", y = "y") + ggplot2::theme_minimal()
}

plot_heatmap <- function(parsed, trial_id = "", phase = "") {
  need_pkg("ggplot2")
  sm <- parsed$samples[valid_gaze == TRUE]
  if (nzchar(trial_id)) sm <- sm[sm$trial_id == trial_id]
  if (nzchar(phase)) sm <- sm[sm$phase == phase]
  dc <- parsed$metadata$display_coords
  if (nrow(sm) == 0) return(ggplot2::ggplot() + ggplot2::ggtitle("无 gaze sample 数据"))
  ggplot2::ggplot(sm, ggplot2::aes(x = gaze_x, y = gaze_y)) + ggplot2::stat_density_2d(ggplot2::aes(fill = ggplot2::after_stat(level)), geom = "polygon", alpha = .45, bins = 12) + ggplot2::coord_fixed(xlim = c(dc[["x_min"]], dc[["x_max"]]), ylim = c(dc[["y_max"]], dc[["y_min"]])) + ggplot2::labs(title = "Heatmap / 眼动热区", x = "x", y = "y") + ggplot2::theme_minimal() + ggplot2::theme(legend.position = "none")
}

metric_dictionary <- function() {
  data.table::data.table(
    category = c(
      "数据质量","数据质量","数据质量","数据质量",
      "Trial/Phase","Trial/Phase","Trial/Phase","Trial/Phase",
      "注视","注视","注视",
      "AOI","AOI","AOI","AOI","AOI","AOI",
      "眼跳","眼跳","眼跳","眼跳",
      "眨眼","眨眼","眨眼",
      "瞳孔","瞳孔","瞳孔","瞳孔",
      "时间序列","行为合并"
    ),
    metric = c(
      "sample_count","valid_sample_rate","missing_data_rate","validation_avg_error",
      "duration_ms","fixation_count","first_fixation_latency","baseline_corrected_pupil_area",
      "mean_fixation_duration","total_fixation_duration","fixation_rate_per_sec",
      "dwell_time_ms","ttff_ms","first_fixation_duration_ms","visit_count","aoi_sample_proportion","mean_pupil_in_aoi",
      "saccade_count","mean_saccade_amplitude","total_scanpath_length","saccade_rate_per_sec",
      "blink_count","blink_rate_per_sec","total_blink_duration",
      "mean_pupil_area","peak_pupil_dilation","pupil_slope_per_sec","baseline_pupil_area",
      "timebin_mean_pupil","accuracy"
    ),
    cn_name = c(
      "采样点数","有效采样率","缺失率","平均校准误差",
      "阶段/试次时长","注视次数","首次注视潜伏期","基线校正瞳孔",
      "平均注视时长","总注视时长","注视频率",
      "AOI 停留时间","首次看向 AOI 时间","AOI 首次注视时长","AOI 访问次数","AOI 采样占比","AOI 内平均瞳孔",
      "眼跳次数","平均眼跳幅度","扫视路径总长度","眼跳频率",
      "眨眼次数","眨眼频率","总眨眼时长",
      "平均瞳孔面积","峰值瞳孔扩张","瞳孔变化斜率","基线瞳孔面积",
      "分箱平均瞳孔","正确率"
    ),
    report_table = c(
      "quality_report / trial_report / phase_report","quality_report / trial_report / phase_report","quality_report / trial_report / phase_report","metadata / quality_report",
      "trial_report / phase_report","trial_report / phase_report / fixation_report","trial_report / phase_report","trial_report / phase_report / pupil_timeseries",
      "fixation_report / trial_report / phase_report","trial_report / phase_report","trial_report / phase_report",
      "aoi_report","aoi_report","aoi_report","aoi_report","aoi_report","aoi_report",
      "saccade_report / trial_report / phase_report","saccade_report / trial_report / phase_report","trial_report / phase_report","trial_report / phase_report",
      "blink_report / trial_report / phase_report","trial_report / phase_report","trial_report / phase_report",
      "trial_report / phase_report / pupil_timeseries","trial_report / phase_report","trial_report / phase_report","trial_report / phase_report",
      "pupil_timeseries","merged_eye_behavior_report / condition_summary"
    ),
    ui_location = c(
      "数据概览、导出","数据概览、Trial / Phase 分析、导出","数据概览、Trial / Phase 分析、导出","数据概览、导出",
      "Trial / Phase 分析","Trial / Phase 分析、原始报表","Trial / Phase 分析","Trial / Phase 分析、瞳孔曲线、导出",
      "原始报表、Trial / Phase 分析","Trial / Phase 分析","Trial / Phase 分析",
      "AOI 分析","AOI 分析","AOI 分析","AOI 分析","AOI 分析","AOI 分析",
      "原始报表、Trial / Phase 分析","原始报表、Trial / Phase 分析","Trial / Phase 分析","Trial / Phase 分析",
      "原始报表、Trial / Phase 分析","Trial / Phase 分析","Trial / Phase 分析",
      "Trial / Phase 分析","Trial / Phase 分析","Trial / Phase 分析","Trial / Phase 分析",
      "Trial / Phase 分析、导出","答题合并"
    ),
    definition = c(
      "ASC 中逐行解析出的 sample 数量。","有效 gaze 与 pupil sample 占全部 sample 的比例。","无效或缺失 sample 的比例。","EyeLink validation 平均误差，用于质量控制。",
      "trial 或 phase 起点到终点的时间差。","当前 trial/phase 内 EFIX 数量。","阶段开始到第一次 fixation 的时间。","当前 pupil area 减去该阶段基线 pupil area 后的均值。",
      "当前范围内 fixation duration 平均值。","当前范围内 fixation duration 总和。","fixation count / duration_sec。",
      "落入 AOI 的 fixation 或 sample 累计时长，取决于 AOI 方法。","phase 开始到第一次落入 AOI fixation 的时间。","第一次落入 AOI 的 fixation duration。","连续进入同一 AOI 算一次 visit。","AOI 内 sample 数 / phase 内 sample 数。","落在 AOI 内 sample 的 pupil 均值。",
      "当前范围内 ESACC 数量。","当前范围内 saccade amplitude 平均值。","当前范围内 saccade amplitude 总和。","saccade count / duration_sec。",
      "当前范围内 EBLINK 数量。","blink count / duration_sec。","当前范围内 blink duration 总和。",
      "有效 pupil sample 的均值。","相对基线的最大 pupil change。","pupil change 对时间的线性斜率。","阶段前或阶段初始窗口估计的 pupil baseline。",
      "按固定 time-bin 汇总的平均 pupil area。","行为 CSV 中的正确率，可与 trial/phase 指标合并。"
    ),
    loading_hci_use = c(
      "数据完整性检查。","剔除低质量数据的依据。","判断追踪中断或眨眼较多的时段。","报告校准质量。",
      "加载、查看、答题阶段的基础时长指标。","注意投入和视觉搜索强度。","进入阶段后多快开始稳定注视。","等待压力、认知负荷和生理反应参考。",
      "认知加工深度参考。","总体注意投入。","单位时间内注视活跃度。",
      "AOI 关注程度核心指标。","目标区域是否被快速注意。","首次处理深度。","回看/访问行为。","时间精度更高的 AOI 占比。","AOI 相关生理反应。",
      "视觉搜索活跃度。","眼跳幅度变化。","视觉探索总量。","单位时间探索活跃度。",
      "注意、疲劳和数据质量参考。","单位时间眨眼情况。","缺失/闭眼总时长参考。",
      "瞳孔基础水平。","最大负荷响应。","过程趋势。","用于校正个体差异。",
      "观察加载过程中的瞳孔曲线。","与眼动指标合并，解释行为表现。"
    )
  )
}

merge_eye_behavior_report <- function(reports, behavior) {
  if (is.null(behavior) || nrow(behavior) == 0 || is.null(reports$phase_report)) return(data.table::data.table())
  b <- data.table::as.data.table(behavior)
  phase_report <- data.table::copy(reports$phase_report)
  phase_question <- phase_report[phase == "question"]
  if (nrow(phase_question) == 0) phase_question <- phase_report
  keys <- intersect(c("participant", "trial_id", "condition", "question_id"), names(b))
  if (length(keys) == 0) return(data.table::data.table())
  merge(phase_question, b, by = keys, all.x = TRUE, allow.cartesian = TRUE)
}

condition_summary <- function(merged) {
  if (is.null(merged) || nrow(merged) == 0 || !"condition" %in% names(merged)) return(data.table::data.table())
  dt <- data.table::as.data.table(merged)
  dt[, .(
    n_rows = .N,
    mean_accuracy = safe_mean(accuracy),
    mean_response_time_ms = safe_mean(response_time_ms),
    mean_duration_ms = safe_mean(duration_ms),
    mean_fixation_count = safe_mean(fixation_count),
    mean_total_fixation_duration = safe_mean(total_fixation_duration),
    mean_baseline_corrected_pupil_area = safe_mean(baseline_corrected_pupil_area),
    mean_saccade_count = safe_mean(saccade_count),
    mean_blink_count = safe_mean(blink_count)
  ), by = condition]
}

combine_report_lists <- function(report_lists) {
  if (length(report_lists) == 0) return(list())
  all_names <- unique(unlist(lapply(report_lists, names)))
  out <- list()
  for (nm in all_names) {
    pieces <- lapply(report_lists, function(x) x[[nm]])
    pieces <- pieces[vapply(pieces, is.data.frame, logical(1))]
    if (length(pieces) > 0) out[[nm]] <- data.table::rbindlist(pieces, fill = TRUE)
  }
  out
}
