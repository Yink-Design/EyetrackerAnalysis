# EyeLink ASC Analyzer CN
# Run with: shiny::runApp()

options(shiny.maxRequestSize = 1024 * 1024^2)

required_packages <- c("shiny", "DT", "data.table", "ggplot2", "openxlsx", "ggforce", "png", "jpeg", "plotly")
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

empty_aoi <- function() data.table(
  aoi_group_id = character(), aoi_name = character(), shape_id = character(), shape_type = character(),
  x_min = numeric(), y_min = numeric(), x_max = numeric(), y_max = numeric(),
  center_x = numeric(), center_y = numeric(), radius = numeric(),
  participant = character(), trial_id = character(), condition = character(), phase = character(),
  time_start = numeric(), time_end = numeric(), priority = numeric(), enabled = logical()
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

plot_aoi_canvas <- function(parsed, aoi, reference_image = NULL) {
  p <- base_canvas(parsed, reference_image, "AOI canvas aligned to DISPLAY_COORDS")
  if (!is.null(aoi) && nrow(aoi) > 0) {
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
    geom_segment(data = ph, aes(x = rel_start, xend = rel_end, y = phase_instance, yend = phase_instance, linewidth = phase), color = "#2A6FBB") +
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
  if (nrow(ts) == 0) return(ggplot() + ggtitle("当前筛选下无瞳孔时间序列"))
  ggplot(ts, aes(x = bin_start / 1000, y = baseline_corrected_pupil_area, color = phase)) +
    geom_line(linewidth = 0.55, na.rm = TRUE) +
    facet_wrap(~ trial_id, scales = "free_x") +
    labs(x = "阶段内时间 / 秒", y = "基线校正瞳孔面积", title = "瞳孔变化曲线") +
    theme_minimal()
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
  titlePanel("EyeLink ASC 眼动分析工具"),
  sidebarLayout(
    sidebarPanel(
      fileInput("asc_files", "上传 ASC 文件（支持多选）", accept = c(".asc", ".txt"), multiple = TRUE),
      helpText("当前单次上传上限约 1GB。大文件解析时会显示分阶段进度。"),
      fileInput("reference_file", "上传参考图（PNG/JPG，用于 AOI 和叠加图）", accept = c(".png", ".jpg", ".jpeg")),
      fileInput("aoi_file", "上传 AOI CSV（可选）", accept = ".csv"),
      fileInput("behavior_file", "上传答题记录 CSV（可选）", accept = ".csv"),
      fileInput("project_file", "读取项目 RDS（可选）", accept = ".rds"),
      numericInput("bin_ms", "Time-bin 大小 / ms", value = 100, min = 20, step = 10),
      numericInput("baseline_ms", "瞳孔基线窗口 / ms", value = 500, min = 100, step = 100),
      selectInput("aoi_method", "AOI dwell 计算方法", choices = c("fixation", "sample"), selected = "fixation"),
      actionButton("parse_btn", "解析 / 更新分析", class = "btn-primary"),
      hr(),
      uiOutput("active_file_ui"),
      selectInput("trial_select", "Trial", choices = c("All" = "__all__"), selected = "__all__"),
      selectInput("phase_select", "Phase", choices = c("All" = "__all__"), selected = "__all__"),
      hr(),
      downloadButton("download_xlsx", "导出全部 XLSX"),
      downloadButton("download_project", "保存项目 RDS")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("工作流", br(), DTOutput("workflow_tbl")),
        tabPanel("数据概览", br(), verbatimTextOutput("status"), h4("Quality Report"), DTOutput("quality_tbl"), h4("Metadata"), DTOutput("metadata_tbl"), h4("Trials"), DTOutput("trials_tbl"), h4("Phases"), DTOutput("phases_tbl")),
        tabPanel("指标说明", br(), DTOutput("metric_tbl")),
        tabPanel("Trial / Phase 分析", br(), verbatimTextOutput("filter_status"), plotlyOutput("timeline_plot", height = 360), plotlyOutput("scanpath_plot", height = 420), plotlyOutput("heatmap_plot", height = 420), plotlyOutput("pupil_plot", height = 360), h4("Trial Report"), DTOutput("trial_report_tbl"), h4("Phase Report"), DTOutput("phase_report_tbl")),
        tabPanel("AOI 编辑", br(), fluidRow(column(4, textInput("aoi_group", "AOI 组 ID", "aoi_1"), textInput("aoi_name", "AOI 名称", "兴趣区 1"), numericInput("circle_radius", "圆形半径", 80, min = 1), numericInput("aoi_time_start", "AOI 起始时间（可选）", NA), numericInput("aoi_time_end", "AOI 结束时间（可选）", NA), numericInput("aoi_priority", "优先级", 0), checkboxInput("aoi_enabled", "启用 AOI", TRUE), actionButton("add_circle", "在点击位置添加圆形 AOI"), actionButton("clear_aoi", "清空临时 AOI"), downloadButton("download_aoi_csv", "导出 AOI CSV")), column(8, plotOutput("aoi_canvas", height = 560, brush = brushOpts(id = "aoi_brush", resetOnNew = TRUE), click = clickOpts(id = "aoi_click")))), DTOutput("aoi_tbl")),
        tabPanel("AOI 分析", br(), plotOutput("aoi_overlay_plot", height = 460), h4("AOI Report"), DTOutput("aoi_report_tbl")),
        tabPanel("答题合并", br(), h4("时间戳 / 题目匹配检查"), DTOutput("behavior_check_tbl"), h4("眼动 + 行为综合表"), DTOutput("merged_behavior_tbl"), h4("Condition Summary"), DTOutput("condition_summary_tbl")),
        tabPanel("原始报表", br(), h4("Fixation"), DTOutput("fix_tbl"), h4("Saccade"), DTOutput("sac_tbl"), h4("Blink"), DTOutput("blink_tbl"), h4("Messages / Events"), DTOutput("event_tbl")),
        tabPanel("导出", br(), fluidRow(column(5, uiOutput("report_download_ui"), downloadButton("download_csv", "导出所选 CSV")), column(5, selectInput("png_plot", "PNG 图像", choices = c("事件时间线" = "timeline", "Scanpath" = "scanpath", "Heatmap" = "heatmap", "瞳孔曲线" = "pupil", "AOI 叠加" = "aoi"))), column(2, br(), downloadButton("download_png", "导出 PNG"))), hr(), DTOutput("export_inventory_tbl"))
      )
    )
  )
)

server <- function(input, output, session) {
  parsed_items <- reactiveVal(list())
  report_items <- reactiveVal(list())
  aoi_dt <- reactiveVal(empty_aoi())
  behavior_dt <- reactiveVal(data.table())
  reference_img <- reactiveVal(NULL)

  observeEvent(input$reference_file, {
    req(input$reference_file)
    reference_img(read_reference_image(input$reference_file$datapath))
  })

  observeEvent(input$project_file, {
    req(input$project_file)
    obj <- readRDS(input$project_file$datapath)
    if (!is.null(obj$aoi)) aoi_dt(normalize_aoi(obj$aoi))
    if (!is.null(obj$behavior)) behavior_dt(as.data.table(obj$behavior))
  })

  observeEvent(input$parse_btn, {
    req(input$asc_files)
    parsed_list <- list()
    reports_list <- list()
    withProgress(message = "正在解析 ASC...", value = 0, {
      for (i in seq_len(nrow(input$asc_files))) {
        label <- input$asc_files$name[i]
        file_span <- 1 / nrow(input$asc_files)
        last_parse_value <- 0
        incProgress(file_span * 0.02, detail = paste(label, "准备解析"))
        p <- parse_asc(input$asc_files$datapath[i], progress = function(detail, value) {
          value <- max(last_parse_value, min(1, value))
          incProgress((value - last_parse_value) * file_span * 0.76, detail = paste(label, detail))
          last_parse_value <<- value
        })
        p$metadata$source_file <- label
        parsed_list[[label]] <- p
        incProgress(file_span * 0.08, detail = paste(label, "生成统计报表"))
        reports_list[[label]] <- with_source(compute_reports(p, bin_ms = input$bin_ms, baseline_ms = input$baseline_ms), label)
        incProgress(file_span * 0.14, detail = paste(label, "完成"))
      }
    })
    if (!is.null(input$aoi_file)) aoi_dt(normalize_aoi(fread(input$aoi_file$datapath, encoding = "UTF-8")))
    if (!is.null(input$behavior_file)) behavior_dt(read_behavior(input$behavior_file$datapath))
    parsed_items(parsed_list)
    report_items(reports_list)
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

  current_reports <- reactive({
    p <- active_parsed()
    rep <- active_reports_base()
    if (is.null(p) || length(rep) == 0) return(list())
    rep$aoi_definition <- aoi_dt()
    rep$aoi_report <- if (nrow(aoi_dt()) > 0) compute_aoi_report(p, aoi_dt(), method = input$aoi_method) else data.table()
    if (nrow(behavior_dt()) > 0) {
      rep$behavior_check_report <- behavior_check(p, behavior_dt())
      rep$merged_eye_behavior_report <- merge_eye_behavior_report(rep, behavior_dt())
      rep$condition_summary <- condition_summary(rep$merged_eye_behavior_report)
    }
    rep$metric_dictionary <- metric_dictionary()
    rep
  })

  selected_trial <- reactive({
    x <- input$trial_select
    if (is.null(x)) x <- "__all__"
    if (identical(x, "__all__")) "" else x
  })

  selected_phase <- reactive({
    x <- input$phase_select
    if (is.null(x)) x <- "__all__"
    if (identical(x, "__all__")) "" else x
  })

  filtered_table <- function(x, use_phase = TRUE) {
    if (is.null(x) || !is.data.frame(x) || nrow(x) == 0) return(x)
    dt <- data.table::copy(data.table::as.data.table(x))
    tr <- selected_trial()
    ph <- selected_phase()
    if (nzchar(tr) && "trial_id" %in% names(dt)) dt <- dt[dt$trial_id == tr]
    if (use_phase && nzchar(ph) && "phase" %in% names(dt)) dt <- dt[dt$phase == ph]
    dt
  }

  output$active_file_ui <- renderUI({
    nms <- names(parsed_items())
    if (length(nms) == 0) return(helpText("尚未解析 ASC 文件。"))
    selectInput("active_file", "当前查看文件", choices = nms, selected = nms[[1]])
  })

  observeEvent(active_parsed(), {
    p <- active_parsed()
    if (is.null(p)) return()
    updateSelectInput(session, "trial_select", choices = c("All" = "__all__", unique(p$trials$trial_id)), selected = "__all__")
    updateSelectInput(session, "phase_select", choices = c("All" = "__all__", unique(p$phases$phase)), selected = "__all__")
  }, ignoreNULL = TRUE)

  output$filter_status <- renderPrint({
    req(active_parsed())
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
  output$trial_report_tbl <- renderDT({
    rep <- current_reports()
    req(rep$trial_report)
    datatable(filtered_table(rep$trial_report, use_phase = FALSE), filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 12))
  })
  output$phase_report_tbl <- renderDT({
    rep <- current_reports()
    req(rep$phase_report)
    datatable(filtered_table(rep$phase_report, use_phase = TRUE), filter = "top", rownames = FALSE, options = list(scrollX = TRUE, pageLength = 12))
  })
  output$metric_tbl <- render_report("metric_dictionary")
  output$fix_tbl <- render_report("fixation_report", 800)
  output$sac_tbl <- render_report("saccade_report", 800)
  output$blink_tbl <- render_report("blink_report", 800)
  output$event_tbl <- render_report("event_report", 800)

  output$trials_tbl <- renderDT({ req(active_parsed()); datatable(active_parsed()$trials, filter = "top", rownames = FALSE, options = list(scrollX = TRUE)) })
  output$phases_tbl <- renderDT({ req(active_parsed()); datatable(active_parsed()$phases, filter = "top", rownames = FALSE, options = list(scrollX = TRUE)) })

  output$timeline_plot <- renderPlotly({
    req(active_parsed())
    tr <- selected_trial()
    ggplotly(safe_timeline(active_parsed(), tr), tooltip = c("x", "y", "linewidth")) %>%
      layout(dragmode = "zoom", title = list(text = paste("事件时间线 - Trial:", ifelse(nzchar(tr), tr, "All"))))
  })
  output$scanpath_plot <- renderPlotly({
    req(active_parsed())
    tr <- selected_trial()
    ph <- selected_phase()
    ggplotly(safe_scanpath(active_parsed(), tr, ph, reference_img()), tooltip = c("x", "y", "size", "label")) %>%
      layout(dragmode = "zoom", title = list(text = paste("注视路径 - Trial:", ifelse(nzchar(tr), tr, "All"), "Phase:", ifelse(nzchar(ph), ph, "All"))))
  })
  output$heatmap_plot <- renderPlotly({
    req(active_parsed())
    tr <- selected_trial()
    ph <- selected_phase()
    ggplotly(safe_heatmap(active_parsed(), tr, ph, reference_img()), tooltip = c("x", "y", "fill")) %>%
      layout(dragmode = "zoom", title = list(text = paste("眼动热图 - Trial:", ifelse(nzchar(tr), tr, "All"), "Phase:", ifelse(nzchar(ph), ph, "All"))))
  })
  output$pupil_plot <- renderPlotly({
    req(current_reports())
    tr <- selected_trial()
    ph <- selected_phase()
    ggplotly(safe_pupil_curve(current_reports(), tr, ph), tooltip = c("x", "y", "colour")) %>%
      layout(dragmode = "zoom", title = list(text = paste("瞳孔变化曲线 - Trial:", ifelse(nzchar(tr), tr, "All"), "Phase:", ifelse(nzchar(ph), ph, "All"))))
  })

  new_aoi_row <- function(shape_type, coords) {
    old <- aoi_dt()
    id <- paste0(input$aoi_group %||% "aoi", "_", nrow(old) + 1)
    data.table(
      aoi_group_id = input$aoi_group %||% "aoi_1",
      aoi_name = input$aoi_name %||% input$aoi_group %||% "AOI",
      shape_id = id,
      shape_type = shape_type,
      x_min = coords$x_min, y_min = coords$y_min, x_max = coords$x_max, y_max = coords$y_max,
      center_x = coords$center_x, center_y = coords$center_y, radius = coords$radius,
      participant = "", trial_id = selected_trial(), condition = "", phase = selected_phase(),
      time_start = input$aoi_time_start, time_end = input$aoi_time_end, priority = input$aoi_priority %||% 0, enabled = isTRUE(input$aoi_enabled)
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

  observeEvent(input$clear_aoi, aoi_dt(empty_aoi()))

  output$aoi_canvas <- renderPlot({ req(active_parsed()); plot_aoi_canvas(active_parsed(), aoi_dt(), reference_img()) })
  output$aoi_overlay_plot <- renderPlot({ req(active_parsed()); plot_aoi_canvas(active_parsed(), aoi_dt(), reference_img()) })
  output$aoi_tbl <- renderDT(datatable(aoi_dt(), filter = "top", rownames = FALSE, options = list(scrollX = TRUE)))
  output$aoi_report_tbl <- render_report("aoi_report")
  output$behavior_check_tbl <- render_report("behavior_check_report")
  output$merged_behavior_tbl <- render_report("merged_eye_behavior_report", 1000)
  output$condition_summary_tbl <- render_report("condition_summary")

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

  output$download_project <- downloadHandler(
    filename = function() paste0("eyelink_project_", Sys.Date(), ".rds"),
    content = function(file) saveRDS(list(aoi = aoi_dt(), behavior = behavior_dt(), bin_ms = input$bin_ms, baseline_ms = input$baseline_ms, aoi_method = input$aoi_method), file)
  )

  output$download_png <- downloadHandler(
    filename = function() paste0(input$png_plot %||% "plot", "_", Sys.Date(), ".png"),
    content = function(file) {
      p <- switch(
        input$png_plot,
        timeline = safe_timeline(active_parsed(), selected_trial()),
        scanpath = safe_scanpath(active_parsed(), selected_trial(), selected_phase(), reference_img()),
        heatmap = safe_heatmap(active_parsed(), selected_trial(), selected_phase(), reference_img()),
        pupil = safe_pupil_curve(current_reports(), selected_trial(), selected_phase()),
        aoi = plot_aoi_canvas(active_parsed(), aoi_dt(), reference_img())
      )
      ggplot2::ggsave(file, p, width = 10, height = 6, dpi = 160, device = ragg::agg_png)
    }
  )
}

shinyApp(ui, server)
