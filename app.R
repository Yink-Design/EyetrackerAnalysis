# EyeLink ASC Analyzer CN
# Run with: shiny::runApp()

options(shiny.maxRequestSize = 1024 * 1024^2)

required_packages <- c("shiny", "DT", "data.table", "ggplot2", "openxlsx", "ggforce", "png", "jpeg", "plotly", "readxl", "jsonlite")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages) > 0) {
  stop("Missing R packages: ", paste(missing_packages, collapse = ", "), ". Run source('install_dependencies.R') first.", call. = FALSE)
}

library(shiny)
library(DT)
library(data.table)
library(ggplot2)
library(plotly)

source("global.R", encoding = "UTF-8")
source("R/core.R", encoding = "UTF-8")
source("R/dynamic_aoi_video.R", encoding = "UTF-8")

empty_aoi <- function() data.table(
  aoi_group_id = character(), aoi_name = character(), shape_id = character(), reference_id = character(), shape_type = character(),
  x_min = numeric(), y_min = numeric(), x_max = numeric(), y_max = numeric(),
  center_x = numeric(), center_y = numeric(), radius = numeric(),
  participant = character(), experiment = character(), trial_id = character(), condition = character(), phase = character(),
  time_start = numeric(), time_end = numeric(), time_start_event = character(), time_end_event = character(), priority = numeric(), enabled = logical()
)

with_source <- function(reports, source_file) {
  for (nm in names(reports)) {
    if (is.data.frame(reports[[nm]]) && !"source_file" %in% names(reports[[nm]])) {
      reports[[nm]][, source_file := source_file]
      data.table::setcolorder(reports[[nm]], c("source_file", setdiff(names(reports[[nm]]), "source_file")))
    }
  }
  reports
}

read_reference_image <- function(path) {
  ext <- tolower(tools::file_ext(path))
  img <- switch(ext, png = png::readPNG(path), jpg = jpeg::readJPEG(path), jpeg = jpeg::readJPEG(path), stop("Reference image only supports PNG/JPG/JPEG.", call. = FALSE))
  as.raster(img)
}

blank_reference_choices <- function(refs) {
  c("无参考图" = "", stats::setNames(names(refs), names(refs)))
}

base_canvas <- function(parsed, reference_image = NULL, title = "") {
  dc <- parsed$metadata$display_coords
  p <- ggplot() +
    coord_fixed(xlim = c(dc[["x_min"]], dc[["x_max"]]), ylim = c(dc[["y_max"]], dc[["y_min"]])) +
    labs(x = "x", y = "y", title = title) +
    theme_minimal()
  if (!is.null(reference_image)) {
    p <- p + annotation_raster(reference_image, xmin = dc[["x_min"]], xmax = dc[["x_max"]], ymin = dc[["y_max"]], ymax = dc[["y_min"]])
  }
  p
}

plot_aoi_canvas <- function(parsed, aoi, reference_image = NULL, reference_id = "") {
  p <- base_canvas(parsed, reference_image, "AOI canvas aligned to DISPLAY_COORDS")
  if (!is.null(aoi) && nrow(aoi) > 0) {
    if ("reference_id" %in% names(aoi) && nzchar(reference_id %||% "")) aoi <- aoi[reference_id %in% c("", reference_id)]
    rects <- aoi[shape_type == "rectangle"]
    if (nrow(rects) > 0) p <- p + geom_rect(data = rects, aes(xmin = x_min, xmax = x_max, ymin = y_min, ymax = y_max), inherit.aes = FALSE, fill = NA, color = "#2A6FBB", linewidth = 0.8)
    circles <- aoi[shape_type == "circle"]
    if (nrow(circles) > 0) p <- p + ggforce::geom_circle(data = circles, aes(x0 = center_x, y0 = center_y, r = radius), inherit.aes = FALSE, fill = NA, color = "#B84A62", linewidth = 0.8)
  }
  p
}

safe_timeline <- function(parsed, trial_id = "") {
  trial_id <- trial_id %||% ""
  ph <- copy(parsed$phases); ev <- copy(parsed$events)
  if (nzchar(trial_id)) { ph <- ph[ph$trial_id == trial_id]; ev <- ev[ev$trial_id == trial_id] }
  if (nrow(ph) == 0) return(ggplot() + ggtitle("No phase data"))
  t0 <- min(ph$start_time, na.rm = TRUE)
  ph[, `:=`(rel_start = (start_time - t0) / 1000, rel_end = (end_time - t0) / 1000)]
  ev[, rel_time := (time - t0) / 1000]
  ggplot() +
    geom_segment(data = ph, aes(x = rel_start, xend = rel_end, y = phase_instance, yend = phase_instance), linewidth = 1.2, color = "#2A6FBB") +
    geom_point(data = ev, aes(x = rel_time, y = event_name), size = 1.8, color = "#B84A62") +
    labs(x = "相对时间 / 秒", y = "事件 / 阶段", title = "事件时间线") +
    theme_minimal()
}

safe_scanpath <- function(parsed, trial_id = "", phase = "", reference_image = NULL) {
  trial_id <- trial_id %||% ""; phase <- phase %||% ""
  fx <- copy(parsed$fixations)
  if (nzchar(trial_id)) fx <- fx[fx$trial_id == trial_id]
  if (nzchar(phase)) fx <- fx[fx$phase == phase]
  if (nrow(fx) == 0) return(ggplot() + ggtitle("No fixation data"))
  fx[, order_id := seq_len(.N)]
  base_canvas(parsed, reference_image, "注视路径 / Scanpath") +
    geom_path(data = fx, aes(x = x, y = y, group = 1), linewidth = 0.45, alpha = 0.85, color = "#3E6C59") +
    geom_point(data = fx, aes(x = x, y = y, size = duration), alpha = 0.72, color = "#B84A62") +
    geom_text(data = fx, aes(x = x, y = y, label = order_id), size = 2.4, vjust = -0.8)
}

safe_heatmap <- function(parsed, trial_id = "", phase = "", reference_image = NULL) {
  trial_id <- trial_id %||% ""; phase <- phase %||% ""
  sm <- copy(parsed$samples[valid_gaze == TRUE])
  if (nzchar(trial_id)) sm <- sm[sm$trial_id == trial_id]
  if (nzchar(phase)) sm <- sm[sm$phase == phase]
  if (nrow(sm) == 0) return(ggplot() + ggtitle("No gaze sample data"))
  base_canvas(parsed, reference_image, "眼动热图 / Heatmap") +
    stat_density_2d(data = sm, aes(x = gaze_x, y = gaze_y, fill = after_stat(level)), geom = "polygon", alpha = 0.46, bins = 12) +
    theme(legend.position = "none")
}

safe_pupil_curve <- function(reports, trial_id = "", phase = "") {
  ts <- copy(reports$pupil_timeseries)
  trial_id <- trial_id %||% ""; phase <- phase %||% ""
  if (is.null(ts) || nrow(ts) == 0) return(ggplot() + ggtitle("无瞳孔时间序列"))
  if (nzchar(trial_id)) ts <- ts[ts$trial_id == trial_id]
  if (nzchar(phase)) ts <- ts[ts$phase == phase]
  if (!nzchar(phase) && "phase" %in% names(ts)) ts <- ts[phase != "trial_total"]
  if (nrow(ts) == 0) return(ggplot() + ggtitle("当前筛选下无瞳孔时间序列"))
  ph <- copy(reports$phase_report)
  tr <- copy(reports$trial_report)
  if (!is.null(ph) && nrow(ph) > 0 && !is.null(tr) && nrow(tr) > 0) {
    phase_start <- ph[, .(trial_id, phase, phase_instance, phase_start_time = start_time)]
    trial_start <- tr[, .(trial_id, trial_start_time = start_time)]
    ts <- merge(ts, phase_start, by = c("trial_id", "phase", "phase_instance"), all.x = TRUE)
    ts <- merge(ts, trial_start, by = "trial_id", all.x = TRUE)
    ts[, plot_time_sec := (phase_start_time - trial_start_time + bin_mid) / 1000]
  } else {
    ts[, plot_time_sec := bin_mid / 1000]
  }
  if (!nzchar(phase)) {
    ts[, plot_bin := round(plot_time_sec * 1000)]
    ts[, phase_priority := fifelse(phase == "viewer_clean", 1L,
      fifelse(phase == "loading", 2L,
        fifelse(phase == "progressive_usable", 3L,
          fifelse(phase == "question", 4L, 0L)
        )
      )
    )]
    setorder(ts, trial_id, plot_bin, phase_priority)
    ts <- ts[, .SD[.N], by = .(trial_id, plot_bin)]
    ts[, curve_id := trial_id]
  } else {
    ts[, curve_id := interaction(trial_id, phase_instance, drop = TRUE)]
  }

  ggplot(ts, aes(x = plot_time_sec, y = baseline_corrected_pupil_area, color = phase, group = curve_id)) +
    geom_line(linewidth = 0.55, na.rm = TRUE) +
    facet_wrap(~ trial_id, scales = "free_x") +
    labs(x = "Trial 内连续时间 / 秒", y = "基线校正瞳孔面积", title = "瞳孔变化曲线") +
    theme_minimal()
}

