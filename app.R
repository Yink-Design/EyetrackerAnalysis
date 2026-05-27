# EyeLink ASC Analyzer CN
# Run with: shiny::runApp()

required_packages <- c("shiny", "DT", "data.table", "ggplot2", "openxlsx")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages) > 0) {
  stop("Missing R packages: ", paste(missing_packages, collapse = ", "), ". Run source('install_dependencies.R') first.", call. = FALSE)
}

library(shiny)
library(DT)
library(data.table)
library(ggplot2)

source("R/core.R", encoding = "UTF-8")

empty_aoi <- function() data.table(
  aoi_group_id = character(), aoi_name = character(), shape_id = character(), shape_type = character(),
  x_min = numeric(), y_min = numeric(), x_max = numeric(), y_max = numeric(),
  center_x = numeric(), center_y = numeric(), radius = numeric(),
  participant = character(), trial_id = character(), condition = character(), phase = character(),
  time_start = numeric(), time_end = numeric(), priority = numeric(), enabled = logical()
)

safe_timeline <- function(parsed, trial_id = "") {
  ph <- copy(parsed$phases); ev <- copy(parsed$events)
  if (nzchar(trial_id)) { ph <- ph[ph$trial_id == trial_id]; ev <- ev[ev$trial_id == trial_id] }
  if (nrow(ph) == 0) return(ggplot() + ggtitle("无 phase 数据"))
  t0 <- min(ph$start_time, na.rm = TRUE)
  ph[, `:=`(rel_start = (start_time - t0) / 1000, rel_end = (end_time - t0) / 1000)]
  ev[, rel_time := (time - t0) / 1000]
  ggplot() +
    geom_segment(data = ph, aes(x = rel_start, xend = rel_end, y = phase_instance, yend = phase_instance, linewidth = phase)) +
    geom_point(data = ev, aes(x = rel_time, y = event_name), size = 1.8) +
    labs(x = "相对时间 / 秒", y = "事件 / 阶段", title = "事件时间线") +
    theme_minimal()
}

safe_scanpath <- function(parsed, trial_id = "", phase = "") {
  fx <- copy(parsed$fixations)
  if (nzchar(trial_id)) fx <- fx[fx$trial_id == trial_id]
  if (nzchar(phase)) fx <- fx[fx$phase == phase]
  dc <- parsed$metadata$display_coords
  if (nrow(fx) == 0) return(ggplot() + ggtitle("无注视数据"))
  fx[, order_id := seq_len(.N)]
  ggplot(fx, aes(x = x, y = y)) +
    geom_path(aes(group = 1), linewidth = 0.4, alpha = 0.7) +
    geom_point(aes(size = duration), alpha = 0.7) +
    geom_text(aes(label = order_id), size = 2.5, vjust = -0.8) +
    coord_fixed(xlim = c(dc[["x_min"]], dc[["x_max"]]), ylim = c(dc[["y_max"]], dc[["y_min"]])) +
    labs(title = "Scanpath / 注视路径", x = "x", y = "y") +
    theme_minimal()
}

safe_heatmap <- function(parsed, trial_id = "", phase = "") {
  sm <- copy(parsed$samples[valid_gaze == TRUE])
  if (nzchar(trial_id)) sm <- sm[sm$trial_id == trial_id]
  if (nzchar(phase)) sm <- sm[sm$phase == phase]
  dc <- parsed$metadata$display_coords
  if (nrow(sm) == 0) return(ggplot() + ggtitle("无 gaze sample 数据"))
  ggplot(sm, aes(x = gaze_x, y = gaze_y)) +
    stat_density_2d(aes(fill = after_stat(level)), geom = "polygon", alpha = 0.45, bins = 12) +
    coord_fixed(xlim = c(dc[["x_min"]], dc[["x_max"]]), ylim = c(dc[["y_max"]], dc[["y_min"]])) +
    labs(title = "Heatmap / 眼动热区", x = "x", y = "y") +
    theme_minimal() + theme(legend.position = "none")
}

plot_aoi_canvas <- function(parsed, aoi) {
  dc <- parsed$metadata$display_coords
  p <- ggplot() +
    coord_fixed(xlim = c(dc[["x_min"]], dc[["x_max"]]), ylim = c(dc[["y_max"]], dc[["y_min"]])) +
    labs(x = "x", y = "y", title = "AOI 绘制画布（EyeLink DISPLAY_COORDS 坐标）") +
    theme_minimal()
  if (!is.null(aoi) && nrow(aoi) > 0) {
    rects <- aoi[shape_type == "rectangle"]
    if (nrow(rects) > 0) p <- p + geom_rect(data = rects, aes(xmin = x_min, xmax = x_max, ymin = y_min, ymax = y_max), inherit.aes = FALSE, fill = NA, linewidth = 0.7)
    circles <- aoi[shape_type == "circle"]
    if (nrow(circles) > 0 && requireNamespace("ggforce", quietly = TRUE)) {
      p <- p + ggforce::geom_circle(data = circles, aes(x0 = center_x, y0 = center_y, r = radius), inherit.aes = FALSE, fill = NA, linewidth = 0.7)
    }
  }
  p
}

