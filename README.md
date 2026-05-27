# EyeLink ASC Analyzer CN

面向 EyeLink ASC 数据的 R Shiny 眼动分析工具。项目目标是替代 DataViewer 的主要指标导出流程，并针对 UE / 三维加载体验 HCI 实验提供 trial、phase、AOI、瞳孔与行为数据综合分析能力。

## 当前状态

当前代码按 V1–V4 目标推进，第一批提交覆盖：

- ASC 解析：sample、EFIX、ESACC、EBLINK、MSG、TRIALID、TRIAL_VAR
- trial / phase 自动识别：loading、viewer、question、progressive usable
- 核心指标导出：trial、phase、fixation、saccade、blink、pupil timeseries
- 中文指标字典
- Shiny 可视化界面
- 矩形 / 圆形 / 组合 AOI 基础支持
- AOI 指标：dwell time、TTFF、FFD、visit count、sample proportion
- 答题记录 CSV 合并与时间戳校验
- CSV / XLSX / PNG 导出基础函数

视频导入与视频 gaze replay 暂未纳入当前版本。

## 安装依赖

```r
source("install_dependencies.R")
```

## 启动软件

```r
shiny::runApp()
```

## 推荐输入

### 1. EyeLink ASC

先用 SR Research `EDF2ASC` 将 EDF 转为 ASC，然后在界面上传 `.asc` 文件。

### 2. AOI CSV

参考：

```text
data/templates/aoi_template.csv
```

支持：

- `rectangle`
- `circle`
- 多个 shape 共享同一个 `aoi_group_id`，形成组合 AOI
- 按 `trial_id`、`condition`、`phase`、`time_start`、`time_end` 绑定 AOI

### 3. 答题记录 CSV

参考：

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

## 测试数据

测试文件 `FM164641.asc` 的期望解析结果见：

```text
data/demo/FM164641_expected_counts.csv
```

本地测试时可将完整 ASC 放入：

```text
data/demo/FM164641.asc
```

## 注意事项

1. 当前第一目标是指标导出与论文分析表生成，不是完整复制 DataViewer 的回放体验。
2. 多边形 AOI 暂不做，异形区域建议由多个矩形 / 圆形组合。
3. 动态 3D AOI 建议后续由 UE 导出屏幕空间 bounding box 后再接入。
4. 瞳孔字段按 EyeLink `PUPIL AREA` 处理，论文中建议写为 pupil size / pupil area，并进行 baseline correction。
5. 2000 Hz ASC 可能出现同一毫秒两行 sample，程序保留 `sample_index`，不会按时间戳去重。
