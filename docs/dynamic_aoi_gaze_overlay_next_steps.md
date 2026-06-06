# 动态 AOI 与眼动轨迹叠加：下一步修改计划

本文给后续代码修改使用。当前 UE 侧已改为统一动态 AOI CSV：一个被试一个文件，只记录实验一 B 与实验二 E1/E3 的加载过程动态 AOI。R 程序下一步要把 AOI 录屏验证与 gaze/眼动轨迹叠加合并到同一个页面。

## 1. UE 侧数据约定

统一输入文件：

```text
<ParticipantID>_DynamicAOI.csv
```

只应包含以下动态 AOI：

| 实验 | 条件 | AOI |
|---|---|---|
| 实验一 | B | `b_preview_panel`：B 条件悬浮加载卡片 |
| 实验二 | E1 | `exp2_table_objects`：桌面四模型总体区域；`exp2_target_object`：当前目标模型区域 |
| 实验二 | E3 | `exp2_table_objects`：桌面四模型总体区域；`exp2_target_object`：当前目标模型区域 |

不要再把 A、A+、C-、C、E2、E4 当动态 AOI。它们后续使用静态 AOI 或不参与动态 AOI 分析。

建议 R 端识别这些列：

```text
participant, trial_id, experiment_code, condition, phase,
aoi_scope, aoi_group_id, aoi_name, shape_id,
video_time_start_ms, video_time_end_ms, time_ms,
start_ms, end_ms,
x_min, y_min, x_max, y_max,
projection_valid, is_clamped, enabled, visible,
target_content_index, target_display_index, slot_permutation
```

视频预览优先用：

```text
video_time_start_ms / video_time_end_ms / time_ms
```

正式 EyeLink 分析再用：

```text
LOADING_START + rel_start_ms / rel_end_ms
```

## 2. 当前仓库状态

相关文件：

```text
dynamic_aoi_validator_app.R
R/dynamic_aoi_video.R
R/dynamic_aoi_video_v2.R
R/dynamic_aoi_video_v3.R
R/dynamic_aoi_video_v4.R
www/dynamic-aoi-player.js
tests/testthat/test_dynamic_aoi_offset.R
```

当前是多个 R 文件逐个 source、后者覆盖前者的结构。短期可以继续，但完成后建议合并到：

```text
R/dynamic_aoi_video.R
```

避免 v2/v3/v4 覆盖链造成调试困难。

## 3. 标准化 AOI 表

修改 `standardize_dynamic_aoi()`，保证输出：

```r
c(
  "participant", "trial_id", "experiment_code", "condition", "phase",
  "aoi_scope", "aoi_group_id", "aoi_name", "shape_id",
  "time_ms", "start_ms", "end_ms",
  "x_min", "y_min", "x_max", "y_max",
  "projection_valid", "is_clamped", "enabled", "visible",
  "valid_aoi", "invalid_reason",
  "target_content_index", "target_display_index", "slot_permutation",
  "source_file"
)
```

字段兼容建议：

| 标准字段 | 兼容来源 |
|---|---|
| `experiment_code` | `experiment_code`, `experiment`, `exp`，或从 `condition` 推断 |
| `aoi_scope` | `aoi_scope`, `aoi_group_id`, `aoi_id`, `aoi` |
| `time_ms` | `time_ms`, `video_time_ms`, `video_time_mid_ms`，或 `(video_time_start_ms + video_time_end_ms)/2` |
| `start_ms` | `video_time_start_ms`, `start_ms`, `rel_start_ms` |
| `end_ms` | `video_time_end_ms`, `end_ms`, `rel_end_ms` |

## 4. 有效 AOI 判定

不要把 `is_clamped == TRUE` 直接判无效。半露出的 UI 仍然是可见 AOI。

推荐规则：

```r
valid_aoi =
  enabled == TRUE &
  visible == TRUE &
  projection_valid == TRUE &
  坐标完整 &
  AOI 矩形面积 > 0 &
  AOI 与屏幕区域存在交集
```

`is_clamped == TRUE` 只作为 warning 字段或风险提示，不应默认隐藏。

## 5. 加载段识别

新增函数：

```r
build_dynamic_aoi_segments <- function(aoi_dt)
```

输出建议：

```text
segment_id, participant, trial_id, experiment_code, condition, phase,
segment_label, start_ms, end_ms, duration_ms,
aoi_scopes, n_rows, n_valid, valid_ratio
```

