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

parse_asc <- function(file, keep_samples = TRUE) {
  need_pkg("data.table")
  lines <- readLines(file, warn = FALSE, encoding = "UTF-8")
  metadata <- parse_metadata(lines, file)
  messages <- parse_messages(lines)
  samples <- if (keep_samples) parse_samples(lines) else empty_dt(c("sample_index", "time", "gaze_x", "gaze_y", "pupil", "valid_gaze", "valid_pupil"))
  fixations <- parse_fixations(lines)
  saccades <- parse_saccades(lines)
  blinks <- parse_blinks(lines)
  parsed <- list(metadata = metadata, messages = messages, samples = samples, fixations = fixations, saccades = saccades, blinks = blinks)
  parsed <- build_trials(parsed)
  parsed <- build_phases(parsed)
  parsed <- assign_trial_phase(parsed)
  parsed$metadata$participant <- first_non_na(parsed$trials$participant, parsed$metadata$participant)
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

parse_samples <- function(lines) {
  need_pkg("data.table")
  idx <- grep("^\\s*[0-9]+\\s+", lines)
  if (length(idx) == 0) return(empty_dt(c("sample_index", "time", "gaze_x", "gaze_y", "pupil", "valid_gaze", "valid_pupil")))
  out <- lapply(seq_along(idx), function(k) {
    p <- strsplit(trimws(lines[idx[k]]), "\\s+")[[1]]
    if (length(p) < 4) return(NULL)
    data.table::data.table(sample_index = k, time = as_num(p[1]), gaze_x = as_num(p[2]), gaze_y = as_num(p[3]), pupil = as_num(p[4]))
  })
  dt <- data.table::rbindlist(out, fill = TRUE)
  dt[, valid_gaze := !is.na(gaze_x) & !is.na(gaze_y)]
  dt[, valid_pupil := !is.na(pupil)]
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
    rows <- add_phase(rows, tr$participant[i], tid, tr$condition[i], "trial", "trial_total", tr$trial_start[i], tr$trial_end[i])
    ls <- first_non_na(ev[event_name == "LOADING_START"]$time, NA_real_); le <- first_non_na(ev[event_name == "LOADING_COMPLETE"]$time, NA_real_)
    rows <- add_phase(rows, tr$participant[i], tid, tr$condition[i], "loading", "loading_start_to_complete", ls, le)
    vs <- first_non_na(ev[event_name == "VIEWER_ENTER"]$time, NA_real_); ve <- first_non_na(ev[event_name == "VIEWER_EXIT"]$time, tr$trial_end[i])
    rows <- add_phase(rows, tr$participant[i], tid, tr$condition[i], "viewer", "viewer_total", vs, ve)
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
  priority <- c(trial = 1, viewer = 2, loading = 3, progressive_usable = 4, question = 5)
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
  s <- parsed$samples
  data.table::data.table(source_file = parsed$metadata$source_file, participant = parsed$metadata$participant, sample_count = nrow(s), valid_sample_rate = if (nrow(s) > 0) mean(s$valid_gaze & s$valid_pupil, na.rm = TRUE) else NA_real_, missing_data_rate = if (nrow(s) > 0) 1 - mean(s$valid_gaze & s$valid_pupil, na.rm = TRUE) else NA_real_, fixation_count = nrow(parsed$fixations), saccade_count = nrow(parsed$saccades), blink_count = nrow(parsed$blinks), message_count = nrow(parsed$messages), event_count = nrow(parsed$events), trial_count = nrow(parsed$trials), validation_status = parsed$metadata$validation_status, validation_avg_error = parsed$metadata$validation_avg_error, validation_max_error = parsed$metadata$validation_max_error)
}

get_baseline <- function(samples, start, end, baseline_ms = 500) {
  pre <- samples[time >= start - baseline_ms & time < start & valid_pupil == TRUE]
  if (nrow(pre) >= 5) return(mean(pre$pupil, na.rm = TRUE))
  early <- samples[time >= start & time <= min(end, start + baseline_ms) & valid_pupil == TRUE]
  if (nrow(early) >= 5) return(mean(early$pupil, na.rm = TRUE))
  NA_real_
}

summarise_interval <- function(parsed, iv, level = "phase", baseline_ms = 500) {
  start <- if ("start_time" %in% names(iv)) iv$start_time else iv$trial_start
  end <- if ("end_time" %in% names(iv)) iv$end_time else iv$trial_end
  dur <- end - start
  sm <- parsed$samples[time >= start & time <= end]
  fx <- parsed$fixations[start_time >= start & start_time <= end]
  sc <- parsed$saccades[start_time >= start & start_time <= end]
  bl <- parsed$blinks[start_time >= start & start_time <= end]
  base <- get_baseline(parsed$samples, start, end, baseline_ms)
  vp <- sm[valid_pupil == TRUE]$pupil; delta <- vp - base
  slope <- NA_real_
  if (length(vp) > 5 && !all(is.na(delta))) { x <- (sm[valid_pupil == TRUE]$time - start) / 1000; fit <- tryCatch(lm(delta ~ x), error = function(e) NULL); if (!is.null(fit)) slope <- unname(coef(fit)[2]) }
  data.table::data.table(level = level, participant = if ("participant" %in% names(iv)) iv$participant else NA_character_, trial_id = if ("trial_id" %in% names(iv)) iv$trial_id else NA_character_, condition = if ("condition" %in% names(iv)) iv$condition else NA_character_, phase = if ("phase" %in% names(iv)) iv$phase else "trial", phase_instance = if ("phase_instance" %in% names(iv)) iv$phase_instance else "trial_total", question_id = if ("question_id" %in% names(iv)) iv$question_id else NA_character_, start_time = start, end_time = end, duration_ms = dur, duration_sec = dur / 1000, sample_count = nrow(sm), valid_sample_rate = if (nrow(sm) > 0) mean(sm$valid_gaze & sm$valid_pupil, na.rm = TRUE) else NA_real_, missing_data_rate = if (nrow(sm) > 0) 1 - mean(sm$valid_gaze & sm$valid_pupil, na.rm = TRUE) else NA_real_, fixation_count = nrow(fx), mean_fixation_duration = safe_mean(fx$duration), median_fixation_duration = if (nrow(fx) > 0) median(fx$duration, na.rm = TRUE) else NA_real_, total_fixation_duration = safe_sum(fx$duration), fixation_rate_per_sec = ifelse(dur > 0, nrow(fx) / (dur / 1000), NA_real_), first_fixation_latency = ifelse(nrow(fx) > 0, min(fx$start_time, na.rm = TRUE) - start, NA_real_), saccade_count = nrow(sc), mean_saccade_amplitude = safe_mean(sc$amplitude), total_scanpath_length = safe_sum(sc$amplitude), mean_peak_velocity = safe_mean(sc$peak_velocity), saccade_rate_per_sec = ifelse(dur > 0, nrow(sc) / (dur / 1000), NA_real_), blink_count = nrow(bl), blink_rate_per_sec = ifelse(dur > 0, nrow(bl) / (dur / 1000), NA_real_), total_blink_duration = safe_sum(bl$duration), mean_blink_duration = safe_mean(bl$duration), mean_pupil_area = safe_mean(vp), baseline_pupil_area = base, baseline_corrected_pupil_area = safe_mean(delta), peak_pupil_dilation = safe_max(delta), pupil_slope_per_sec = slope)
}

interval_report <- function(parsed, intervals, level, baseline_ms = 500) {
  if (is.null(intervals) || nrow(intervals) == 0) return(data.table::data.table())
  data.table::rbindlist(lapply(seq_len(nrow(intervals)), function(i) summarise_interval(parsed, intervals[i], level, baseline_ms)), fill = TRUE)
}

pupil_timeseries <- function(parsed, bin_ms = 100, baseline_ms = 500) {
  rows <- list(); ph <- parsed$phases
  for (i in seq_len(nrow(ph))) {
    sm <- parsed$samples[time >= ph$start_time[i] & time <= ph$end_time[i]]
    if (nrow(sm) == 0) next
    base <- get_baseline(parsed$samples, ph$start_time[i], ph$end_time[i], baseline_ms)
    sm[, bin_start := floor((time - ph$start_time[i]) / bin_ms) * bin_ms]
    tb <- sm[, .(bin_end = bin_start[1] + bin_ms, sample_count = .N, valid_rate = mean(valid_gaze & valid_pupil, na.rm = TRUE), mean_gaze_x = safe_mean(gaze_x), mean_gaze_y = safe_mean(gaze_y), mean_pupil_area = safe_mean(pupil), baseline_pupil_area = base, baseline_corrected_pupil_area = safe_mean(pupil - base)), by = bin_start]
    tb[, `:=`(participant = ph$participant[i], trial_id = ph$trial_id[i], condition = ph$condition[i], phase = ph$phase[i], phase_instance = ph$phase_instance[i], question_id = ph$question_id[i], bin_ms = bin_ms)]
    rows[[length(rows) + 1]] <- tb
  }
  data.table::rbindlist(rows, fill = TRUE)
}

compute_reports <- function(parsed, bin_ms = 100, baseline_ms = 500) {
  list(metadata = metadata_report(parsed), quality_report = quality_report(parsed), trial_report = interval_report(parsed, parsed$trials, "trial", baseline_ms), phase_report = interval_report(parsed, parsed$phases, "phase", baseline_ms), fixation_report = parsed$fixations, saccade_report = parsed$saccades, blink_report = parsed$blinks, pupil_timeseries = pupil_timeseries(parsed, bin_ms, baseline_ms), event_report = parsed$events, message_report = parsed$messages, metric_dictionary = metric_dictionary())
}

metric_dictionary <- function() {
  data.table::data.table(category = c("数据质量","数据质量","Trial/Phase","Trial/Phase","注视","注视","AOI","AOI","AOI","眼跳","眼跳","眨眼","瞳孔","瞳孔","时间序列"), metric = c("valid_sample_rate","missing_data_rate","loading_duration","question_duration","fixation_count","mean_fixation_duration","dwell_time","ttff","ffd","saccade_count","total_scanpath_length","blink_rate","baseline_corrected_pupil","pupil_slope","timebin_mean_pupil"), cn_name = c("有效采样率","缺失率","加载时长","答题时长","注视次数","平均注视时长","停留时间","首次注视时间","首次注视时长","眼跳次数","扫视路径总长度","眨眼率","基线校正瞳孔变化","瞳孔变化斜率","分箱平均瞳孔"), definition = c("有效 gaze 与 pupil sample 占全部 sample 的比例。","无效或缺失 sample 的比例。","LOADING_START 到 LOADING_COMPLETE 的时间差。","QUESTION_START 到 QUESTION_SUBMIT 的时间差。","阶段内 EFIX 数量。","阶段内 fixation duration 平均值。","gaze 或 fixation 落在 AOI 内的累计时长。","阶段开始到第一次看向 AOI 的时间。","第一次落入 AOI 的 fixation duration。","阶段内 ESACC 数量。","阶段内所有 saccade amplitude 总和。","blink count / duration。","当前阶段 pupil area 减去基线 pupil area。","pupil area 随时间变化的线性斜率。","按固定时间窗计算的平均 pupil area。"), loading_hci_use = c("适合：数据质量控制","适合：数据质量控制","核心适合：加载体验基础变量","适合：任务效率","适合：视觉搜索/注意投入","适合：认知加工深度参考","核心适合：注意投入","核心适合：提示是否被快速注意","适合：首次处理深度","适合：视觉搜索活跃度","适合：视觉探索总量","辅助：注意/疲劳参考","核心适合：等待压力/负荷参考","适合：过程趋势","核心适合：加载过程曲线"))
}

normalize_aoi <- function(aoi) {
  need_pkg("data.table")
  req <- c("aoi_group_id","aoi_name","shape_id","shape_type","x_min","y_min","x_max","y_max","center_x","center_y","radius","participant","trial_id","condition","phase","time_start","time_end","priority","enabled")
  for (nm in req) if (!nm %in% names(aoi)) aoi[[nm]] <- NA
  aoi <- data.table::as.data.table(aoi)[, ..req]
  for (nm in c("aoi_group_id","aoi_name","shape_id","shape_type","participant","trial_id","condition","phase")) { aoi[[nm]] <- as.character(aoi[[nm]]); aoi[[nm]][is.na(aoi[[nm]])] <- "" }
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
    if (sh$trial_id != "" && "trial_id" %in% names(pts)) hit <- hit & pts$trial_id == sh$trial_id
    if (sh$condition != "" && "condition" %in% names(pts)) hit <- hit & pts$condition == sh$condition
    if (sh$phase != "" && sh$phase != "all" && "phase" %in% names(pts)) hit <- hit & pts$phase == sh$phase
    pts$aoi_group[hit] <- ifelse(is.na(pts$aoi_group[hit]) | pts$aoi_group[hit] == "", sh$aoi_group_id, paste(pts$aoi_group[hit], sh$aoi_group_id, sep = ";"))
    pts$aoi_name[hit] <- ifelse(is.na(pts$aoi_name[hit]) | pts$aoi_name[hit] == "", sh$aoi_name, paste(pts$aoi_name[hit], sh$aoi_name, sep = ";"))
  }
  pts
}

