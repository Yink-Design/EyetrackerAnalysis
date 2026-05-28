# EyeLink ASC Analyzer CN

面向 **EyeLink ASC / EyeLink 1000+** 数据的 R Shiny 眼动分析工具。项目目标是替代 DataViewer 的主要指标导出流程，并针对 UE / 三维加载体验 HCI 实验提供更贴合实验流程的 trial、phase、AOI、瞳孔与行为数据综合分析能力。

## CodeX / Codex 接手说明

请先阅读仓库根目录下的：

```text
PROJECT_PLAN.md
```

该文件记录了项目定位、版本规划、当前代码状态、已实现功能、已知限制、下一步开发任务和验收标准。后续开发请优先按照 `PROJECT_PLAN.md` 的任务顺序推进。

当前参考 ASC 文件已经由用户手动上传到：

```text
data/demo/FM164641.asc
```

解析该文件时，可用以下期望计数作为回归测试参照：

```text
data/demo/FM164641_expected_counts.csv
```

期望值：

| 项目 | 数量 / 状态 |
|---|---:|
| samples | 94,009 |
| fixations | 126 |
| saccades | 125 |
| blinks | 17 |
| messages | 91 |
| trials | 2 |
| sampling_rate | 2000 Hz |
| eye | RIGHT |
| display_coords | 0,0,1919,1079 |

## 当前代码状态

当前提交已经包含一个可继续开发的 R Shiny 原型：

| 模块 | 当前状态 |
|---|---|
| ASC 解析 | 已写入 `R/core.R` |
| Sample / EFIX / ESACC / EBLINK 解析 | 已写入 |
| MSG / TRIALID / TRIAL_VAR 解析 | 已写入 |
| Trial / Phase 自动识别 | 已写入 |
| Loading / Viewer / Question / Progressive Usable 阶段 | 已写入 |
| Trial / Phase / Fixation / Saccade / Blink / Pupil 报表 | 已写入 |
| 中文指标字典 | 已写入 |
| Shiny 可视化界面 | 已写入 `app.R` |
| 矩形 / 圆形 / 组合 AOI | 已写入基础逻辑 |
| AOI Report | 已写入基础逻辑 |
| 答题 CSV 合并与时间戳检查 | 已写入基础逻辑 |
| XLSX 导出 | 已写入基础逻辑 |
| 热图 / 轨迹 / 时间线基础图 | 已写入 |

重要：当前代码是在无 R 运行时环境下生成的，尚未完成本地实际运行测试。CodeX / Codex 的第一项任务应是进行本地 R 运行验证和修复。

## 安装依赖

在 R 或 RStudio 中运行：

```r
source("install_dependencies.R")
```

## 启动软件

```r
shiny::runApp()
```

或显式指定项目目录：

```r
shiny::runApp(".")
```

## 推荐本地验证流程

CodeX / Codex 接手后建议先按以下顺序验证：

```r
source("install_dependencies.R")
source("R/core.R", encoding = "UTF-8")
parsed <- parse_asc("data/demo/FM164641.asc")
reports <- compute_reports(parsed)

nrow(parsed$samples)
nrow(parsed$fixations)
nrow(parsed$saccades)
nrow(parsed$blinks)
nrow(parsed$messages)
nrow(parsed$trials)
```

然后与 `data/demo/FM164641_expected_counts.csv` 对比。

## DataViewer 对齐检查

本项目现在提供 DataViewer 4.2.1 对齐检查入口，用于把自编 R 报表与 DataViewer 导出的 Trial Report、Message Report、Fixation Report、Saccade Report 和 Time Course Report 做并排比较。

在 R 中运行：

```r
source("R/core.R", encoding = "UTF-8")
parsed <- parse_asc("data/demo/FM164641.asc")
reports <- compute_reports(parsed)

compare_with_dataviewer(
  parsed = parsed,
  reports = reports,
  dv_trial_file = "data/dv_exports/trialreport_FM121120.xls",
  dv_message_file = "data/dv_exports/mesreport_FM121120.xls",
  dv_fixation_file = "data/dv_exports/fixreport.xls",
  dv_saccade_file = "data/dv_exports/sacreport_FM121120.xls",
  dv_timecourse_file = "data/dv_exports/timecourseReport_FM121120.xls",
  out_file = "outputs/dv_alignment_report.xlsx"
)
```