time_in_windows <- function(time, windows) {
  if (is.null(windows) || nrow(windows) == 0) return(rep(FALSE, length(time)))
  hit <- rep(FALSE, length(time))
  for (i in seq_len(nrow(windows))) hit <- hit | (time >= windows$start_time[i] & time < windows$end_time[i])
  hit
}

event_in_windows <- function(start_time, end_time, windows) {
  if (is.null(windows) || nrow(windows) == 0) return(rep(FALSE, length(start_time)))
  hit <- rep(FALSE, length(start_time))
  for (i in seq_len(nrow(windows))) hit <- hit | interval_overlaps(start_time, end_time, windows$start_time[i], windows$end_time[i])
  hit
}

filtered_analysis <- function(parsed, reports, experiment_value = "", trial_value = "", phase_value = "") {
  experiment_value <- experiment_value %||% ""
  trial_value <- trial_value %||% ""
  phase_value <- phase_value %||% ""
  p <- parsed
  p$trials <- copy(parsed$trials)
  p$phases <- copy(parsed$phases)
  p$events <- copy(parsed$events)
  p$samples <- copy(parsed$samples)
  p$fixations <- copy(parsed$fixations)
  if (nzchar(experiment_value)) {
    p$trials <- p$trials[experiment == experiment_value]
    p$phases <- p$phases[experiment == experiment_value]
    p$events <- p$events[trial_id %in% p$trials$trial_id]
    p$samples <- p$samples[experiment == experiment_value]
    p$fixations <- p$fixations[experiment == experiment_value]
  }
  if (nzchar(trial_value)) {
    p$phases <- p$phases[p$phases$trial_id == trial_value]
    p$events <- p$events[p$events$trial_id == trial_value]
    p$samples <- p$samples[p$samples$trial_id == trial_value]
    p$fixations <- p$fixations[p$fixations$trial_id == trial_value]
  }
  if (nzchar(phase_value)) {
    p$phases <- p$phases[p$phases$phase == phase_value]
    p$events <- p$events[time_in_windows(p$events$time, p$phases)]
    p$samples <- p$samples[time_in_windows(p$samples$time, p$phases)]
    p$fixations <- p$fixations[event_in_windows(p$fixations$start_time, p$fixations$end_time, p$phases)]
  }
  rep <- reports
  if (length(rep) > 0) {
    for (nm in names(rep)) {
      if (is.data.frame(rep[[nm]])) {
        dt <- copy(as.data.table(rep[[nm]]))
        if (nzchar(experiment_value) && "experiment" %in% names(dt)) dt <- dt[dt$experiment == experiment_value]
        if (nzchar(trial_value) && "trial_id" %in% names(dt)) dt <- dt[dt$trial_id == trial_value]
        if (nzchar(phase_value) && "phase" %in% names(dt)) dt <- dt[dt$phase == phase_value]
        rep[[nm]] <- dt
      }
    }
  }
  list(parsed = p, reports = rep)
}

workflow_table <- function() {
  data.table(
    step = c("1 导入数据", "2 数据概览", "3 指标说明", "4 Trial / Phase", "5 AOI", "6 答题合并", "7 导出"),
    action = c(
      "上传一个或多个 ASC 文件。",
      "检查 metadata、quality、trials 和 phases。",
      "搜索指标定义，并查看每个指标所在的报表和页面。",
      "选择 trial / phase，查看时间线、注视路径、热图、瞳孔曲线和报表。",
      "上传参考图，绘制 AOI 或读取 AOI CSV，然后查看 aoi_report。",
      "上传行为 CSV，查看时间戳检查、眼动行为综合表和 condition 汇总。",
      "导出 CSV、XLSX、PNG、AOI CSV 或项目 RDS。"
    ),
    output = c("解析后的数据", "quality_report / trial_report / phase_report", "metric_dictionary", "trial_report / phase_report / pupil_timeseries", "aoi_definition / aoi_report", "behavior_check_report / merged_eye_behavior_report / condition_summary", "CSV / XLSX / PNG / RDS")
  )
}

