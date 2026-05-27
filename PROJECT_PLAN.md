# EyeLink ASC 眼动分析软件开发计划

## 1. 项目定位

本项目计划开发一个面向 **EyeLink ASC 数据** 的本地化眼动分析工具，用于替代 DataViewer 的主要指标导出流程，并针对 UE / 三维加载体验 HCI 实验提供更贴合实验流程的 trial、phase、AOI、瞳孔与行为数据综合分析能力。

项目初期以 **R + Shiny** 为主要技术路线，优先支持 `.asc` 文件解析、中文指标解释、可视化分析、AOI 绘制、CSV / XLSX / PNG 导出，以及答题记录 CSV 合并分析。

视频导入、视频时间戳对齐和视频叠加 gaze replay 暂不纳入当前开发范围，作为后续扩展功能。

---

## 2. 目标用户与使用场景

### 2.1 目标用户

- 使用 EyeLink / EyeLink 1000+ 的实验研究者
- 需要从 EDF2ASC 转换后的 `.asc` 文件中导出论文分析指标的用户
- 进行 HCI、用户体验、界面设计、三维交互、加载体验研究的设计学 / 交互研究人员
- 希望减少对 DataViewer 依赖，但仍需要 AOI、trial、phase、pupil、fixation 等指标导出的用户

### 2.2 典型使用场景

1. 上传 EyeLink `.asc` 文件。
2. 软件自动解析 sample、fixation、saccade、blink、MSG、TRIALID、trial variables。
3. 自动识别加载实验中的 trial 与 phase。
4. 用户上传背景图，在图上绘制矩形 / 圆形 / 组合 AOI。
5. 软件计算 trial-level、phase-level、AOI-level、pupil time-series 等指标。
6. 用户上传答题记录 CSV，软件进行时间戳对齐与综合分析。
7. 导出 CSV、XLSX 和 PNG，用于论文统计与结果展示。

---

## 3. 当前数据基础判断

基于测试文件 `FM164641.asc`，当前 ASC 文件已经包含以下关键结构：

| 数据结构 | 状态 | 用途 |
|---|---|---|
| Sample 数据 | 有 | gaze x/y、pupil、validity、热图、轨迹、瞳孔曲线 |
| EFIX | 有 | fixation report、注视次数、注视时长、AOI 注视指标 |
| ESACC | 有 | saccade report、眼跳次数、眼跳幅度、scanpath length |
| EBLINK | 有 | blink report、眨眼次数、眨眼率、缺失区间 |
| MSG | 有 | trial、phase、UE 事件、时间戳解析 |
| TRIALID | 有 | 自动划分试次 |
| `!V TRIAL_VAR` | 有 | participant、condition、exhibit 等实验变量 |
| PUPIL AREA | 有 | 瞳孔面积、baseline correction、pupil slope |
| DISPLAY_COORDS | 有 | 将 gaze 坐标与 1920×1080 背景图对齐 |
| UE 时间戳 | 有 | 与答题记录、UE 日志、后续视频扩展对齐 |

结论：当前 ASC 文件足以支撑软件 V1–V4 的核心开发。

---

## 4. 当前开发范围

### 4.1 纳入当前版本的功能