在 Shiny 中，先上传并解析 ASC，再进入 **DataViewer 对齐检查** 页，分别上传 DataViewer 的五类 report，点击“运行对齐检查”，然后下载 `dv_alignment_report.xlsx`。

## 关键对齐规则

- Fixation / Saccade / Blink 现在按半开区间重叠 `[start, end)` 归入 trial / phase，而不是只看事件起点。
- 跨越 trial 或 phase 边界的事件会被裁剪，并输出 `*_interval_report`。
- `fixation_report_raw` / `saccade_report_raw` / `blink_report_raw` 保留 EyeLink 原始事件。
- Pupil 指标默认使用 `valid_sample = valid_gaze & valid_pupil`，其中 pupil 必须有限且大于 0。
- Time Course 支持 DataViewer Full Trial Period 对齐模式：`pupil_timeseries(parsed, bin_ms = 20, interval_mode = "full_trial", align_to = "trial_start")`。

## 正式分析长表

`compute_reports(parsed)` 会生成 `phase_analysis_long`，默认保留 `phase == "loading"` 的正式加载分析窗口，包含 trial、condition、duration_level、fixation、saccade、blink 和 pupil 指标，可直接用于后续统计建模。

## 测试脚本

```r
source("scripts/check_demo_alignment.R")
testthat::test_dir("tests/testthat")
```

通过核心解析后，再运行：

```r
shiny::runApp()
```

## 输入文件

### 1. EyeLink ASC

当前 demo 文件路径：

```text
data/demo/FM164641.asc
```

正式使用时，先用 SR Research `EDF2ASC` 将 EDF 转为 ASC，再在界面上传 `.asc` 文件。

### 2. AOI CSV

模板：

```text
data/templates/aoi_template.csv
```

支持：

- `rectangle`
- `circle`
- 多个 shape 共享同一个 `aoi_group_id`，形成组合 AOI
- 按 `trial_id`、`condition`、`phase`、`time_start`、`time_end` 绑定 AOI

### 3. 答题记录 CSV

模板：

```text
data/templates/behavior_template.csv
```

推荐字段：

```text
participant,trial_id,condition,question_id,question_start_unix,question_submit_unix,response_time_ms,selected_answer,correct_answer,accuracy
```

## 主要导出表

| 表 | 内容 |
|---|---|
| `metadata` | 文件、采样率、眼别、屏幕坐标、校准信息 |
| `quality_report` | 有效率、缺失率、事件数量、validation 信息 |
| `trial_report` | 每个 trial 的眼动与瞳孔汇总指标 |
| `phase_report` | loading / viewer / question / progressive usable 分阶段指标 |
| `fixation_report` | 每个 fixation 的起止时间、持续时间、坐标、瞳孔、trial、phase |
| `saccade_report` | 每个 saccade 的起止点、幅度、峰值速度、方向 |
| `blink_report` | 每个 blink 的起止时间和持续时间 |
| `pupil_timeseries` | 分箱瞳孔曲线 |
| `aoi_report` | AOI dwell、TTFF、FFD、visit count、sample proportion |
| `behavior_check_report` | ASC 与答题记录时间戳对齐检查 |
| `merged_eye_behavior_report` | 眼动指标 + 行为表现综合表 |
| `metric_dictionary` | 中文指标定义、公式、适用性说明 |

## 当前不包含的功能

| 功能 | 状态 |
|---|---|
| 视频导入 | 暂不做，后续 V5 |
| 视频叠加 gaze replay | 暂不做 |
| 多边形 AOI | 暂不做，用多个矩形 / 圆形组合代替 |
| 直接读取 EDF | 暂不做，当前优先 ASC |
| 内置 ANOVA / LMM / SEM | 暂不做，优先导出统计前长表 |

## 注意事项

1. 当前第一目标是指标导出与论文分析表生成，不是完整复制 DataViewer 的回放体验。
2. 多边形 AOI 暂不做，异形区域建议由多个矩形 / 圆形组合。
3. 动态 3D AOI 建议后续由 UE 导出屏幕空间 bounding box 后再接入。
4. 瞳孔字段按 EyeLink `PUPIL AREA` 处理，论文中建议写为 pupil size / pupil area，并进行 baseline correction。
5. 2000 Hz ASC 可能出现同一毫秒两行 sample，程序保留 `sample_index`，不要按时间戳去重。
