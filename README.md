# EyeLink ASC Analyzer

面向 EyeLink 眼动实验的本地分析工具，基于 R Shiny 构建。项目用于解析 EyeLink ASC 数据，按实验、试次与阶段计算眼动指标，并整合 AOI、行为记录和录屏验证结果，生成可用于统计分析的报表。

当前版本主要适配 EyeLink 1000+ 与 笔者自己的交互实验，同时保留通用 ASC 上传与分析流程。

后续如果中了好的期刊就进一步优化这个项目（❌）

## 主要功能

- 解析 ASC 中的 sample、fixation、saccade、blink、message、trial 与实验变量。
- 自动识别 EXP1 / EXP2 及 loading、viewer、question、selection 等实验阶段。
- 生成 trial、phase、fixation、saccade、blink、pupil 和数据质量报表。
- 合并 EXP1 答题记录与 EXP2 选择事件，检查时间戳和 marker 对齐情况。
- 支持矩形、圆形、组合 AOI，以及 UE 导出的动态 AOI。
- 在录屏中实时叠加动态 AOI 与 gaze，支持时间、位置和缩放校准。
- 对照 DataViewer 导出结果检查关键指标。
- 导出 CSV、XLSX 与 PNG，提供统计建模所需长表。

## 运行环境

- Windows
- R 4.5.3 或兼容版本
- SR Research EDF2ASC，用于将 EDF 转换为 ASC
- ffmpeg，可选，用于动态 AOI 录屏验证与视频预处理

安装 R 依赖：

```r
source("install_dependencies.R")
```

启动应用：

```r
source("run_local.R")
```

应用默认运行于：

```text
http://127.0.0.1:3838
```

也可以在 R 或 RStudio 中直接运行：

```r
shiny::runApp(".")
```

## 推荐工作流

1. 将 EDF 转换为 ASC，或准备完整的正式参与者数据包。
2. 在 Shiny 中上传 ASC，或填写正式参与者目录路径并加载。
3. 检查数据概览、质量报告、trial 和 phase 识别结果。
4. 按实验、条件、trial 与 phase 筛选并查看指标。
5. 根据需要进行静态 AOI、动态 AOI、行为数据或 DataViewer 对齐分析。
6. 在导出页面下载分析表、图像或完整 XLSX 报告。

正式参与者数据包建议采用以下结构：

```text
Participant/
├─ DataCollectionManifest.csv
├─ AOI/
│  └─ *_DynamicAOI.csv
├─ CSV/
│  ├─ *_exp01_InspectQuestionResults.csv
│  ├─ *_exp02_Experiment2Results.csv
│  └─ *_ExperimentEndEvent.csv
├─ EDF/
│  ├─ *.EDF
│  └─ *.asc
├─ Logs/
│  ├─ EyeLinkMarkers_*.log
│  └─ ScreenRecordingLog.csv
└─ ScreenRecordings/
   └─ *.mkv
```

部分补采或中断实验可能只包含其中一部分文件。应用会读取可用内容，并在数据概览中显示包清单与警告。

## 输入数据

### EyeLink ASC

ASC 是核心分析输入。正式使用前需通过 SR Research EDF2ASC 将 EDF 转换为 ASC。

仓库提供两个回归测试样例：

- `data/demo/FM164641.asc`：基础解析样例。
- `data/demo/V2/610FullTrialTest/`：包含 EXP1、EXP2、动态 AOI 与录屏的完整参与者包。

### 静态 AOI

模板位于 `data/templates/aoi_template.csv`。支持矩形、圆形及由多个 shape 组成的组合 AOI，可按 trial、condition、phase 和时间范围绑定。

### 动态 AOI

动态 AOI CSV 通常由 UE 导出屏幕空间 bounding box。动态 AOI 验证页面可将其与录屏和 gaze 叠加，并校准：

- 视频时间偏移
- 水平与垂直位置偏移
- 横向与纵向缩放

正式录制时，建议保持 UE Viewport、录屏和 EyeLink `DISPLAY_COORDS` 分辨率一致。

### 行为记录

通用行为表模板位于 `data/templates/behavior_template.csv`。正式数据包中的 EXP1 与 EXP2 行为 CSV 会被自动识别并用于对齐和综合分析。

## 主要输出

| 输出 | 内容 |
|---|---|
| `quality_report` | 有效率、缺失率、事件数量与 validation 信息 |
| `trial_report` | 每个 trial 的眼动与瞳孔汇总指标 |
| `phase_report` | 每个实验阶段的汇总指标 |
| `phase_analysis_long` | 面向后续统计建模的正式分析长表 |
| `fixation_report` | fixation 起止时间、持续时间、坐标、瞳孔与阶段归属 |
| `saccade_report` | saccade 起止点、幅度、峰值速度与方向 |
| `blink_report` | blink 起止时间与持续时间 |
| `pupil_timeseries` | 分箱后的瞳孔时间序列 |
| `aoi_report` | dwell、TTFF、FFD、visit count 与 sample proportion |
| `behavior_check_report` | ASC marker 与行为记录的时间戳检查 |
| `merged_eye_behavior_report` | 眼动指标与行为表现综合表 |
| `metric_dictionary` | 指标定义、公式与适用性说明 |

## 分析规则

- Fixation、saccade 与 blink 按半开区间 `[start, end)` 与 trial / phase 区间重叠关系归属。
- 跨越 trial 或 phase 边界的事件会被裁剪；原始事件仍保留在 `*_report_raw`。
- Pupil 指标默认要求 pupil 有限且大于 0，并可同时要求 gaze 有效。
- 2000 Hz ASC 可能在同一毫秒包含两行 sample；程序通过 `sample_index` 保留全部记录。
- 动态 AOI 正式分析使用 EyeLink、UE 与 Unix 时间基准对齐；视频预览校准不会改变正式报表。

## 验证与测试

运行完整回归测试：

```r
testthat::test_dir("tests/testthat")
```

运行基础 demo 与 DataViewer 对齐检查：

```r
source("scripts/check_demo_alignment.R")
```

基础 demo 的期望计数记录在：

```text
data/demo/FM164641_expected_counts.csv
```

## 已知限制

- 当前不直接读取 EDF，需先转换为 ASC。
- 多边形 AOI 暂不支持，可使用多个矩形或圆形组合。
- 项目侧重数据解析、质量检查与指标导出，不以复刻完整 DataViewer 回放功能为目标。
- ANOVA、LMM、SEM 等统计模型不在应用内执行，建议使用导出的长表完成后续分析。

## 开发与维护

核心解析与报表逻辑位于 `R/core.R`，动态 AOI 逻辑位于 `R/dynamic_aoi_video.R`，Shiny 主界面位于 `app.R`。

开发者或自动化编程助手在修改项目前，应先阅读：

- [`PROJECT_PLAN.md`](PROJECT_PLAN.md)：项目设计背景、实验约定与后续规划。
- [`data/demo/README.md`](data/demo/README.md)：测试数据与正式 V2 数据包说明。
- [`PUSH_LOG.md`](PUSH_LOG.md)：历史实现与验证记录。

提交修改前应至少运行完整 testthat 测试，并确认 Shiny 应用可以正常启动。