| 功能 | 是否纳入 | 说明 |
|---|---:|---|
| EyeLink ASC 导入 | 是 | 第一版仅支持 ASC，EDF 先由 EDF2ASC 转换 |
| sample / fixation / saccade / blink 解析 | 是 | 支持当前 EyeLink ASC 结构 |
| MSG / TRIALID / TRIAL_VAR 解析 | 是 | 用于识别 trial、condition、phase |
| trial / phase 自动切分 | 是 | 特别适配加载实验流程 |
| 全部可用指标导出 | 是 | trial、phase、AOI、pupil、fixation、saccade、blink、time-bin |
| 中文指标说明 | 是 | 在界面中解释指标定义、公式、适用性 |
| CSV 导出 | 是 | 单表导出 |
| XLSX 导出 | 是 | 多 sheet 汇总导出 |
| PNG 导出 | 是 | 轨迹图、热图、瞳孔曲线、事件时间线等 |
| 背景图上传 | 是 | 支持 AOI 与可视化叠加 |
| 矩形 AOI 绘制 | 是 | 核心 AOI 绘制方式 |
| 圆形 AOI 绘制 | 是 | 支持圆形兴趣区 |
| 组合 AOI | 是 | 多个矩形 / 圆形可合并为一个 AOI group |
| 时间段 AOI | 是 | 支持 trial / phase / time range 绑定 |
| 答题记录 CSV 上传 | 是 | 用于行为数据合并 |
| 时间戳对齐检查 | 是 | 检查 ASC marker 与行为 CSV 是否一致 |
| 综合分析表导出 | 是 | 眼动指标 + 答题表现合并 |
| 批量被试基础支持 | 是 | 支持多 ASC 合并分析 |

### 4.2 暂不纳入当前版本的功能

| 功能 | 处理方式 | 原因 |
|---|---|---|
| 视频导入 | 后续扩展 | 视频同步依赖视频起始时间基准 |
| 视频叠加 gaze replay | 后续扩展 | 需要前端 canvas / JS 处理，复杂度较高 |
| 多边形 AOI | 暂不做 | 当前以多个矩形 / 圆形组合替代 |
| 直接读取 EDF | 后续扩展 | 第一版优先支持 ASC，更稳定 |
| 完整复刻 DataViewer 回放界面 | 不作为目标 | 当前目标是指标导出和论文分析 |
| 内置 ANOVA / LMM / SEM 统计 | 暂不做 | 优先导出统计前长表，统计在 R / SPSS / JASP 中完成 |

---

## 5. 技术路线

### 5.1 核心技术栈

| 模块 | 建议技术 |
|---|---|
| 主语言 | R |
| GUI | Shiny |
| 数据处理 | data.table / dplyr |
| 可视化 | ggplot2 / plotly |
| 图片叠加 | magick / ggplot2 / grid |
| Excel 导出 | openxlsx 或 writexl |
| PNG 导出 | ggplot2::ggsave / ragg |
| 项目保存 | RDS / JSON / CSV |
| AOI 配置 | CSV / JSON |

### 5.2 项目结构

```text
EyeLinkASCAnalyzer_CN/
├─ app.R
├─ R/
│  ├─ 01_parse_asc.R
│  ├─ 02_extract_trials.R
│  ├─ 03_assign_phase.R
│  ├─ 04_metrics_core.R
│  ├─ 05_metrics_aoi.R
│  ├─ 06_merge_behavior.R
│  ├─ 07_visualization.R
│  ├─ 08_export_reports.R
│  ├─ 09_metric_dictionary.R
│  └─ 10_utils.R
├─ data/
│  ├─ demo/
│  └─ templates/
│     ├─ aoi_template.csv
│     ├─ behavior_template.csv
│     └─ metric_dictionary.csv
├─ www/
│  └─ app.css
├─ outputs/
└─ README.md
```

---

## 6. 版本规划

## V1：ASC 核心解析与指标导出版

### 目标

先完成 ASC 解析、trial / phase 自动识别、核心指标计算、CSV / XLSX 导出。

### 功能

- 上传单个 ASC 文件
- 解析 metadata
- 解析 samples
- 解析 EFIX / ESACC / EBLINK
- 解析 MSG / TRIALID / TRIAL_VAR
- 自动识别 participant、trial、condition、exhibit
- 自动识别 loading、viewer、question、progressive usable 等 phase
- 导出核心报表

### 输出对象

```r
parsed$samples
parsed$fixations
parsed$saccades
parsed$blinks
parsed$messages
parsed$trials
parsed$phases
parsed$metadata
```

### 导出表