compute_aoi_report <- function(parsed, aoi, method = "fixation") {
  aoi <- normalize_aoi(aoi); aoi <- aoi[enabled == TRUE]
  if (nrow(aoi) == 0) return(data.table::data.table())
  rows <- list(); sample_period <- parsed$metadata$sample_period_ms
  for (i in seq_len(nrow(parsed$phases))) {
    ph <- parsed$phases[i]
    fx <- parsed$fixations[start_time >= ph$start_time & start_time <= ph$end_time & trial_id == ph$trial_id]
    sm <- parsed$samples[time >= ph$start_time & time <= ph$end_time & trial_id == ph$trial_id]
    fx <- assign_aoi(fx, aoi, "start_time", "x", "y"); sm <- assign_aoi(sm, aoi, "time", "gaze_x", "gaze_y")
    for (g in unique(aoi$aoi_group_id)) {
      pattern <- paste0("(^|;)", g, "($|;)")
      fhit <- if (nrow(fx) > 0) !is.na(fx$aoi_group) & grepl(pattern, fx$aoi_group) else logical()
      shit <- if (nrow(sm) > 0) !is.na(sm$aoi_group) & grepl(pattern, sm$aoi_group) else logical()
      fix_hit <- fx[fhit]; sam_hit <- sm[shit]
      visit_count <- if (length(fhit) > 0) sum(fhit & c(TRUE, !head(fhit, -1)), na.rm = TRUE) else 0
      ttff <- if (nrow(fix_hit) > 0) min(fix_hit$start_time) - ph$start_time else NA_real_
      rows[[length(rows) + 1]] <- data.table::data.table(participant = ph$participant, trial_id = ph$trial_id, condition = ph$condition, phase = ph$phase, phase_instance = ph$phase_instance, aoi_group_id = g, aoi_name = first_non_na(aoi[aoi_group_id == g]$aoi_name, g), method = method, duration_ms = ph$duration, fixation_count = nrow(fix_hit), dwell_time_fixation_ms = safe_sum(fix_hit$duration), dwell_time_sample_ms = ifelse(!is.na(sample_period), nrow(sam_hit) * sample_period, NA_real_), dwell_time_ms = ifelse(method == "sample", ifelse(!is.na(sample_period), nrow(sam_hit) * sample_period, NA_real_), safe_sum(fix_hit$duration)), ttff_ms = ttff, first_fixation_duration_ms = if (nrow(fix_hit) > 0) fix_hit[which.min(start_time)]$duration else NA_real_, visit_count = visit_count, aoi_sample_count = nrow(sam_hit), aoi_sample_proportion = ifelse(nrow(sm) > 0, nrow(sam_hit) / nrow(sm), NA_real_), mean_pupil_in_aoi = safe_mean(sam_hit$pupil))
    }
  }
  data.table::rbindlist(rows, fill = TRUE)
}