ui <- fluidPage(
  includeCSS("www/app.css"),
  tags$head(tags$script(src = "dynamic-aoi-player.js?v=20260610-blob-seek")),
  titlePanel("EyeLink ASC 眼动分析工具"),
  sidebarLayout(
    sidebarPanel(
      textInput("formal_package_dir", "正式被试目录路径", value = ""),
      actionButton("load_formal_package", "加载正式被试目录"),
      helpText("目录必须包含 DataCollectionManifest.csv；程序只读取该目录内部文件。"),
      hr(),
      fileInput("asc_files", "上传 ASC 文件（支持多选）", accept = c(".asc", ".txt"), multiple = TRUE),
      helpText("当前单次上传上限约 1GB。大文件解析时会显示分阶段进度。"),
      fileInput("reference_file", "上传参考图（PNG/JPG，支持多张）", accept = c(".png", ".jpg", ".jpeg"), multiple = TRUE),
      fileInput("aoi_file", "上传 AOI CSV（可选）", accept = ".csv"),
      fileInput("behavior_file", "上传答题记录 CSV（可选，支持多选）", accept = ".csv", multiple = TRUE),
      fileInput("project_file", "读取项目 RDS（可选）", accept = ".rds"),
      numericInput("bin_ms", "Time-bin 大小 / ms", value = 100, min = 20, step = 10),
      numericInput("baseline_ms", "瞳孔基线窗口 / ms", value = 500, min = 100, step = 100),
      selectInput("aoi_method", "AOI dwell 计算方法", choices = c("fixation", "sample"), selected = "fixation"),
      actionButton("parse_btn", "解析 / 更新分析", class = "btn-primary"),
      uiOutput("pending_upload_ui"),
      uiOutput("behavior_inventory_ui"),
      hr(),
      uiOutput("active_file_ui"),
      uiOutput("parsed_file_inventory_ui"),
      selectInput("experiment_select", "当前查看 Experiment", choices = c("All" = "__all__"), selected = "__all__"),
      selectInput("trial_select", "当前查看 / 绑定 Trial", choices = c("All" = "__all__"), selected = "__all__"),
      selectInput("phase_select", "当前查看 Phase", choices = c("All" = "__all__"), selected = "__all__"),
      hr(),
      downloadButton("download_xlsx", "导出当前被试 XLSX"),
      downloadButton("download_all_xlsx", "导出全部被试 ZIP"),
      downloadButton("download_project", "保存项目 RDS")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("工作流", br(), DTOutput("workflow_tbl")),
        tabPanel("数据概览", br(), verbatimTextOutput("status"), h4("Package Inventory"), DTOutput("package_inventory_tbl"), h4("Package / Phase Warnings"), DTOutput("package_warning_tbl"), h4("Quality Report"), DTOutput("quality_tbl"), h4("Metadata"), DTOutput("metadata_tbl"), h4("Trials"), DTOutput("trials_tbl"), h4("Phases"), DTOutput("phases_tbl")),
        tabPanel("指标说明", br(), DTOutput("metric_tbl")),
        tabPanel("Trial / Phase 分析", br(), verbatimTextOutput("filter_status"), plotlyOutput("timeline_plot", height = 360), plotlyOutput("scanpath_plot", height = 420), plotlyOutput("heatmap_plot", height = 420), plotlyOutput("pupil_plot", height = 360), h4("Trial Report"), DTOutput("trial_report_tbl"), h4("Phase Report"), DTOutput("phase_report_tbl")),
        tabPanel("AOI 编辑", br(),
          fluidRow(
            column(4,
              selectInput("reference_select", "参考图", choices = c("无参考图" = ""), selected = ""),
              textInput("aoi_group", "AOI Group ID", "aoi_1"),
              textInput("aoi_name", "AOI 名称", "兴趣区 1"),
              textInput("aoi_shape_id", "Shape ID", ""),
              selectInput("aoi_participant_bind", "批量规则 Participant（可选）", choices = c("All" = ""), selected = "", multiple = TRUE),
              selectInput("aoi_experiment_bind", "批量规则 Experiment（可选）", choices = c("All" = ""), selected = "", multiple = TRUE),
              selectInput("aoi_condition_bind", "批量规则 Condition（可选）", choices = c("All" = ""), selected = "", multiple = TRUE),
              selectInput("aoi_trial_bind", "批量规则 Trial（可选）", choices = c("All" = ""), selected = "", multiple = TRUE),
              selectInput("aoi_phase_bind", "批量规则 Phase（可选）", choices = c("All" = ""), selected = "", multiple = TRUE),
              selectInput("aoi_time_start_event", "动态起点", choices = c("手动/不使用" = "", "phase_start", "trial_start", "LOADING_START", "PROGRESSIVE_USABLE", "QUESTION_START_q1", "QUESTION_START_q2", "LOADING_COMPLETE", "VIEWER_ENTER", "EXP2_LOADING_START", "EXP2_STAGE_1_START", "EXP2_STAGE_2_START", "EXP2_PROGRESSIVE_USABLE", "EXP2_STAGE_3_START", "EXP2_LOADING_COMPLETE"), selected = ""),
              selectInput("aoi_time_end_event", "动态终点", choices = c("手动/不使用" = "", "phase_end", "trial_end", "LOADING_COMPLETE", "PROGRESSIVE_USABLE", "QUESTION_START_q1", "QUESTION_START_q2", "QUESTION_SUBMIT_q1", "QUESTION_SUBMIT_q2", "VIEWER_EXIT", "EXP2_STAGE_1_START", "EXP2_STAGE_2_START", "EXP2_STAGE_3_START", "EXP2_LOADING_COMPLETE", "EXP2_SUBMIT_SELECTION"), selected = ""),
              numericInput("circle_radius", "圆形半径", 80, min = 1),
              numericInput("aoi_time_start", "AOI 起始时间（可选）", NA),
              numericInput("aoi_time_end", "AOI 结束时间（可选）", NA),
              numericInput("aoi_priority", "优先级", 0),
              checkboxInput("aoi_enabled", "启用 AOI", TRUE),
              actionButton("add_circle", "在点击位置添加圆形 AOI"),
              actionButton("update_aoi", "更新选中 AOI"),
              actionButton("duplicate_aoi_time", "为选中 AOI 新增时间窗"),
              actionButton("bind_current_trial_aoi", "绑定到当前被试/Trial"),
              helpText("拉丁方映射推荐：左侧选择当前 ASC/Trial 后点此按钮，会为该被试-trial 写入一条单独 AOI 记录。上方批量规则只适合所有被试 trial_id 完全一致的情况。"),
              actionButton("delete_aoi", "删除选中 AOI"),
              actionButton("clear_aoi", "清空全部 AOI"),
              downloadButton("download_aoi_csv", "导出 AOI CSV")
            ),
            column(8,
              plotOutput("aoi_canvas", height = 520, brush = brushOpts(id = "aoi_brush", resetOnNew = TRUE), click = clickOpts(id = "aoi_click")),
              h4("当前 trial/phase 时间标记"),
              fluidRow(column(6, actionButton("time_to_start", "填入起始时间")), column(6, actionButton("time_to_end", "填入结束时间"))),
              DTOutput("aoi_time_markers_tbl")
            )
          ),
          DTOutput("aoi_tbl"),
          h4("选中 AOI 的被试 / Trial 绑定情况"),
          fluidRow(
            column(6, actionButton("load_aoi_binding", "载入选中绑定")),
            column(6, actionButton("delete_aoi_binding", "删除选中绑定"))
          ),
          DTOutput("aoi_binding_summary_tbl")
        ),
        tabPanel("AOI 分析", br(), plotOutput("aoi_overlay_plot", height = 460), h4("AOI Report"), DTOutput("aoi_report_tbl")),
        tabPanel("动态 AOI 验证", br(), dynamic_aoi_validator_module_ui("dynamic_validator")),
        tabPanel("答题合并", br(), h4("EXP1 时间戳 / 题目匹配检查"), DTOutput("behavior_check_tbl"), h4("EXP1 眼动 + 行为综合表"), DTOutput("merged_behavior_tbl"), h4("EXP1 Condition Summary"), DTOutput("condition_summary_tbl"), hr(), h4("EXP2 Marker 对齐"), DTOutput("exp2_alignment_tbl"), h4("EXP2 眼动 + 选择综合表"), DTOutput("exp2_behavior_tbl"), h4("EXP2 Condition Summary"), DTOutput("exp2_summary_tbl"), hr(), h4("正式动态 AOI 对齐"), DTOutput("dynamic_aoi_alignment_tbl"), h4("正式动态 AOI 汇总"), DTOutput("dynamic_aoi_summary_tbl")),
        tabPanel("原始报表", br(), h4("Fixation"), DTOutput("fix_tbl"), h4("Saccade"), DTOutput("sac_tbl"), h4("Blink"), DTOutput("blink_tbl"), h4("Messages / Events"), DTOutput("event_tbl")),
        tabPanel("DataViewer 对齐检查", br(),
          fluidRow(
            column(4, fileInput("dv_trial_file", "Trial Report", accept = c(".xls", ".xlsx", ".csv", ".txt"))),
            column(4, fileInput("dv_message_file", "Message Report", accept = c(".xls", ".xlsx", ".csv", ".txt"))),
            column(4, fileInput("dv_fixation_file", "Fixation Report", accept = c(".xls", ".xlsx", ".csv", ".txt")))
          ),
          fluidRow(
            column(4, fileInput("dv_saccade_file", "Saccade Report", accept = c(".xls", ".xlsx", ".csv", ".txt"))),
            column(4, fileInput("dv_timecourse_file", "Time Course Report", accept = c(".xls", ".xlsx", ".csv", ".txt"))),
            column(4, br(), actionButton("run_dv_compare", "运行对齐检查", class = "btn-primary"), downloadButton("download_dv_alignment", "下载对齐报告"))
          ),
          h4("Trial Mapping"), DTOutput("dv_trial_mapping_tbl"),
          h4("Event Time Compare"), DTOutput("dv_event_compare_tbl"),
          h4("Fixation Count Compare"), DTOutput("dv_fix_count_tbl"),
          h4("Pupil Mean Compare"), DTOutput("dv_pupil_compare_tbl"),
          h4("Warnings"), DTOutput("dv_warnings_tbl")
        ),
        tabPanel("导出", br(), fluidRow(column(5, uiOutput("report_download_ui"), downloadButton("download_csv", "导出所选 CSV")), column(5, selectInput("png_plot", "PNG 图像", choices = c("事件时间线" = "timeline", "Scanpath" = "scanpath", "Heatmap" = "heatmap", "瞳孔曲线" = "pupil", "AOI 叠加" = "aoi"))), column(2, br(), downloadButton("download_png", "导出 PNG"))), hr(), DTOutput("export_inventory_tbl"))
      )
    )
  )
)