| 表名 | 内容 |
|---|---|
| `quality_report.csv` | 数据质量、有效率、校准信息、记录时长 |
| `trial_report.csv` | 每个 trial 的汇总指标 |
| `phase_report.csv` | 每个 phase 的汇总指标 |
| `fixation_report.csv` | 每个 fixation 一行 |
| `saccade_report.csv` | 每个 saccade 一行 |
| `blink_report.csv` | 每个 blink 一行 |
| `pupil_timeseries.csv` | 分箱瞳孔曲线 |
| `all_reports.xlsx` | 多 sheet 汇总文件 |

### 完成标准

- 能正确解析 `FM164641.asc`
- 能识别 T001 / T002 等 trial
- 能识别 condition A / C 等 trial variable
- 能识别 `LOADING_START`、`LOADING_COMPLETE`、`VIEWER_ENTER`、`QUESTION_START`、`QUESTION_SUBMIT`
- 能输出 trial / phase / fixation / saccade / blink / pupil 报表
- 输出结果可直接用于统计分析

---

## V2：Shiny 可视化分析与基础 AOI 版

### 目标

完成基础可视化界面、中文指标说明、背景图叠加、矩形 / 圆形 AOI 绘制与 AOI 指标导出。

### 功能页面

| 页面 | 功能 |
|---|---|
| 数据导入 | 上传 ASC、显示解析结果 |
| 数据概览 | trial、phase、事件、数据质量概览 |
| 指标说明 | 中文解释指标定义、公式、适用性 |
| Trial / Phase 分析 | 选择 trial / phase，查看指标与图表 |
| AOI 编辑 | 上传背景图，绘制矩形 / 圆形 AOI |
| AOI 分析 | 计算 AOI dwell、TTFF、FFD、visit count |
| 导出 | 导出 CSV、XLSX、PNG |

### AOI 支持范围

| AOI 类型 | 支持状态 |
|---|---:|
| 矩形 AOI | 支持 |
| 圆形 AOI | 支持 |
| 组合 AOI group | 支持 |
| 多边形 AOI | 暂不支持 |
| 分 trial AOI | 支持 |
| 分 phase AOI | 支持 |
| 分时间段 AOI | 支持 |

### AOI 数据结构

| 字段 | 说明 |
|---|---|
| `aoi_group_id` | AOI 组编号 |
| `aoi_name` | AOI 名称 |
| `shape_id` | 单个形状编号 |
| `shape_type` | rectangle / circle |
| `x_min` | 矩形左上角 x |
| `y_min` | 矩形左上角 y |
| `x_max` | 矩形右下角 x |
| `y_max` | 矩形右下角 y |
| `center_x` | 圆形 AOI 圆心 x |
| `center_y` | 圆形 AOI 圆心 y |
| `radius` | 圆形 AOI 半径 |
| `trial_id` | 适用 trial，可为空 |
| `condition` | 适用 condition，可为空 |
| `phase` | 适用 phase，可为空 |
| `time_start` | 适用时间起点 |
| `time_end` | 适用时间终点 |
| `priority` | AOI 重叠时优先级 |
| `enabled` | 是否启用 |

### 完成标准

- 背景图可上传并显示
- AOI 坐标与 EyeLink display coordinates 对齐
- 可绘制 / 保存 / 读取矩形 AOI
- 可绘制 / 保存 / 读取圆形 AOI
- 多个 shape 可合并为一个 AOI group
- 可计算 AOI dwell time、TTFF、FFD、fixation count、visit count
- 可导出 AOI report
- 可导出 AOI 叠加图、scanpath、heatmap、pupil curve PNG

---

## V3：答题记录合并与综合实验分析版

### 目标

支持上传每个被试的答题记录 CSV，与 ASC 中的 trial、question marker、时间戳进行对齐检查，并导出眼动 + 行为表现综合分析表。

### 行为数据 CSV 推荐字段

```text
participant,trial_id,condition,question_id,question_start_unix,question_submit_unix,response_time_ms,selected_answer,correct_answer,accuracy
```

### 功能

