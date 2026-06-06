# Overrides for dynamic_aoi_video.R / v2 / v3.
# Adds an AOI video-time offset control for systematic video encoding / capture start lag.
# Convention: adjusted_video_time = raw_aoi_time_ms + offset_ms.
# If AOI boxes appear late, try a negative offset such as -300 to -500 ms.

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
        shiny::numericInput("aoi_video_offset_ms", "AOI 视频时间偏移 / ms", value = 0, step = 50),
        shiny::helpText("校准录屏验证用：adjusted_video_time = AOI time + offset。AOI 框看起来晚，就填负数，例如 -300。"),
        shiny::numericInput("gaze_offset_ms", "眼动时间偏移：gaze_time - offset = video_rel_ms", value = 0, step = 10),
        shiny::numericInput("screen_width", "录屏坐标宽度", value = 1920, min = 1),
        shiny::numericInput("screen_height", "录屏坐标高度", value = 1080, min = 1),
        shiny::numericInput("frame_interval_ms", "抽帧间隔 / ms", value = 1000, min = 100, step = 100),
        shiny::numericInput("max_frames", "最多抽帧数", value = 20, min = 1, max = 200),
        shiny::numericInput("gaze_window_ms", "叠加眼动窗口 ±ms", value = 120, min = 1, step = 10),
        shiny::numericInput("nearest_aoi_ms", "AOI 最近帧容差 / ms", value = 120, min = 1, step = 10),
        shiny::textInput("ffmpeg_path", "ffmpeg 路径", value = "ffmpeg"),
        shiny::checkboxInput("valid_only", "只显示有效 AOI", value = TRUE),
        shiny::actionButton("run_check", "读取并开始实验验证", class = "btn-primary"),
        shiny::hr(),
        shiny::downloadButton("download_aoi_quality", "下载 AOI 有效性报告 CSV"),
        shiny::downloadButton("download_overlay_png", "下载当前叠加图 PNG")
      ),
      shiny::mainPanel(
        shiny::tabsetPanel(
          shiny::tabPanel("状态", shiny::br(), shiny::verbatimTextOutput("status")),
          shiny::tabPanel("AOI 有效性", shiny::br(), DT::DTOutput("quality_tbl"), shiny::h4("无效 / 风险 AOI"), DT::DTOutput("invalid_tbl"), shiny::h4("有效 AOI 时间断点"), DT::DTOutput("gap_tbl")),
          shiny::tabPanel("录屏叠加预览", shiny::br(), shiny::selectInput("frame_select", "预览帧", choices = character()), shiny::plotOutput("overlay_plot", height = 650)),
          shiny::tabPanel("标准化 AOI", shiny::br(), DT::DTOutput("aoi_tbl")),
          shiny::tabPanel("眼动数据", shiny::br(), shiny::helpText("未上传眼动文件也可以完成 AOI 验证。上传后会在预览图中叠加 gaze 轨迹。"), DT::DTOutput("gaze_tbl"))
        )
      )
    )
  )

  server <- function(input, output, session) {
    aoi_raw_rv <- shiny::reactiveVal(data.table::data.table())
    aoi_rv <- shiny::reactiveVal(data.table::data.table())
    quality_rv <- shiny::reactiveVal(list(summary = data.table::data.table(), invalid_rows = data.table::data.table(), gaps = data.table::data.table()))
    gaze_rv <- shiny::reactiveVal(data.table::data.table())
    frames_rv <- shiny::reactiveVal(data.table::data.table())
    last_plot_rv <- shiny::reactiveVal(NULL)

    apply_aoi_offset <- function(aoi, offset_ms) {
      out <- data.table::copy(data.table::as.data.table(aoi))
      if (nrow(out) == 0) return(out)
      offset_ms <- suppressWarnings(as.numeric(offset_ms %||% 0))
      if (!is.finite(offset_ms)) offset_ms <- 0
      for (nm in intersect(c("time_ms", "start_ms", "end_ms"), names(out))) {
        out[[nm]] <- as.numeric(out[[nm]]) + offset_ms
      }
      out[, aoi_video_offset_ms := offset_ms]
      out
    }

    rebuild_with_offset <- function() {
      raw <- aoi_raw_rv()
      if (nrow(raw) == 0) return(invisible(NULL))
      aoi <- apply_aoi_offset(raw, input$aoi_video_offset_ms)
      q <- validate_dynamic_aoi(aoi, screen_width = input$screen_width, screen_height = input$screen_height)
      aoi_rv(aoi)
      quality_rv(q)
      invisible(aoi)
    }

    build_frames <- function(aoi) {
      frame_plan <- make_frame_plan(aoi, interval_ms = input$frame_interval_ms, max_frames = input$max_frames, valid_only = FALSE)
      if (!is.null(input$video_file) && nrow(frame_plan) > 0) {
        out_dir <- file.path(tempdir(), paste0("daoi_frames_", as.integer(Sys.time()), "_", round(input$aoi_video_offset_ms %||% 0)))
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
    }

    shiny::observeEvent(input$run_check, {
      shiny::req(input$aoi_file)
      raw_aoi <- read_dynamic_aoi_csv(input$aoi_file$datapath, time_unit = input$aoi_time_unit, source_file = input$aoi_file$name)
      aoi_raw_rv(raw_aoi)
      aoi <- rebuild_with_offset()

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

      build_frames(aoi)
      shiny::showNotification(sprintf("动态 AOI 读取完成。当前 AOI 视频时间偏移：%s ms。", input$aoi_video_offset_ms), type = "message")
    })

    shiny::observeEvent(input$aoi_video_offset_ms, {
      if (nrow(aoi_raw_rv()) == 0) return()
      aoi <- rebuild_with_offset()
      build_frames(aoi)
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
        title = sprintf("AOI / gaze overlay | %.0f ms | AOI offset: %+d ms | AOI rows: %d | gaze points: %d", t, as.integer(input$aoi_video_offset_ms %||% 0), nrow(ar), nrow(gz)))
    })

    output$status <- shiny::renderPrint({
      cat("AOI raw rows:", nrow(aoi_raw_rv()), "\n")
      cat("AOI adjusted rows:", nrow(aoi_rv()), "\n")
      cat("AOI video offset ms:", input$aoi_video_offset_ms, "\n")
      cat("Gaze rows:", nrow(gaze_rv()), "\n")
      cat("Extracted frames:", nrow(frames_rv()), "\n")
      if (nrow(frames_rv()) == 0) cat("如未抽帧，请确认已上传视频且 ffmpeg 可用。AOI 有效性表仍可使用。\n")
      cat("\n偏移规则：adjusted_video_time = raw_aoi_time_ms + AOI视频时间偏移。\n")
      cat("AOI 框看起来比画面晚：填负数，例如 -300 / -500。\n")
      cat("AOI 框看起来比画面早：填正数，例如 300 / 500。\n")
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