只保留：

```r
condition %in% c("B", "E1", "E3")
```

分组：

```r
participant + trial_id + experiment_code + condition + phase
```

`segment_label` 示例：

```text
EXP1 | T001_02 | B | 35.2s-45.3s
EXP2 | Trial03 | E1 | 120.5s-132.1s
```

## 6. UI 需要增加的筛选

在动态 AOI 页面左侧增加：

```text
实验：All / EXP1 / EXP2
条件：All / B / E1 / E3
Trial：All / 具体 trial_id
AOI Scope：All / b_preview_panel / exp2_table_objects / exp2_target_object
加载段：来自 build_dynamic_aoi_segments()
```

选择加载段后，视频应跳转到：

```r
segment_start_ms / 1000
```

## 7. 视频叠加逻辑

`www/dynamic-aoi-player.js` 继续作为视频 canvas 叠加层。

每帧逻辑：

```js
t_ms = video.currentTime * 1000
```

AOI 选择优先级：

```text
1. start_ms <= t_ms < end_ms
2. 若没有区间命中，再使用 abs(time_ms - t_ms) <= nearestMs
```

Gaze 选择：

```text
abs(video_time_ms - t_ms) <= gazeWindowMs
```

AOI 颜色建议：

| AOI | 颜色建议 |
|---|---|
| `b_preview_panel` | 绿色 |
| `exp2_table_objects` | 蓝色 |
| `exp2_target_object` | 红色或橙色 |

JS 消息建议增加：

```js
selectedSegmentId
selectedTrialId
selectedCondition
selectedScopes
```

## 8. 眼动数据叠加

### gaze CSV

标准化为：

```text
time_ms, gaze_x, gaze_y, pupil, valid_gaze
```

视频时间：

```r
video_time_ms = time_ms - gaze_offset_ms
```

### ASC

用现有 `parse_asc()`，取 `parsed$samples`：

```r
time_ms = parsed$samples$time
gaze_x = parsed$samples$gaze_x
gaze_y = parsed$samples$gaze_y
pupil = parsed$samples$pupil
valid_gaze = parsed$samples$valid_gaze
video_time_ms = time_ms - gaze_offset_ms
```

注意：`gaze_offset_ms` 只用于录屏叠加验证，不要写回正式 EyeLink 分析时间。

## 9. Gaze × AOI 命中表

新增函数：

```r
compute_dynamic_gaze_aoi_hits <- function(aoi, gaze, sample_period_ms = NULL)
```

逻辑：

1. 找当前时间有效 AOI：`start_ms <= video_time_ms < end_ms`。
2. 判断 gaze 点是否落在 AOI 矩形内。
3. 输出 hit 明细与汇总。

明细字段建议：

```text
video_time_ms, gaze_x, gaze_y, participant, trial_id,
experiment_code, condition, aoi_scope, aoi_group_id, hit, pupil
```

汇总字段建议：

```text
participant, trial_id, experiment_code, condition, aoi_scope,
dwell_time_sample_ms, aoi_sample_count, aoi_sample_proportion,
first_hit_time_ms, ttff_ms, mean_pupil_in_aoi
```

若没有 sample period：

```r
sample_period_ms = median(diff(sort(gaze$video_time_ms)), na.rm = TRUE)
```

## 10. 导出

建议提供：

```text
dynamic_aoi_segments.csv
dynamic_aoi_quality.csv
dynamic_gaze_aoi_hits.csv
dynamic_gaze_aoi_summary.csv
```

## 11. 测试用例

1. 只上传视频 + AOI：应识别 B/E1/E3 加载段，并实时画 AOI。
2. 上传视频 + AOI + gaze：应同时画 AOI 与 gaze 轨迹。
3. 半露出 UI：`is_clamped=1` 但与屏幕有交集时仍可显示。
4. 统一 CSV：B 只显示 `b_preview_panel`；E1/E3 可切换 `exp2_table_objects` 与 `exp2_target_object`；A/A+/C-/C/E2/E4 不出现在动态段列表。

## 12. 不要改的点

1. 不要重新为 A/A+/C-/C/E2/E4 生成动态 AOI。
2. 不要假设一个 trial 一个 AOI CSV。
3. 不要把 `is_clamped=1` 直接当作无效。
4. 不要把录屏校准偏移写入正式 ASC 分析。
5. 不要把实验二固定视角条件纳入动态 AOI。