- 上传 behavior CSV
- 自动检查 participant / trial / condition / question_id
- 对比 ASC 中的 `QUESTION_START` 与 `QUESTION_SUBMIT`
- 检查 response time 是否一致
- 计算时间戳误差
- 生成 mismatch report
- 合并眼动指标与答题表现
- 导出综合分析表

### 输出表

| 表名 | 内容 |
|---|---|
| `behavior_check_report.csv` | trial / question / 时间戳匹配检查 |
| `merged_eye_behavior_report.csv` | 眼动指标 + accuracy + RT |
| `condition_summary.csv` | 按 condition 汇总的行为与眼动指标 |

### 完成标准

- 能识别行为 CSV 与 ASC 的 trial 对应关系
- 能提示缺失、重复、condition 不一致、时间戳偏差过大等问题
- 能输出适合统计建模的长表

---

## V4：批量处理、项目保存与稳定化版

### 目标

支持正式实验中的多被试批量处理、项目配置保存、批量导出和错误提示中文化。

### 功能

- 多个 ASC 文件批量导入
- 多被试合并分析
- 项目配置保存 / 读取
- AOI 配置保存 / 读取
- 批量生成 CSV / XLSX / PNG
- 错误提示中文化
- 输出日志文件
- 指标字典随报表一起导出

### 完成标准

- 多被试数据不会混淆 participant / trial / condition
- 所有导出表为长表格式，适合 R / SPSS / JASP / Jamovi
- 项目重新打开后可以恢复 AOI、文件配置与分析参数
- 批量导出结构稳定

---

## V5：视频扩展版（后续，不纳入当前开发）

### 目标

支持视频导入、视频起点时间对齐、gaze 轨迹叠加、视频截图上热图与轨迹导出。

### 前提

需要解决视频时间基准问题，例如：

- 视频 0 秒对应 ASC 中某个 EVENT
- 视频 0 秒对应 UE unix / bjt 时间戳
- 用户手动输入 offset

### 暂缓原因

视频同步精度依赖实验记录流程，不适合作为当前核心开发目标。

---

## 7. 指标体系

## 7.1 数据质量指标

| 英文名 | 中文名 | 定义 | 是否适合加载体验研究 |
|---|---|---|---:|
| Sample Count | 采样点数量 | ASC 中逐采样记录数量 | 是，用于检查数据完整性 |
| Valid Sample Rate | 有效采样率 | 有效 gaze / pupil sample 占比 | 是，作为数据剔除依据 |
| Missing Data Rate | 缺失率 | 无效或缺失 sample 占比 | 是，作为质量控制指标 |
| Calibration Error | 校准误差 | validation 平均误差和最大误差 | 是，用于报告数据质量 |
| Recording Duration | 记录总时长 | recording start 到 stop 的时长 | 是，用于流程检查 |

## 7.2 Trial / Phase 指标

| 英文名 | 中文名 | 定义 | 是否适合加载体验研究 |
|---|---|---|---:|
| Trial Duration | 试次总时长 | trial 起点到终点的时间 | 是 |
| Loading Duration | 加载时长 | LOADING_START 到 LOADING_COMPLETE | 是，核心指标 |
| Viewer Duration | 查看阶段时长 | VIEWER_ENTER 到 VIEWER_EXIT | 是 |
| Question Duration | 答题时长 | QUESTION_START 到 QUESTION_SUBMIT | 是 |
| Progressive Usable Duration | 渐进可用阶段时长 | PROGRESSIVE_USABLE 到 LOADING_COMPLETE | 是，适合 C 条件 |
| Phase-specific Metrics | 分阶段眼动指标 | 在 loading / viewer / question 内分别计算指标 | 是，核心分析方式 |

## 7.3 Fixation 指标