ui <- fluidPage(
  titlePanel("EyeLink ASC 眼动分析工具 / EyeLink ASC Analyzer"),
  sidebarLayout(
    sidebarPanel(
      fileInput("asc_file", "上传 ASC 文件", accept = c(".asc", ".txt")),
      fileInput("aoi_file", "上传 AOI CSV（可选）", accept = c(".csv")),
      fileInput("behavior_file", "上传答题记录 CSV（可选）", accept = c(".csv")),
      numericInput("bin_ms", "Time-bin 大小 / ms", value = 100, min = 20, step = 10),
      numericInput("baseline_ms", "瞳孔基线窗口 / ms", value = 500, min = 100, step = 100),
      actionButton("parse_btn", "解析 / 更新分析", class = "btn-primary"),
      hr(),
      uiOutput("selectors"),
      hr(),
      downloadButton("download_xlsx", "导出 XLSX"),
      downloadButton("download_metric", "导出指标字典 CSV")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("数据概览", br(), verbatimTextOutput("status"), h4("Metadata"), DTOutput("metadata_tbl"), h4("Trials"), DTOutput("trials_tbl"), h4("Phases"), DTOutput("phases_tbl")),
        tabPanel("指标说明", br(), DTOutput("metric_tbl")),
        tabPanel("Trial / Phase 分析", br(), plotOutput("timeline_plot", height = 420), plotOutput("scanpath_plot", height = 460), plotOutput("heatmap_plot", height = 460), h4("Phase Report"), DTOutput("phase_report_tbl")),
        tabPanel("AOI 编辑", br(), fluidRow(column(4, textInput("aoi_group", "AOI 组 ID", "aoi_1"), textInput("aoi_name", "AOI 名称", "兴趣区1"), numericInput("circle_radius", "圆形半径", 80, min = 1), actionButton("add_circle", "以点击位置添加圆形 AOI"), actionButton("clear_aoi", "清空临时 AOI")), column(8, p("矩形：在图上拖拽框选；圆形：点击图中位置后按按钮。"), plotOutput("aoi_canvas", height = 520, brush = brushOpts(id = "aoi_brush", resetOnNew = TRUE), click = clickOpts(id = "aoi_click")))), DTOutput("aoi_tbl")),
        tabPanel("AOI 分析", br(), h4("AOI Report"), DTOutput("aoi_report_tbl")),
        tabPanel("答题合并", br(), h4("时间戳 / 题目匹配检查"), DTOutput("behavior_check_tbl")),
        tabPanel("原始报表", br(), h4("Fixation"), DTOutput("fix_tbl"), h4("Saccade"), DTOutput("sac_tbl"), h4("Blink"), DTOutput("blink_tbl"))
      )
    )
  )
)