server <- function(input, output, session) {
  parsed_items <- reactiveVal(list())
  report_items <- reactiveVal(list())
  parsed_file_info <- reactiveVal(data.table(name = character(), size = numeric()))
  aoi_dt <- reactiveVal(empty_aoi())
  behavior_items <- reactiveVal(list())
  behavior_dt <- reactiveVal(data.table())
  formal_package_items <- reactiveVal(list())
  reference_imgs <- reactiveVal(list())
  dv_alignment <- reactiveVal(list())
  dv_alignment_file <- reactiveVal(NULL)
  dynamic_aoi_validator_module_server("dynamic_validator", package_reactive = reactive({
    packages <- formal_package_items()
    if (length(packages) == 0) NULL else packages[[length(packages)]]
  }))

  observeEvent(input$load_formal_package, {
    req(nzchar(trimws(input$formal_package_dir %||% "")))
    root <- trimws(input$formal_package_dir)
    withProgress(message = "正在加载正式被试目录...", value = 0, {
      pkg <- read_formal_participant_package(root, keep_samples = TRUE, progress = function(detail, value) {
        setProgress(value = min(0.72, value * 0.72), detail = detail)
      })
      incProgress(0.08, detail = "生成 EXP1 / EXP2 报告")
      reports <- formal_package_reports(pkg, bin_ms = input$bin_ms, baseline_ms = input$baseline_ms)
      label <- paste0(pkg$participant, " [formal]")
      parsed_list <- parsed_items(); parsed_list[[label]] <- pkg$parsed; parsed_items(parsed_list)
      reports_list <- report_items(); reports_list[[label]] <- with_source(reports, label); report_items(reports_list)
      packages <- formal_package_items(); packages[[label]] <- pkg; formal_package_items(packages)
      info <- parsed_file_info()
      asc_size <- first_non_na(pkg$inventory[type == "asc"]$size, NA_real_)
      info <- info[name != label]
      parsed_file_info(rbindlist(list(info, data.table(name = label, size = asc_size)), fill = TRUE))
      if (nrow(pkg$exp1_behavior) > 0) {
        items <- behavior_items(); items[[paste0(label, "_exp1")]] <- pkg$exp1_behavior
        behavior_items(items); behavior_dt(rbindlist(items, fill = TRUE))
      }
      updateSelectInput(session, "active_file", choices = names(parsed_list), selected = label)
      incProgress(0.20, detail = "正式被试目录加载完成")
    })
    showNotification("正式被试目录已加载；动态 AOI 正式结果已加入导出表。", type = "message")
  })

  observeEvent(input$reference_file, {
    req(input$reference_file)
    refs <- reference_imgs()
    for (i in seq_len(nrow(input$reference_file))) refs[[input$reference_file$name[i]]] <- read_reference_image(input$reference_file$datapath[i])
    reference_imgs(refs)
    first_ref <- if (length(refs) > 0) names(refs)[[1]] else ""
    updateSelectInput(session, "reference_select", choices = blank_reference_choices(refs), selected = input$reference_select %||% first_ref)
  })

  current_reference_id <- reactive(input$reference_select %||% "")
  current_reference_img <- reactive({
    id <- current_reference_id()
    refs <- reference_imgs()
    if (!nzchar(id) || is.null(refs[[id]])) NULL else refs[[id]]
  })

  observeEvent(input$project_file, {
    req(input$project_file)
    obj <- readRDS(input$project_file$datapath)
    if (!is.null(obj$parsed_items)) parsed_items(obj$parsed_items)
    if (!is.null(obj$report_items)) report_items(obj$report_items)
    if (!is.null(obj$parsed_file_info)) parsed_file_info(as.data.table(obj$parsed_file_info))
    if (!is.null(obj$aoi)) aoi_dt(normalize_aoi(obj$aoi))
    if (!is.null(obj$behavior)) behavior_dt(as.data.table(obj$behavior))
    if (!is.null(obj$behavior_items)) behavior_items(obj$behavior_items)
    if (!is.null(obj$formal_package_items)) formal_package_items(obj$formal_package_items)
    if (!is.null(obj$reference_imgs)) {
      reference_imgs(obj$reference_imgs)
      first_ref <- if (length(obj$reference_imgs) > 0) names(obj$reference_imgs)[[1]] else ""
      updateSelectInput(session, "reference_select", choices = blank_reference_choices(obj$reference_imgs), selected = first_ref)
    }
    if (!is.null(obj$bin_ms)) updateNumericInput(session, "bin_ms", value = obj$bin_ms)
    if (!is.null(obj$baseline_ms)) updateNumericInput(session, "baseline_ms", value = obj$baseline_ms)
    if (!is.null(obj$aoi_method)) updateSelectInput(session, "aoi_method", selected = obj$aoi_method)
    if (!is.null(obj$parsed_items) && length(obj$parsed_items) > 0) {
      updateSelectInput(session, "active_file", choices = names(obj$parsed_items), selected = names(obj$parsed_items)[[1]])
    }
  })

  observeEvent(input$parse_btn, {
    parsed_list <- parsed_items()
    reports_list <- report_items()
    if (is.null(parsed_list)) parsed_list <- list()
    if (is.null(reports_list)) reports_list <- list()
    current_info <- parsed_file_info()
    if (is.null(current_info)) current_info <- data.table(name = character(), size = numeric())
    asc_to_parse <- data.table()
    if (!is.null(input$asc_files) && nrow(input$asc_files) > 0) {
      asc_files <- as.data.table(input$asc_files)
      asc_files[, size := as.numeric(size)]
      asc_to_parse <- asc_files[!mapply(function(nm, sz) any(current_info$name == nm & current_info$size == sz), name, size)]
    }
    if (nrow(asc_to_parse) > 0) withProgress(message = "正在解析 ASC...", value = 0, {
      for (i in seq_len(nrow(asc_to_parse))) {
        label <- asc_to_parse$name[i]
        file_span <- 1 / nrow(asc_to_parse)
        last_parse_value <- 0
        incProgress(file_span * 0.02, detail = paste(label, "准备解析"))
        p <- parse_asc(asc_to_parse$datapath[i], progress = function(detail, value) {
          value <- max(last_parse_value, min(1, value))
          incProgress((value - last_parse_value) * file_span * 0.76, detail = paste(label, detail))
          last_parse_value <<- value
        })
        p$metadata$source_file <- label
        parsed_list[[label]] <- p
        incProgress(file_span * 0.08, detail = paste(label, "生成统计报表"))
        reports_list[[label]] <- with_source(compute_reports(p, bin_ms = input$bin_ms, baseline_ms = input$baseline_ms), label)
        current_info <- current_info[name != label]
        current_info <- rbindlist(list(current_info, data.table(name = label, size = asc_to_parse$size[i])), fill = TRUE)
        incProgress(file_span * 0.14, detail = paste(label, "完成"))
      }
    })
    if (!is.null(input$aoi_file)) aoi_dt(normalize_aoi(fread(input$aoi_file$datapath, encoding = "UTF-8")))
    if (!is.null(input$behavior_file)) {
      items <- behavior_items()
      if (is.null(items)) items <- list()
      for (i in seq_len(nrow(input$behavior_file))) {
        b <- read_behavior(input$behavior_file$datapath[i])
        data.table::set(b, j = "source_file", value = input$behavior_file$name[i])
        items[[input$behavior_file$name[i]]] <- b
      }
      behavior_items(items)
      behavior_dt(rbindlist(items, fill = TRUE))
    }
    parsed_items(parsed_list)
    report_items(reports_list)
    parsed_file_info(current_info)
    if (nrow(asc_to_parse) > 0) {
      updateSelectInput(session, "active_file", choices = names(parsed_list), selected = asc_to_parse$name[nrow(asc_to_parse)])
    }
  })

  active_name <- reactive({
    nms <- names(parsed_items())
    if (length(nms) == 0) return(NULL)
    input$active_file %||% nms[[1]]
  })

  active_parsed <- reactive({
    nm <- active_name()
    if (is.null(nm)) return(NULL)
    parsed_items()[[nm]]
  })

  active_reports_base <- reactive({
    nm <- active_name()
    if (is.null(nm)) return(list())
    report_items()[[nm]]
  })

  reports_for_item <- function(p, rep) {
    if (is.null(p) || length(rep) == 0) return(list())
    out <- rep
    out$aoi_definition <- aoi_dt()
    out$aoi_report <- if (nrow(aoi_dt()) > 0) compute_aoi_report(p, aoi_dt(), method = input$aoi_method) else data.table()
    if (nrow(behavior_dt()) > 0) {
      out$behavior_check_report <- behavior_check(p, behavior_dt())
      out$merged_eye_behavior_report <- merge_eye_behavior_report(out, behavior_dt())
      out$condition_summary <- condition_summary(out$merged_eye_behavior_report)
    }
    out$metric_dictionary <- metric_dictionary()
    out
  }

  current_reports <- reactive({
    reports_for_item(active_parsed(), active_reports_base())
  })

  selected_trial <- reactive({
    x <- input$trial_select
    if (is.null(x)) x <- "__all__"
    if (identical(x, "__all__")) "" else x
  })

  selected_experiment <- reactive({
    x <- input$experiment_select
    if (is.null(x)) x <- "__all__"
    if (identical(x, "__all__")) "" else x
  })

  selected_phase <- reactive({
    x <- input$phase_select
    if (is.null(x)) x <- "__all__"
    if (identical(x, "__all__")) "" else x
  })

  bind_value <- function(x) {
    x <- x %||% ""
    x <- x[nzchar(x)]
    if (length(x) == 0) "" else paste(x, collapse = ";")
  }
  selected_aoi_participant <- reactive(bind_value(input$aoi_participant_bind))
  selected_aoi_experiment <- reactive(bind_value(input$aoi_experiment_bind))
  selected_aoi_condition <- reactive(bind_value(input$aoi_condition_bind))
  selected_aoi_trial <- reactive(bind_value(input$aoi_trial_bind))
  selected_aoi_phase <- reactive(bind_value(input$aoi_phase_bind))

  active_participant <- reactive({
    p <- active_parsed()
    if (is.null(p)) return("")
    p$metadata$participant %||% ""
  })

  selected_trial_condition <- reactive({
    p <- active_parsed()
    tr <- selected_trial()
    if (is.null(p) || !nzchar(tr)) return("")
    first_non_na(p$trials[trial_id == tr]$condition, "")
  })

  selected_trial_experiment <- reactive({
    p <- active_parsed()
    tr <- selected_trial()
    if (is.null(p) || !nzchar(tr)) return(selected_experiment())
    first_non_na(p$trials[trial_id == tr]$experiment, selected_experiment())
  })

  analysis_view <- reactive({
    req(active_parsed(), current_reports())
    filtered_analysis(active_parsed(), current_reports(), selected_experiment(), selected_trial(), selected_phase())
  })

  filtered_table <- function(x, use_phase = TRUE) {
    if (is.null(x) || !is.data.frame(x) || nrow(x) == 0) return(x)
    dt <- data.table::copy(data.table::as.data.table(x))
    ex <- selected_experiment()
    tr <- selected_trial()
    ph <- selected_phase()
    if (nzchar(ex) && "experiment" %in% names(dt)) dt <- dt[dt$experiment == ex]
    if (nzchar(tr) && "trial_id" %in% names(dt)) dt <- dt[dt$trial_id == tr]
    if (use_phase && nzchar(ph) && "phase" %in% names(dt)) dt <- dt[dt$phase == ph]
    dt
  }

  output$active_file_ui <- renderUI({
    nms <- names(parsed_items())
    if (length(nms) == 0) return(helpText("尚未解析 ASC 文件。"))
    selected <- input$active_file
    if (is.null(selected) || !selected %in% nms) selected <- nms[[1]]
    selectInput("active_file", "当前查看文件", choices = nms, selected = selected)
  })

  output$pending_upload_ui <- renderUI({
    files <- input$asc_files
    if (is.null(files) || nrow(files) == 0) return(helpText("本次未选择新的 ASC；再次浏览只会改变待解析列表，不会清空已解析结果。"))
    tags$div(
      tags$small(tags$b("本次待解析 / 追加：")),
      tags$ul(lapply(files$name, function(x) tags$li(tags$small(x))))
    )
  })

  output$behavior_inventory_ui <- renderUI({
    pending <- input$behavior_file
    loaded <- names(behavior_items())
    tags$div(
      if (!is.null(pending) && nrow(pending) > 0) tags$div(
        tags$small(tags$b("本次待追加答题 CSV：")),
        tags$ul(lapply(pending$name, function(x) tags$li(tags$small(x))))
      ),
      if (length(loaded) > 0) tags$div(
        tags$small(tags$b(sprintf("已加载答题 CSV：%d 个", length(loaded)))),
        tags$ul(lapply(loaded, function(nm) {
          rows <- nrow(behavior_items()[[nm]])
          tags$li(tags$small(sprintf("%s | rows: %s", nm, rows)))
        }))
      ) else tags$small("尚未加载答题 CSV。")
    )
  })

  output$parsed_file_inventory_ui <- renderUI({
    items <- parsed_items()
    nms <- names(items)
    if (length(nms) == 0) return(NULL)
    tags$div(
      tags$small(tags$b(sprintf("已解析 ASC：%d 个", length(nms)))),
      tags$ul(lapply(nms, function(nm) {
        p <- items[[nm]]
        label <- sprintf("%s | trials: %s | phases: %s", nm, nrow(p$trials), nrow(p$phases))
        tags$li(tags$small(label))
      }))
    )
  })

  observeEvent(active_parsed(), {
    p <- active_parsed()
    if (is.null(p)) return()
    updateSelectInput(session, "experiment_select", choices = c("All" = "__all__", unique(p$trials$experiment)), selected = "__all__")
    updateSelectInput(session, "trial_select", choices = c("All" = "__all__", unique(p$trials$trial_id)), selected = "__all__")
    updateSelectInput(session, "phase_select", choices = c("All" = "__all__", unique(p$phases$phase)), selected = "__all__")
    updateSelectInput(session, "aoi_participant_bind", choices = c("All" = "", unique(p$trials$participant)), selected = character())
    updateSelectInput(session, "aoi_experiment_bind", choices = c("All" = "", unique(p$trials$experiment)), selected = character())
    updateSelectInput(session, "aoi_condition_bind", choices = c("All" = "", unique(p$trials$condition)), selected = character())
    updateSelectInput(session, "aoi_trial_bind", choices = c("All" = "", unique(p$trials$trial_id)), selected = character())
    updateSelectInput(session, "aoi_phase_bind", choices = c("All" = "", unique(p$phases$phase)), selected = character())
  }, ignoreNULL = TRUE)

  observeEvent(input$experiment_select, {
    p <- active_parsed()
    if (is.null(p)) return()
    ex <- selected_experiment()
    trials <- if (nzchar(ex)) p$trials[experiment == ex]$trial_id else p$trials$trial_id
    phases <- if (nzchar(ex)) p$phases[experiment == ex]$phase else p$phases$phase
    updateSelectInput(session, "trial_select", choices = c("All" = "__all__", unique(trials)), selected = "__all__")
    updateSelectInput(session, "phase_select", choices = c("All" = "__all__", unique(phases)), selected = "__all__")
  }, ignoreInit = TRUE)

  output$filter_status <- renderPrint({
    req(active_parsed())
    cat("当前筛选 Experiment:", ifelse(nzchar(selected_experiment()), selected_experiment(), "All"), "\n")
    cat("当前筛选 Trial:", ifelse(nzchar(selected_trial()), selected_trial(), "All"), "\n")
    cat("当前筛选 Phase:", ifelse(nzchar(selected_phase()), selected_phase(), "All"), "\n")
  })

  output$workflow_tbl <- renderDT(datatable(workflow_table(), rownames = FALSE, options = list(dom = "t", scrollX = TRUE)))

  output$status <- renderPrint({
    p <- active_parsed()
    if (is.null(p)) {
      cat("请上传 ASC 文件并点击“解析 / 更新分析”。")
    } else {
      cat("当前文件：", p$metadata$source_file, "\n")
      cat("采样率：", p$metadata$sampling_rate, "Hz\n")
      cat("记录眼：", p$metadata$eye, "\n")
      cat("Samples:", nrow(p$samples), "\nFixations:", nrow(p$fixations), "\nSaccades:", nrow(p$saccades), "\nBlinks:", nrow(p$blinks), "\nTrials:", nrow(p$trials), "\n")
    }
  })

  render_report <- function(name, max_rows = NULL) {
    renderDT({
      rep <- current_reports()
      req(rep[[name]])
      x <- rep[[name]]
      if (!is.null(max_rows)) x <- head(x, max_rows)
      datatable(x, filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 12))
    })
  }

  output$metadata_tbl <- render_report("metadata")
  output$quality_tbl <- render_report("quality_report")
  output$package_inventory_tbl <- render_report("package_inventory")
  output$package_warning_tbl <- renderDT({
    rep <- current_reports()
    pieces <- list(rep$phase_quality_report, rep$dynamic_aoi_alignment_report)
    pieces <- pieces[vapply(pieces, is.data.frame, logical(1))]
    req(length(pieces) > 0)
    datatable(rbindlist(pieces, fill = TRUE), filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 10))
  })
  output$trial_report_tbl <- renderDT({
    rep <- analysis_view()$reports
    req(rep$trial_report)
    datatable(rep$trial_report, filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 12))
  })
  output$phase_report_tbl <- renderDT({
    rep <- analysis_view()$reports
    req(rep$phase_report)
    datatable(rep$phase_report, filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 12))
  })
  output$metric_tbl <- render_report("metric_dictionary")
  output$fix_tbl <- render_report("fixation_report", 800)
  output$sac_tbl <- render_report("saccade_report", 800)
  output$blink_tbl <- render_report("blink_report", 800)
  output$event_tbl <- render_report("event_report", 800)

  output$trials_tbl <- renderDT({ req(active_parsed()); datatable(active_parsed()$trials, filter = "top", rownames = FALSE, options = list(scrollX = TRUE)) })
  output$phases_tbl <- renderDT({ req(active_parsed()); datatable(active_parsed()$phases, filter = "top", rownames = FALSE, options = list(scrollX = TRUE)) })

  output$timeline_plot <- renderPlotly({
    req(analysis_view())
    tr <- selected_trial()
    ph <- selected_phase()
    ggplotly(safe_timeline(analysis_view()$parsed, ""), tooltip = c("x", "y", "linewidth")) %>%
      layout(dragmode = "zoom", title = list(text = paste("事件时间线 - Trial:", ifelse(nzchar(tr), tr, "All"), "Phase:", ifelse(nzchar(ph), ph, "All"))))
  })
  output$scanpath_plot <- renderPlotly({
    req(analysis_view())
    tr <- selected_trial()
    ph <- selected_phase()
    ggplotly(safe_scanpath(analysis_view()$parsed, "", "", current_reference_img()), tooltip = c("x", "y", "size", "label")) %>%
      layout(dragmode = "zoom", title = list(text = paste("注视路径 - Trial:", ifelse(nzchar(tr), tr, "All"), "Phase:", ifelse(nzchar(ph), ph, "All"))))
  })
  output$heatmap_plot <- renderPlotly({
    req(analysis_view())
    tr <- selected_trial()
    ph <- selected_phase()
    ggplotly(safe_heatmap(analysis_view()$parsed, "", "", current_reference_img()), tooltip = c("x", "y", "fill")) %>%
      layout(dragmode = "zoom", title = list(text = paste("眼动热图 - Trial:", ifelse(nzchar(tr), tr, "All"), "Phase:", ifelse(nzchar(ph), ph, "All"))))
  })
  output$pupil_plot <- renderPlotly({
    req(analysis_view())
    tr <- selected_trial()
    ph <- selected_phase()
    ggplotly(safe_pupil_curve(analysis_view()$reports, "", ""), tooltip = c("x", "y", "colour")) %>%
      layout(dragmode = "zoom", title = list(text = paste("瞳孔变化曲线 - Trial:", ifelse(nzchar(tr), tr, "All"), "Phase:", ifelse(nzchar(ph), ph, "All"))))
  })

  aoi_time_markers <- reactive({
    p <- active_parsed()
    if (is.null(p)) return(data.table())
    tr <- selected_trial()
    ph <- selected_phase()
    phases <- copy(p$phases)
    events <- copy(p$events)
    if (nzchar(tr)) {
      phases <- phases[trial_id == tr]
      events <- events[trial_id == tr]
    }
    if (nzchar(ph)) phases <- phases[phase == ph]
    phase_marks <- rbindlist(list(
      phases[, .(source = "phase_start", label = paste(phase_instance, "start"), trial_id, phase, time = start_time)],
      phases[, .(source = "phase_end", label = paste(phase_instance, "end"), trial_id, phase, time = end_time)]
    ), fill = TRUE)
    event_marks <- events[, .(source = "event", label = ifelse(is.na(q) | q == "", event_name, paste0(event_name, "_q", q)), trial_id, phase = NA_character_, time)]
    out <- rbindlist(list(phase_marks, event_marks), fill = TRUE)
    if (nrow(out) == 0) return(out)
    out <- unique(out[is.finite(time)], by = c("source", "label", "trial_id", "time"))
    setorder(out, trial_id, time, source)
    out
  })

  output$aoi_time_markers_tbl <- renderDT({
    datatable(aoi_time_markers(), selection = "single", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 6))
  })

  selected_marker_time <- reactive({
    idx <- input$aoi_time_markers_tbl_rows_selected
    marks <- aoi_time_markers()
    if (length(idx) != 1 || nrow(marks) < idx) return(NA_real_)
    marks$time[idx]
  })

  observeEvent(input$time_to_start, {
    t <- selected_marker_time()
    if (is.finite(t)) updateNumericInput(session, "aoi_time_start", value = t)
  })

  observeEvent(input$time_to_end, {
    t <- selected_marker_time()
    if (is.finite(t)) updateNumericInput(session, "aoi_time_end", value = t)
  })

  editing_aoi_row <- reactiveVal(NA_integer_)

  selected_aoi_index <- reactive({
    idx <- editing_aoi_row()
    if (length(idx) == 1 && nrow(aoi_dt()) >= idx) idx else NA_integer_
  })

  load_aoi_row_to_inputs <- function(row) {
    updateTextInput(session, "aoi_group", value = row$aoi_group_id)
    updateTextInput(session, "aoi_name", value = row$aoi_name)
    updateTextInput(session, "aoi_shape_id", value = row$shape_id)
    if ("reference_id" %in% names(row)) updateSelectInput(session, "reference_select", selected = row$reference_id)
    split_bind <- function(x) { x <- x %||% ""; if (!nzchar(x)) character() else unlist(strsplit(x, "\\s*[;,|]\\s*")) }
    updateSelectInput(session, "aoi_participant_bind", selected = split_bind(row$participant))
    updateSelectInput(session, "aoi_experiment_bind", selected = split_bind(row$experiment))
    updateSelectInput(session, "aoi_condition_bind", selected = split_bind(row$condition))
    updateSelectInput(session, "aoi_trial_bind", selected = split_bind(row$trial_id))
    updateSelectInput(session, "aoi_phase_bind", selected = split_bind(row$phase))
    if ("time_start_event" %in% names(row)) updateSelectInput(session, "aoi_time_start_event", selected = row$time_start_event)
    if ("time_end_event" %in% names(row)) updateSelectInput(session, "aoi_time_end_event", selected = row$time_end_event)
    updateNumericInput(session, "circle_radius", value = ifelse(is.na(row$radius), input$circle_radius, row$radius))
    updateNumericInput(session, "aoi_time_start", value = row$time_start)
    updateNumericInput(session, "aoi_time_end", value = row$time_end)
    updateNumericInput(session, "aoi_priority", value = row$priority)
    updateCheckboxInput(session, "aoi_enabled", value = isTRUE(row$enabled))
  }

  aoi_binding_summary <- reactive({
    dt <- normalize_aoi(aoi_dt())
    if (nrow(dt) == 0) return(data.table())
    dt[, row_id := seq_len(.N)]
    idx <- selected_aoi_index()
    selected_label <- "全部 AOI"
    if (is.finite(idx)) {
      row <- dt[idx]
      selected_label <- paste(row$aoi_group_id, row$shape_id, sep = " / ")
      dt <- dt[
        aoi_group_id == row$aoi_group_id &
          shape_id == row$shape_id &
          reference_id == row$reference_id
      ]
    }
    out <- copy(dt)
    out[, binding_scope := fifelse(!nzchar(participant) & !nzchar(trial_id), "全局/模板",
      fifelse(grepl("[;,|]", participant) | grepl("[;,|]", trial_id), "批量规则", "单被试-trial")
    )]
    out[, selected_aoi := selected_label]
    out[, time_window := fifelse(
      nzchar(time_start_event) | nzchar(time_end_event),
      paste0(ifelse(nzchar(time_start_event), time_start_event, "manual"), " -> ", ifelse(nzchar(time_end_event), time_end_event, "manual")),
      paste0(ifelse(is.na(time_start), "All", as.character(time_start)), " -> ", ifelse(is.na(time_end), "All", as.character(time_end)))
    )]
    cols <- c("row_id", "selected_aoi", "binding_scope", "enabled", "aoi_group_id", "aoi_name", "shape_id", "reference_id", "participant", "experiment", "trial_id", "condition", "phase", "time_window")
    out <- out[, ..cols]
    setorder(out, -enabled, binding_scope, participant, condition, trial_id, phase)
    out
  })

  selected_binding_row_id <- reactive({
    idx <- input$aoi_binding_summary_tbl_rows_selected
    x <- aoi_binding_summary()
    if (length(idx) != 1 || nrow(x) < idx) return(NA_integer_)
    x$row_id[idx]
  })

  observeEvent(input$aoi_tbl_rows_selected, {
    idx <- input$aoi_tbl_rows_selected
    if (length(idx) == 1) editing_aoi_row(idx)
    idx <- selected_aoi_index()
    if (!is.finite(idx)) return()
    row <- aoi_dt()[idx]
    load_aoi_row_to_inputs(row)
  })

  observeEvent(input$load_aoi_binding, {
    row_id <- selected_binding_row_id()
    if (!is.finite(row_id)) {
      showNotification("请先在绑定情况表中选中一条绑定记录。", type = "warning")
      return()
    }
    dt <- aoi_dt()
    if (nrow(dt) < row_id) return()
    editing_aoi_row(row_id)
    load_aoi_row_to_inputs(dt[row_id])
    showNotification(sprintf("已载入第 %s 条 AOI 绑定，可修改后点击“更新选中 AOI”。", row_id), type = "message")
  })

  new_aoi_row <- function(shape_type, coords) {
    old <- aoi_dt()
    custom_id <- trimws(input$aoi_shape_id %||% "")
    id <- if (nzchar(custom_id)) custom_id else paste0(input$aoi_group %||% "aoi", "_", nrow(old) + 1)
    data.table(
      aoi_group_id = input$aoi_group %||% "aoi_1",
      aoi_name = input$aoi_name %||% input$aoi_group %||% "AOI",
      shape_id = id,
      reference_id = current_reference_id(),
      shape_type = shape_type,
      x_min = coords$x_min, y_min = coords$y_min, x_max = coords$x_max, y_max = coords$y_max,
      center_x = coords$center_x, center_y = coords$center_y, radius = coords$radius,
      participant = selected_aoi_participant(), experiment = selected_aoi_experiment(), trial_id = selected_aoi_trial(), condition = selected_aoi_condition(), phase = selected_aoi_phase(),
      time_start = input$aoi_time_start, time_end = input$aoi_time_end,
      time_start_event = input$aoi_time_start_event %||% "", time_end_event = input$aoi_time_end_event %||% "",
      priority = input$aoi_priority %||% 0, enabled = isTRUE(input$aoi_enabled)
    )
  }

  observeEvent(input$aoi_brush, {
    req(active_parsed(), input$aoi_brush)
    b <- input$aoi_brush
    row <- new_aoi_row("rectangle", list(x_min = b$xmin, y_min = b$ymin, x_max = b$xmax, y_max = b$ymax, center_x = NA_real_, center_y = NA_real_, radius = NA_real_))
    aoi_dt(normalize_aoi(rbindlist(list(aoi_dt(), row), fill = TRUE)))
  })

  observeEvent(input$add_circle, {
    req(active_parsed(), input$aoi_click)
    row <- new_aoi_row("circle", list(x_min = NA_real_, y_min = NA_real_, x_max = NA_real_, y_max = NA_real_, center_x = input$aoi_click$x, center_y = input$aoi_click$y, radius = input$circle_radius))
    aoi_dt(normalize_aoi(rbindlist(list(aoi_dt(), row), fill = TRUE)))
  })

  observeEvent(input$update_aoi, {
    idx <- selected_aoi_index()
    if (!is.finite(idx)) return()
    dt <- copy(aoi_dt())
    dt[idx, `:=`(
      aoi_group_id = input$aoi_group %||% aoi_group_id,
      aoi_name = input$aoi_name %||% aoi_name,
      shape_id = ifelse(nzchar(trimws(input$aoi_shape_id %||% "")), trimws(input$aoi_shape_id), shape_id),
      reference_id = current_reference_id(),
      participant = selected_aoi_participant(),
      experiment = selected_aoi_experiment(),
      trial_id = selected_aoi_trial(),
      condition = selected_aoi_condition(),
      phase = selected_aoi_phase(),
      time_start = input$aoi_time_start,
      time_end = input$aoi_time_end,
      time_start_event = input$aoi_time_start_event %||% "",
      time_end_event = input$aoi_time_end_event %||% "",
      priority = input$aoi_priority %||% priority,
      enabled = isTRUE(input$aoi_enabled)
    )]
    if (dt$shape_type[idx] == "circle") dt[idx, radius := input$circle_radius]
    aoi_dt(normalize_aoi(dt))
  })

  observeEvent(input$duplicate_aoi_time, {
    idx <- selected_aoi_index()
    if (!is.finite(idx)) return()
    dt <- copy(aoi_dt())
    row <- copy(dt[idx])
    row[, `:=`(
      aoi_group_id = input$aoi_group %||% aoi_group_id,
      aoi_name = input$aoi_name %||% aoi_name,
      shape_id = ifelse(nzchar(trimws(input$aoi_shape_id %||% "")), trimws(input$aoi_shape_id), shape_id),
      reference_id = current_reference_id(),
      participant = selected_aoi_participant(),
      experiment = selected_aoi_experiment(),
      trial_id = selected_aoi_trial(),
      condition = selected_aoi_condition(),
      phase = selected_aoi_phase(),
      time_start = input$aoi_time_start,
      time_end = input$aoi_time_end,
      time_start_event = input$aoi_time_start_event %||% "",
      time_end_event = input$aoi_time_end_event %||% "",
      priority = input$aoi_priority %||% priority,
      enabled = isTRUE(input$aoi_enabled)
    )]
    aoi_dt(normalize_aoi(rbindlist(list(dt, row), fill = TRUE)))
  })

  observeEvent(input$bind_current_trial_aoi, {
    idx <- selected_aoi_index()
    tr <- selected_trial()
    if (!is.finite(idx)) {
      showNotification("请先在 AOI 表中选中一条已有 AOI。", type = "warning")
      return()
    }
    if (!nzchar(tr)) {
      showNotification("请先在左侧 Trial 下拉框中选择一个具体 Trial，不能使用 All。", type = "warning")
      return()
    }
    dt <- copy(aoi_dt())
    row <- copy(dt[idx])
    source_is_template <- !nzchar(dt$participant[idx] %||% "") && !nzchar(dt$trial_id[idx] %||% "")
    row[, `:=`(
      participant = active_participant(),
      experiment = selected_trial_experiment(),
      trial_id = tr,
      condition = selected_trial_condition(),
      phase = selected_aoi_phase(),
      time_start = input$aoi_time_start,
      time_end = input$aoi_time_end,
      time_start_event = input$aoi_time_start_event %||% "",
      time_end_event = input$aoi_time_end_event %||% "",
      priority = input$aoi_priority %||% priority,
      enabled = TRUE
    )]
    keys <- c("aoi_group_id", "shape_id", "participant", "experiment", "trial_id", "condition", "phase", "time_start_event", "time_end_event")
    keys <- intersect(keys, names(dt))
    if (length(keys) > 0 && nrow(dt) > 0) {
      dt[, .row_key := do.call(paste, c(.SD, sep = "\r")), .SDcols = keys]
      row[, .row_key := do.call(paste, c(.SD, sep = "\r")), .SDcols = keys]
      if (row$.row_key[1] %in% dt$.row_key) {
        row_key <- row$.row_key[1]
        row[, .row_key := NULL]
        update_cols <- intersect(names(row), names(dt))
        dt[.row_key == row_key, (update_cols) := row[, ..update_cols]]
        if (source_is_template) dt[idx, enabled := FALSE]
        dt[, .row_key := NULL]
        aoi_dt(normalize_aoi(dt))
        showNotification(sprintf("已更新 %s / %s 的 AOI 绑定。", active_participant(), tr), type = "message")
        return()
      }
      dt[, .row_key := NULL]
      row[, .row_key := NULL]
    }
    if (source_is_template) dt[idx, enabled := FALSE]
    aoi_dt(normalize_aoi(rbindlist(list(dt, row), fill = TRUE)))
    showNotification(sprintf("已新增 %s / %s 的 AOI 绑定。", active_participant(), tr), type = "message")
  })

  observeEvent(input$delete_aoi, {
    idx <- selected_aoi_index()
    if (!is.finite(idx)) return()
    dt <- copy(aoi_dt())
    aoi_dt(if (nrow(dt) == 1) empty_aoi() else normalize_aoi(dt[-idx]))
    editing_aoi_row(NA_integer_)
  })

  observeEvent(input$delete_aoi_binding, {
    row_id <- selected_binding_row_id()
    if (!is.finite(row_id)) {
      showNotification("请先在绑定情况表中选中一条绑定记录。", type = "warning")
      return()
    }
    dt <- copy(aoi_dt())
    if (nrow(dt) < row_id) return()
    deleted <- dt[row_id]
    aoi_dt(if (nrow(dt) == 1) empty_aoi() else normalize_aoi(dt[-row_id]))
    editing_aoi_row(NA_integer_)
    showNotification(sprintf("已删除 %s / %s / %s 的 AOI 绑定。", deleted$participant %||% "All", deleted$trial_id %||% "All", deleted$aoi_group_id), type = "message")
  })

  observeEvent(input$clear_aoi, aoi_dt(empty_aoi()))

  output$aoi_canvas <- renderPlot({ req(active_parsed()); plot_aoi_canvas(active_parsed(), aoi_dt(), current_reference_img(), current_reference_id()) })
  output$aoi_overlay_plot <- renderPlot({ req(active_parsed()); plot_aoi_canvas(active_parsed(), aoi_dt(), current_reference_img(), current_reference_id()) })
  output$aoi_tbl <- renderDT(datatable(aoi_dt(), filter = "top", selection = "single", rownames = FALSE, options = list(scrollX = TRUE)))
  output$aoi_binding_summary_tbl <- renderDT({
    datatable(aoi_binding_summary(), filter = "top", selection = "single", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 8))
  })
  output$aoi_report_tbl <- render_report("aoi_report")
  output$behavior_check_tbl <- render_report("behavior_check_report")
  output$merged_behavior_tbl <- render_report("merged_eye_behavior_report", 1000)
  output$condition_summary_tbl <- render_report("condition_summary")
  output$exp2_alignment_tbl <- render_report("exp2_alignment_report", 1000)
  output$exp2_behavior_tbl <- render_report("exp2_eye_behavior_report", 1000)
  output$exp2_summary_tbl <- render_report("exp2_condition_summary")
  output$dynamic_aoi_alignment_tbl <- render_report("dynamic_aoi_alignment_report")
  output$dynamic_aoi_summary_tbl <- render_report("dynamic_aoi_summary", 1000)

  observeEvent(input$run_dv_compare, {
    req(active_parsed(), current_reports())
    out <- tempfile(fileext = ".xlsx")
    file_path <- function(x) if (is.null(x)) NULL else x$datapath
    sheets <- compare_with_dataviewer(
      parsed = active_parsed(),
      reports = current_reports(),
      dv_trial_file = file_path(input$dv_trial_file),
      dv_message_file = file_path(input$dv_message_file),
      dv_fixation_file = file_path(input$dv_fixation_file),
      dv_saccade_file = file_path(input$dv_saccade_file),
      dv_timecourse_file = file_path(input$dv_timecourse_file),
      out_file = out
    )
    dv_alignment(sheets)
    dv_alignment_file(out)
  })

  render_dv_sheet <- function(name) {
    renderDT({
      x <- dv_alignment()[[name]]
      req(x)
      datatable(x, filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 10))
    })
  }
  output$dv_trial_mapping_tbl <- render_dv_sheet("trial_mapping")
  output$dv_event_compare_tbl <- render_dv_sheet("event_time_compare")
  output$dv_fix_count_tbl <- render_dv_sheet("fixation_count_compare")
  output$dv_pupil_compare_tbl <- render_dv_sheet("pupil_mean_compare")
  output$dv_warnings_tbl <- render_dv_sheet("warnings")

  output$download_dv_alignment <- downloadHandler(
    filename = function() paste0("dv_alignment_report_", Sys.Date(), ".xlsx"),
    content = function(file) {
      req(dv_alignment_file())
      file.copy(dv_alignment_file(), file, overwrite = TRUE)
    }
  )

  output$report_download_ui <- renderUI({
    rep <- current_reports()
    choices <- names(rep)[vapply(rep, is.data.frame, logical(1))]
    selectInput("csv_report", "CSV 报表", choices = choices)
  })

  output$export_inventory_tbl <- renderDT({
    rep <- current_reports()
    inv <- data.table(report = names(rep), rows = vapply(rep, function(x) if (is.data.frame(x)) nrow(x) else NA_integer_, integer(1)))
    datatable(inv[!is.na(rows)], rownames = FALSE, options = list(dom = "t", scrollX = TRUE))
  })

  output$download_csv <- downloadHandler(
    filename = function() paste0(input$csv_report %||% "report", ".csv"),
    content = function(file) fwrite(current_reports()[[input$csv_report]], file)
  )

  output$download_aoi_csv <- downloadHandler(
    filename = function() paste0("aoi_definition_", Sys.Date(), ".csv"),
    content = function(file) fwrite(aoi_dt(), file)
  )

  output$download_xlsx <- downloadHandler(
    filename = function() paste0("eyelink_reports_", Sys.Date(), ".xlsx"),
    content = function(file) export_xlsx(current_reports(), file)
  )

  output$download_all_xlsx <- downloadHandler(
    filename = function() paste0("eyelink_reports_all_subjects_", Sys.Date(), ".zip"),
    content = function(file) {
      req(length(parsed_items()) > 0)
      out_dir <- tempfile("eyelink_reports_all_")
      dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
      files <- character()
      nms <- names(parsed_items())
      for (nm in nms) {
        safe_name <- gsub("[^A-Za-z0-9_.-]+", "_", tools::file_path_sans_ext(nm))
        xlsx <- file.path(out_dir, paste0(safe_name, "_reports.xlsx"))
        export_xlsx(reports_for_item(parsed_items()[[nm]], report_items()[[nm]]), xlsx)
        files <- c(files, xlsx)
      }
      old <- setwd(out_dir)
      on.exit(setwd(old), add = TRUE)
      utils::zip(zipfile = file, files = basename(files), flags = "-r9Xj")
    }
  )

  output$download_project <- downloadHandler(
    filename = function() paste0("eyelink_project_", Sys.Date(), ".rds"),
    content = function(file) saveRDS(list(
      parsed_items = parsed_items(),
      report_items = report_items(),
      parsed_file_info = parsed_file_info(),
      aoi = aoi_dt(),
      behavior = behavior_dt(),
      behavior_items = behavior_items(),
      formal_package_items = formal_package_items(),
      reference_imgs = reference_imgs(),
      bin_ms = input$bin_ms,
      baseline_ms = input$baseline_ms,
      aoi_method = input$aoi_method
    ), file)
  )

  output$download_png <- downloadHandler(
    filename = function() paste0(input$png_plot %||% "plot", "_", Sys.Date(), ".png"),
    content = function(file) {
      p <- switch(
        input$png_plot,
        timeline = safe_timeline(analysis_view()$parsed, ""),
        scanpath = safe_scanpath(analysis_view()$parsed, "", "", current_reference_img()),
        heatmap = safe_heatmap(analysis_view()$parsed, "", "", current_reference_img()),
        pupil = safe_pupil_curve(analysis_view()$reports, "", ""),
        aoi = plot_aoi_canvas(active_parsed(), aoi_dt(), current_reference_img(), current_reference_id())
      )
      ggplot2::ggsave(file, p, width = 10, height = 6, dpi = 160, device = ragg::agg_png)
    }
  )
}

shinyApp(ui, server)