| 英文名 | 中文名 | 定义 | 是否适合加载体验研究 |
|---|---|---|---:|
| Fixation Count | 注视次数 | 阶段内 EFIX 数量 | 是 |
| Mean Fixation Duration | 平均注视时长 | fixation duration 平均值 | 是 |
| Total Fixation Duration | 总注视时长 | fixation duration 总和 | 是 |
| Fixation Rate | 注视频率 | fixation count / 阶段时长 | 是 |
| First Fixation Latency | 首次注视潜伏期 | 阶段开始到第一次 fixation 的时间 | 一般，结合 AOI 更有价值 |

## 7.4 AOI 指标

| 英文名 | 中文名 | 定义 | 是否适合加载体验研究 |
|---|---|---|---:|
| AOI Fixation Count | AOI 注视次数 | 落入 AOI 的 fixation 数量 | 是，核心指标 |
| Dwell Time | 停留时间 | gaze / fixation 落在 AOI 内的累计时长 | 是，核心指标 |
| Time to First Fixation | 首次注视时间 | 阶段开始到第一次看向 AOI 的时间 | 是，核心指标 |
| First Fixation Duration | 首次注视时长 | 第一次落入 AOI 的 fixation duration | 是 |
| Visit Count / Run Count | AOI 访问次数 / 回访次数 | 连续进入 AOI 算一次 visit | 是 |
| AOI Sample Proportion | AOI 采样占比 | AOI 内有效 sample / 阶段内有效 sample | 是 |
| AOI Transition | AOI 转移路径 | AOI 之间的注视转移顺序 | 是，辅助解释注意路径 |

## 7.5 Saccade 指标

| 英文名 | 中文名 | 定义 | 是否适合加载体验研究 |
|---|---|---|---:|
| Saccade Count | 眼跳次数 | 阶段内 ESACC 数量 | 是 |
| Mean Saccade Amplitude | 平均眼跳幅度 | saccade amplitude 平均值 | 是 |
| Total Scanpath Length | 扫视路径总长度 | 所有 saccade amplitude 总和 | 是 |
| Peak Velocity | 峰值速度 | saccade 最大速度 | 辅助指标 |
| Saccade Rate | 眼跳频率 | saccade count / 阶段时长 | 是 |

## 7.6 Blink 指标

| 英文名 | 中文名 | 定义 | 是否适合加载体验研究 |
|---|---|---|---:|
| Blink Count | 眨眼次数 | 阶段内 EBLINK 数量 | 是，但解释需谨慎 |
| Blink Rate | 眨眼率 | blink count / 阶段时长 | 是，辅助指标 |
| Total Blink Duration | 总眨眼时长 | blink duration 总和 | 是，质量与注意状态参考 |
| Mean Blink Duration | 平均眨眼时长 | blink duration 平均值 | 辅助指标 |

## 7.7 Pupil 指标

| 英文名 | 中文名 | 定义 | 是否适合加载体验研究 |
|---|---|---|---:|
| Mean Pupil Area | 平均瞳孔面积 | sample 中 pupil area 平均值 | 是 |
| Baseline-corrected Pupil | 基线校正瞳孔变化 | 当前 pupil 减去基线 pupil | 是，核心指标 |
| Pupil Dilation | 瞳孔扩张量 | 相对 baseline 的瞳孔增量 | 是 |
| Peak Pupil Dilation | 峰值瞳孔扩张 | 阶段内最大 pupil change | 是 |
| Time to Peak Pupil | 峰值出现时间 | 阶段开始到最大瞳孔变化的时间 | 是 |
| Pupil Slope | 瞳孔变化斜率 | pupil 随时间变化的线性趋势 | 是 |

## 7.8 Time-bin 指标

| 英文名 | 中文名 | 定义 | 是否适合加载体验研究 |
|---|---|---|---:|
| Time-bin Mean Pupil | 分箱平均瞳孔 | 每 50/100/200ms 计算平均 pupil | 是，核心曲线指标 |
| Time-bin AOI Proportion | 分箱 AOI 注视比例 | 每个时间窗内看向 AOI 的比例 | 是 |
| Time-bin Valid Rate | 分箱有效率 | 每个时间窗内有效 sample 比例 | 是 |
| Time-bin Blink Proportion | 分箱眨眼比例 | 每个时间窗内 blink 占比 | 辅助指标 |