server <- function(input, output, session) {
  parsed <- reactiveVal(NULL)
  reports <- reactiveVal(list())
  aoi_dt <- reactiveVal(empty_aoi())
  behavior_dt <- reactiveVal(data.table())

  observeEvent(input$parse_btn, {
    req(input$asc_file)
    withProgress(message = "正在解析 ASC...", value = 0.1, {
      p <- parse_asc(input$asc_file$datapath)
      incProgress(0.4)
      rep <- compute_reports(p, bin_ms = input$bin_ms, baseline_ms = input$baseline_ms)
      if (!is.null(input$aoi_file)) {
        aoi <- normalize_aoi(fread(input$aoi_file$datapath, encoding = "UTF-8")); aoi_dt(aoi); rep$aoi_definition <- aoi; rep$aoi_report <- compute_aoi_report(p, aoi)
      }
      if (!is.null(input$behavior_file)) {
        b <- read_behavior(input$behavior_file$datapath); behavior_dt(b); rep$behavior_check_report <- behavior_check(p, b)
      }
      parsed(p); reports(rep); incProgress(1)
    })
  })

  output$selectors <- renderUI({
    p <- parsed(); if (is.null(p)) return(helpText("尚未解析 ASC 文件。"))
    tagList(selectInput("trial_select", "Trial", choices = c("" = "", unique(p$trials$trial_id))), selectInput("phase_select", "Phase", choices = c("" = "", unique(p$phases$phase))))
  })

  output$status <- renderPrint({
    p <- parsed(); if (is.null(p)) { cat("请上传 ASC 文件并点击解析。") } else {
      cat("当前文件：", p$metadata$source_file, "\n")
      cat("采样率：", p$metadata$sampling_rate, "Hz\n")
      cat("记录眼：", p$metadata$eye, "\n")
      cat("Samples：", nrow(p$samples), "\nFixations：", nrow(p$fixations), "\nSaccades：", nrow(p$saccades), "\nBlinks：", nrow(p$blinks), "\nTrials：", nrow(p$trials), "\n")
    }
  })

  output$metadata_tbl <- renderDT({ req(reports()$metadata); datatable(reports()$metadata, options = list(scrollX = TRUE)) })
  output$trials_tbl <- renderDT({ req(parsed()); datatable(parsed()$trials, options = list(scrollX = TRUE)) })
  output$phases_tbl <- renderDT({ req(parsed()); datatable(parsed()$phases, options = list(scrollX = TRUE)) })
  output$metric_tbl <- renderDT({ datatable(metric_dictionary(), filter = "top", options = list(scrollX = TRUE, pageLength = 15)) })
  output$phase_report_tbl <- renderDT({ req(reports()$phase_report); datatable(reports()$phase_report, options = list(scrollX = TRUE)) })
  output$timeline_plot <- renderPlot({ req(parsed()); safe_timeline(parsed(), input$trial_select) })
  output$scanpath_plot <- renderPlot({ req(parsed()); safe_scanpath(parsed(), input$trial_select, input$phase_select) })
  output$heatmap_plot <- renderPlot({ req(parsed()); safe_heatmap(parsed(), input$trial_select, input$phase_select) })
  output$fix_tbl <- renderDT({ req(reports()$fixation_report); datatable(head(reports()$fixation_report, 500), options = list(scrollX = TRUE)) })
  output$sac_tbl <- renderDT({ req(reports()$saccade_report); datatable(head(reports()$saccade_report, 500), options = list(scrollX = TRUE)) })
  output$blink_tbl <- renderDT({ req(reports()$blink_report); datatable(reports()$blink_report, options = list(scrollX = TRUE)) })

  observeEvent(input$aoi_brush, {
    req(parsed()); b <- input$aoi_brush; if (is.null(b)) return()
    old <- aoi_dt(); id <- paste0(input$aoi_group, "_", nrow(old) + 1)
    new <- data.table(aoi_group_id = input$aoi_group, aoi_name = input$aoi_name, shape_id = id, shape_type = "rectangle", x_min = b$xmin, y_min = b$ymin, x_max = b$xmax, y_max = b$ymax, center_x = NA_real_, center_y = NA_real_, radius = NA_real_, participant = "", trial_id = input$trial_select %||% "", condition = "", phase = input$phase_select %||% "", time_start = NA_real_, time_end = NA_real_, priority = 0, enabled = TRUE)
    aoi_dt(normalize_aoi(rbindlist(list(old, new), fill = TRUE)))
  })
  observeEvent(input$add_circle, {
    req(parsed(), input$aoi_click); old <- aoi_dt(); id <- paste0(input$aoi_group, "_", nrow(old) + 1)
    new <- data.table(aoi_group_id = input$aoi_group, aoi_name = input$aoi_name, shape_id = id, shape_type = "circle", x_min = NA_real_, y_min = NA_real_, x_max = NA_real_, y_max = NA_real_, center_x = input$aoi_click$x, center_y = input$aoi_click$y, radius = input$circle_radius, participant = "", trial_id = input$trial_select %||% "", condition = "", phase = input$phase_select %||% "", time_start = NA_real_, time_end = NA_real_, priority = 0, enabled = TRUE)
    aoi_dt(normalize_aoi(rbindlist(list(old, new), fill = TRUE)))
  })
  observeEvent(input$clear_aoi, aoi_dt(empty_aoi()))
  output$aoi_canvas <- renderPlot({ req(parsed()); plot_aoi_canvas(parsed(), aoi_dt()) })
  output$aoi_tbl <- renderDT({ datatable(aoi_dt(), options = list(scrollX = TRUE)) })
  output$aoi_report_tbl <- renderDT({ req(parsed()); ar <- if (nrow(aoi_dt()) > 0) compute_aoi_report(parsed(), aoi_dt()) else data.table(message = "尚未定义 AOI"); datatable(ar, options = list(scrollX = TRUE)) })
  output$behavior_check_tbl <- renderDT({ req(parsed()); if (nrow(behavior_dt()) == 0) datatable(data.table(message = "未上传答题记录 CSV")) else datatable(behavior_check(parsed(), behavior_dt()), options = list(scrollX = TRUE)) })

  output$download_xlsx <- downloadHandler(filename = function() paste0("eyelink_reports_", Sys.Date(), ".xlsx"), content = function(file) { rep <- reports(); if (length(rep) == 0) stop("No reports available."); rep$aoi_definition <- aoi_dt(); if (!is.null(parsed()) && nrow(aoi_dt()) > 0) rep$aoi_report <- compute_aoi_report(parsed(), aoi_dt()); export_xlsx(rep, file) })
  output$download_metric <- downloadHandler(filename = function() "metric_dictionary_cn.csv", content = function(file) fwrite(metric_dictionary(), file))
}

shinyApp(ui, server)