read_behavior <- function(file) {
  b <- data.table::fread(file, encoding = "UTF-8")
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

export_xlsx <- function(reports, file) {
  need_pkg("openxlsx")
  wb <- openxlsx::createWorkbook()
  for (nm in names(reports)) if (is.data.frame(reports[[nm]])) { sheet <- substr(gsub("[^A-Za-z0-9_]+", "_", nm), 1, 31); openxlsx::addWorksheet(wb, sheet); openxlsx::writeData(wb, sheet, reports[[nm]]) }
  openxlsx::saveWorkbook(wb, file, overwrite = TRUE); file
}

plot_timeline <- function(parsed, trial_id = "") {
  need_pkg("ggplot2")
  ph <- parsed$phases; ev <- parsed$events
  if (nzchar(trial_id)) { ph <- ph[trial_id == !!trial_id]; ev <- ev[trial_id == !!trial_id] }
  if (nrow(ph) == 0) return(ggplot2::ggplot() + ggplot2::ggtitle("无 phase 数据"))
  t0 <- min(ph$start_time); ph[, `:=`(rel_start = (start_time - t0) / 1000, rel_end = (end_time - t0) / 1000)]; ev[, rel_time := (time - t0) / 1000]
  ggplot2::ggplot() + ggplot2::geom_segment(data = ph, ggplot2::aes(x = rel_start, xend = rel_end, y = phase_instance, yend = phase_instance, linewidth = phase)) + ggplot2::geom_point(data = ev, ggplot2::aes(x = rel_time, y = event_name), size = 1.8) + ggplot2::labs(x = "相对时间 / 秒", y = "事件 / 阶段", title = "事件时间线") + ggplot2::theme_minimal()
}

plot_scanpath <- function(parsed, trial_id = "", phase = "") {
  need_pkg("ggplot2")
  fx <- parsed$fixations
  if (nzchar(trial_id)) fx <- fx[trial_id == !!trial_id]
  if (nzchar(phase)) fx <- fx[phase == !!phase]
  dc <- parsed$metadata$display_coords
  if (nrow(fx) == 0) return(ggplot2::ggplot() + ggplot2::ggtitle("无注视数据"))
  fx[, order_id := seq_len(.N)]
  ggplot2::ggplot(fx, ggplot2::aes(x = x, y = y)) + ggplot2::geom_path(ggplot2::aes(group = 1), linewidth = 0.4) + ggplot2::geom_point(ggplot2::aes(size = duration), alpha = .7) + ggplot2::geom_text(ggplot2::aes(label = order_id), size = 2.5, vjust = -0.8) + ggplot2::coord_fixed(xlim = c(dc[["x_min"]], dc[["x_max"]]), ylim = c(dc[["y_max"]], dc[["y_min"]])) + ggplot2::labs(title = "Scanpath / 注视路径", x = "x", y = "y") + ggplot2::theme_minimal()
}

plot_heatmap <- function(parsed, trial_id = "", phase = "") {
  need_pkg("ggplot2")
  sm <- parsed$samples[valid_gaze == TRUE]
  if (nzchar(trial_id)) sm <- sm[trial_id == !!trial_id]
  if (nzchar(phase)) sm <- sm[phase == !!phase]
  dc <- parsed$metadata$display_coords
  if (nrow(sm) == 0) return(ggplot2::ggplot() + ggplot2::ggtitle("无 gaze sample 数据"))
  ggplot2::ggplot(sm, ggplot2::aes(x = gaze_x, y = gaze_y)) + ggplot2::stat_density_2d(ggplot2::aes(fill = ggplot2::after_stat(level)), geom = "polygon", alpha = .45, bins = 12) + ggplot2::coord_fixed(xlim = c(dc[["x_min"]], dc[["x_max"]]), ylim = c(dc[["y_max"]], dc[["y_min"]])) + ggplot2::labs(title = "Heatmap / 眼动热区", x = "x", y = "y") + ggplot2::theme_minimal() + ggplot2::theme(legend.position = "none")
}