---

## 8. 关键算法规则

### 8.1 Phase 识别规则

| Phase | 起点 | 终点 |
|---|---|---|
| loading | `LOADING_START` | `LOADING_COMPLETE` |
| viewer | `VIEWER_ENTER` | `VIEWER_EXIT` |
| question | `QUESTION_START` | `QUESTION_SUBMIT` |
| progressive_usable | `PROGRESSIVE_USABLE` | `LOADING_COMPLETE` |

异常处理：

| 缺失情况 | 处理方式 |
|---|---|
| 缺少 LOADING_COMPLETE | 使用下一个关键事件或 trial 结束作为备选 |
| 缺少 VIEWER_EXIT | 使用 trial 结束作为备选 |
| 缺少 QUESTION_SUBMIT | 标记为 incomplete |
| phase 重叠 | 优先使用更具体阶段，例如 question 高于 viewer |

### 8.2 AOI 命中规则

矩形 AOI：

```text
x >= x_min
x <= x_max
y >= y_min
y <= y_max
```

圆形 AOI：

```text
sqrt((x - center_x)^2 + (y - center_y)^2) <= radius
```

组合 AOI：

```text
hit_group = hit_shape_1 OR hit_shape_2 OR hit_shape_3 ...
```

AOI 重叠处理：

- 默认保留多个 AOI 标签。
- 若用户设置 priority，则优先采用高优先级 AOI。

### 8.3 Dwell Time 计算

| 类型 | 定义 | 推荐用途 |
|---|---|---|
| fixation-based dwell | 落入 AOI 的 fixation duration 总和 | 论文主分析 |
| sample-based dwell | 落入 AOI 的 sample 时间总和 | 高时间精度分析 |

默认使用 fixation-based dwell，同时允许用户切换 sample-based dwell。

### 8.4 Pupil baseline

可选基线：

| 类型 | 说明 |
|---|---|
| trial 前 500ms | 如果有足够数据 |
| loading_start 前 500ms | 推荐 |
| trial 内前 500ms | 备选 |
| 自定义事件前后 | 高级选项 |
| within-subject z-score | 跨被试比较时推荐 |

输出字段：

```text
raw_pupil_area
baseline_corrected_pupil_area
pupil_z
```

---

## 9. 导出设计

### 9.1 CSV 导出

- 每张报表单独导出为 CSV。
- 所有时间字段保留 EyeLink time 与相对 trial time。
- 若存在 UE unix / bjt，则同时保留绝对时间字段。

### 9.2 XLSX 导出

`all_reports.xlsx` 默认包含以下 sheets：

```text
metadata
quality_report
trial_report
phase_report
fixation_report
saccade_report
blink_report
pupil_timeseries
aoi_definition
aoi_report
behavior_check_report
merged_eye_behavior_report
metric_dictionary
```

### 9.3 PNG 导出

支持导出：

| 图像 | 内容 |
|---|---|
| event timeline | trial / phase 事件时间线 |
| pupil curve | 瞳孔变化曲线 |
| scanpath | 注视路径图 |
| heatmap | 热区图 |
| AOI overlay | 背景图 + AOI 边界 |
| AOI scanpath | 背景图 + AOI + fixation path |
| AOI heatmap | 背景图 + AOI + heatmap |

---

## 10. 开发任务拆分

### Step 1：核心解析器

- [ ] 读取 ASC 原始文本
- [ ] 解析 metadata
- [ ] 解析 DISPLAY_COORDS
- [ ] 解析 samples
- [ ] 解析 EFIX
- [ ] 解析 ESACC
- [ ] 解析 EBLINK
- [ ] 解析 MSG
- [ ] 解析 TRIALID
- [ ] 解析 `!V TRIAL_VAR`
- [ ] 生成 parsed object

### Step 2：trial / phase 识别

- [ ] 根据 TRIALID 生成 trial table
- [ ] 提取 participant / condition / exhibit
- [ ] 根据 MSG 识别 loading phase
- [ ] 根据 MSG 识别 viewer phase
- [ ] 根据 MSG 识别 question phase
- [ ] 根据 MSG 识别 progressive usable phase
- [ ] 将 sample / fixation / saccade / blink 归属到 trial 与 phase

### Step 3：核心指标计算

- [ ] 数据质量指标
- [ ] trial report
- [ ] phase report
- [ ] fixation report
- [ ] saccade report
- [ ] blink report
- [ ] pupil timeseries
- [ ] time-bin report
- [ ] baseline-corrected pupil

### Step 4：Shiny 基础界面

- [ ] 数据导入页
- [ ] 数据概览页
- [ ] 指标说明页
- [ ] Trial / Phase 分析页
- [ ] 导出页
- [ ] 中文错误提示

### Step 5：AOI 功能

- [ ] 上传背景图
- [ ] 显示背景图与坐标
- [ ] 绘制矩形 AOI
- [ ] 绘制圆形 AOI
- [ ] AOI group 管理
- [ ] AOI phase / time range 设置
- [ ] AOI 命中计算
- [ ] AOI report
- [ ] AOI 可视化图导出

### Step 6：行为数据合并

- [ ] 上传 behavior CSV
- [ ] 字段检查
- [ ] trial 匹配
- [ ] question 匹配
- [ ] 时间戳误差检查
- [ ] mismatch report
- [ ] merged eye-behavior report

### Step 7：批量处理与稳定化

- [ ] 多 ASC 批量导入
- [ ] 多被试合并
- [ ] AOI 配置保存 / 读取
- [ ] 项目配置保存 / 读取
- [ ] 批量导出 CSV / XLSX / PNG
- [ ] 输出运行日志
- [ ] README 和使用说明

---

## 11. 验收标准

### 11.1 数据解析验收

使用 `FM164641.asc` 测试时，应满足：

- 能识别 sample 数据
- 能识别 fixation / saccade / blink
- 能识别 MSG marker
- 能识别 trial
- 能识别 condition
- 能识别 loading / viewer / question / progressive usable phase

### 11.2 指标导出验收

- 所有报告可导出 CSV
- 所有报告可汇总导出 XLSX
- trial / phase 指标与 MSG 时间差一致
- fixation / saccade / blink 数量与 ASC 事件数量一致
- pupil 指标只使用有效 sample

### 11.3 AOI 验收

- 背景图坐标与 DISPLAY_COORDS 对齐
- 矩形 AOI 命中计算正确
- 圆形 AOI 命中计算正确
- 组合 AOI 能合并多个 shape
- AOI 可绑定 trial / phase / time range
- AOI report 可导出

### 11.4 行为数据合并验收

- 能上传 behavior CSV
- 能匹配 participant、trial、condition、question
- 能输出时间戳误差
- 能输出综合分析长表

---

## 12. 当前优先级

当前优先开发顺序：

1. ASC 解析器
2. trial / phase 识别
3. 核心指标导出
4. Shiny 基础界面
5. 中文指标说明
6. AOI 计算逻辑
7. 背景图与 AOI 绘制
8. PNG / XLSX 导出
9. 答题 CSV 合并
10. 批量处理与项目保存

---

## 13. 项目边界

本项目当前阶段的重点不是完整复制 DataViewer 的全部交互体验，而是实现以下目标：

- 可靠读取 EyeLink ASC 数据
- 自动识别 HCI 加载实验流程
- 导出论文分析所需的核心眼动指标
- 支持中文指标解释
- 支持静态 / 时间段 AOI 分析
- 支持行为数据合并
- 支持 CSV / XLSX / PNG 导出

后续视频功能和更复杂的动态 AOI 可在核心系统稳定后扩展。
