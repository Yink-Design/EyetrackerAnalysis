# 三维场景加载体验研究：实验结构与数据分析说明

> 目的：本文档用于帮助负责 R 数据分析程序的 AI / 开发者理解当前 UE5.3 眼动实验项目的实验结构、条件编码、数据来源、文件命名逻辑与后续分析目标。  
> 项目核心：研究三维场景中不同“加载方式”如何影响用户体验、等待感、任务表现与眼动行为。

---

## 1. 项目总览

本研究是一个基于 UE5.3 原型系统的用户体验与眼动实验。实验运行在三维展厅场景中，被试通过键盘鼠标进行移动、观察、交互和答题。实验数据由两部分组成：

1. **UE 本地记录数据**
   - 实验一答题与事件数据 CSV
   - 实验二答题、选择与任务数据 CSV
   - 动态 AOI 坐标 CSV
   - 本地事件时间戳
   - 屏幕录制文件
   - 最终按被试编号自动打包的数据文件夹

2. **EyeLink 1000+ 眼动数据**
   - EDF / ASC 原始眼动数据
   - EyeLink marker / message
   - 后续由 R 程序解析出注视、眼跳、瞳孔、AOI 命中等指标

整体研究分为两个实验：

| 实验 | 目的 | 设计结构 | 核心问题 |
|---|---|---|---|
| 实验一 | 比较不同三维加载方式的整体体验差异 | A / A+ / B / C / C- 五水平 | 哪种加载方式更能改善等待体验、降低不确定性、提高流畅感？ |
| 实验二 | 拆解实验一中可能起作用的机制 | E1 / E2 / E3 / E4，2×2 设计 | “空间连续性”和“渐进可用性”分别如何影响体验与任务表现？ |

---

## 2. 被试编号与输出编号逻辑

当前代码中建议区分两个概念：

| 概念 | 含义 | 示例 |
|---|---|---|
| `ParticipantID` | 被试原始编号，用于表示同一名被试 | `A001` |
| `ParticipantOutputID` | 本次实验输出编号，用于文件名和打包文件夹 | `A001`, `A001_v2`, `A001_v3` |

### 2.1 正式测试编号规则

如果同一个被试编号重复测试，不能覆盖旧数据，而是生成新文件夹：

```text
A001      # 第一次
A001_v2   # 第二次
A001_v3   # 第三次
```

注意：

- CSV 内部的 `ParticipantID` 建议仍然保持原始编号，例如 `A001`。
- 文件名、文件夹名、AOI 文件名前缀可以使用 `ParticipantOutputID`。
- R 分析时，如果要区分“同一被试的不同采集会话”，应额外保留 `ParticipantOutputID` 或从文件夹名解析 session。
- 如果只分析最终正式数据，应明确每名被试采用哪一次有效采集，避免把 `A001` 与 `A001_v2` 误当成两个不同被试。

### 2.2 TEST 调试编号规则

`TEST` 是调试专用编号：

```text
ParticipantID = TEST
ParticipantOutputID = TEST
```

调试时不生成 `TEST_v2`。每次以 `TEST` 开始测试时，旧的 TEST 数据会被清理，只保留最新一次调试数据。

R 程序默认应将 `ParticipantID == "TEST"` 的数据排除在正式分析之外。

---

## 3. 推荐数据文件结构

自动打包后的推荐结构如下：

```text
Saved/
  ExperimentData/
    Participants/
      A001/
        CSV/
        AOI/
        EDF/
        Logs/
        ScreenRecordings/
        DataCollectionManifest.csv

      A001_v2/
        CSV/
        AOI/
        EDF/
        Logs/
        ScreenRecordings/
        DataCollectionManifest.csv
```

常见数据文件包括：

```text
<ParticipantOutputID>_exp01_InspectQuestionResults.csv
<ParticipantOutputID>_exp02_Experiment2Results.csv
<ParticipantOutputID>_DynamicAOI.csv
DataCollectionManifest.csv
*.EDF
*.asc
*.log
*.mkv / *.mp4
```

R 程序建议从每个 `Participants/<ParticipantOutputID>/` 文件夹读取数据，并添加以下字段：

| 字段 | 来源 | 说明 |
|---|---|---|
| `ParticipantOutputID` | 文件夹名 | 本次采集会话编号 |
| `ParticipantID` | CSV 内部字段 | 原始被试编号 |
| `SessionVersion` | 从 `ParticipantOutputID` 解析 | 如无 `_v2` 则为 1，有 `_v2` 则为 2 |
| `IsTestRun` | `ParticipantID == "TEST"` | 是否调试数据 |
| `DataFolder` | 文件夹路径 | 便于追踪原始文件 |

---

## 4. 实验一：五水平加载方式比较

### 4.1 实验一目的

实验一用于比较五种加载方式对用户体验和眼动行为的影响。研究重点包括：

1. 加载是否阻断用户行动；
2. 是否提供进度信息；
3. 加载信息是否嵌入三维场景；
4. 用户是否能在资源未完全加载时提前开始观察或答题；
5. 不同加载方式对等待感、确定感、流畅感和满意度的影响。

### 4.2 实验一条件

实验一共有五个条件：

| 条件编码 | 条件名称 | 核心特征 | 机制含义 |
|---|---|---|---|
| `A` | 全屏阻断，无进度 | 用户被全屏加载界面阻断，不能继续查看场景，也没有明确进度反馈 | 传统阻断式加载基线 |
| `A+` | 全屏阻断，有图片进度条 | 仍然全屏阻断，但提供图片和进度条 | 测试“进度信息 / 视觉反馈”的作用 |
| `B` | 场景内悬浮卡片加载 | 用户保持在三维场景中，看到占位模型、悬浮信息卡、进度条和展品信息 | 测试“空间嵌入式加载信息”的作用 |
| `C` | 渐进可用，有进度 | 用户可进入查看器，模型从低清晰度逐渐变清晰，达到最低可用后可开始任务，有进度反馈 | 测试“渐进可用 + 进度反馈”的作用 |
| `C-` | 渐进可用，无进度 | 与 C 类似，但去掉明确进度条 | 测试“渐进可用本身”的作用，剥离进度反馈 |

### 4.3 实验一任务流程

单个条件的大致流程：

```text
被试在三维场景中移动
  ↓
靠近展台 / 展品触发区域
  ↓
按 E 触发加载
  ↓
进入对应加载条件 A / A+ / B / C / C-
  ↓
进入查看器或完成加载后进入查看器
  ↓
观察展品并回答题目
  ↓
完成本条件问卷或记录
  ↓
退出查看器，前往下一个条件
```

### 4.4 实验一主要数据

实验一可能涉及以下数据：

| 数据类型 | 说明 |
|---|---|
| 条件编码 | A / A+ / B / C / C- |
| 展品或模型编号 | 不同展台对应不同模型 |
| 加载开始时间 | UE 事件时间戳与 EyeLink marker |
| 加载结束时间 | 模型加载完成或达到可用状态 |
| 查看器进入时间 | 用户进入展品查看界面 |
| 题目出现时间 | 问题开始可答 |
| 回答时间 | 用户提交答案的时间 |
| 答案正确性 | 目标识别或判断是否正确 |
| 主观问卷 | PAD、满意度、感知等待时间、感知不确定性、流畅度等 |
| 眼动数据 | 注视、眼跳、瞳孔、AOI 命中、停留时间等 |

### 4.5 实验一分析目标

R 分析程序应支持：

1. 按条件比较主观体验指标；
2. 按条件比较任务表现，例如答题正确率、反应时间；
3. 按条件比较加载阶段眼动指标；
4. 分析加载前 / 加载中 / 加载后不同阶段的眼动变化；
5. 支持动态 AOI，尤其是 B / C / C- 等场景内或查看器内元素位置可能变化的条件；
6. 输出被试级、条件级、试次级长表，便于后续统计模型分析。

### 4.6 实验一可能的核心假设

可能关注的方向包括：

| 假设方向 | 解释 |
|---|---|
| B 优于 A / A+ | 场景嵌入式信息比全屏阻断更能维持空间连续性和任务感 |
| A+ 优于 A | 进度条和图片反馈可能降低等待不确定性 |
| C 优于 C- | 明确进度反馈可能增强用户对加载状态的掌控感 |
| C / C- 优于 A | 渐进可用可能降低被动等待感 |
| B 与 C 差异 | 用于判断“信息透明度”与“渐进可用性”哪一个贡献更大 |

---

## 5. 实验二：机制拆解实验

### 5.1 实验二目的

实验二用于进一步拆解实验一中可能起作用的机制，重点关注两个因素：

1. **空间连续性**：加载期间用户是否仍然停留在三维场景中，能否保持空间位置和视觉上下文。
2. **渐进可用性**：加载期间用户是否能在资源逐步清晰的过程中提前开始观察、判断或行动。

实验二用 2×2 结构验证机制。

### 5.2 实验二 2×2 因子结构

| 因素 | 水平 1 | 水平 2 |
|---|---|---|
| 空间连续性 | 连续：用户仍在三维场景中，可保持空间上下文 | 不连续：视角固定或全屏加载，空间行动被中断 |
| 渐进可用性 | 有：模型逐步清晰，用户可以在最低可用后开始判断或行动 | 无：加载完成前不能有效完成任务 |

### 5.3 实验二条件

实验二共有四个条件：

| 条件编码 | 空间连续性 | 渐进可用性 | 条件说明 |
|---|---:|---:|---|
| `E1` | 有 | 有 | 用户可移动，四个模型逐渐清晰；达到最低可用后可开始任务 |
| `E2` | 无 | 有 | 视角固定在触发前最后一帧，模型逐渐清晰；有渐进可用但空间不连续 |
| `E3` | 有 | 无 | 用户可移动，但任务对象以占位符或加载环形式等待，未完成加载前不可有效判断 |
| `E4` | 无 | 无 | 全屏加载页，仅进度条；空间连续性和渐进可用性都被移除 |

### 5.4 实验二任务

实验二当前任务是一个选择 / 放置任务。被试需要在加载后或加载过程中判断四个物体，并选择符合目标条件的物体，例如：

```text
选择“最光滑”或具有特定纹理特征的物体
  ↓
尽快将其放置到身后桌面
```

任务重点包括：

1. 观察；
2. 判断；
3. 操作；
4. 任务完成时间；
5. 正误结果。

### 5.5 实验二单次流程

```text
被试进入实验二任务区
  ↓
触发 E1 / E2 / E3 / E4 条件
  ↓
加载开始
  ↓
根据条件决定是否可移动、是否可提前判断
  ↓
被试选择目标物体
  ↓
将物体放到身后桌面
  ↓
记录选择、正确性、完成时间和眼动数据
```

### 5.6 实验二主要数据

| 数据类型 | 说明 |
|---|---|
| 条件编码 | E1 / E2 / E3 / E4 |
| 空间连续性 | 由条件映射得到，建议在 R 中派生为 `SpatialContinuity` |
| 渐进可用性 | 由条件映射得到，建议在 R 中派生为 `ProgressiveAvailability` |
| 目标物体 | 正确答案对象 |
| 被试选择 | 被试实际选择对象 |
| 正确性 | 选择是否正确 |
| 任务完成时间 | 从任务开始到成功放置的时间 |
| 加载阶段时间戳 | 加载开始、最低可用、加载完成等 |
| 眼动指标 | 注视、眼跳、瞳孔、AOI 命中等 |
| 主观问卷 | 可按条件记录等待感、流畅感、不确定性等 |

### 5.7 实验二分析目标

R 分析程序应支持：

1. 按 E1 / E2 / E3 / E4 比较任务完成时间；
2. 按 E1 / E2 / E3 / E4 比较正确率；
3. 将条件编码转换为 2×2 因子：
   - `SpatialContinuity = TRUE/FALSE`
   - `ProgressiveAvailability = TRUE/FALSE`
4. 分析两个因素的主效应与交互效应；
5. 比较四个条件下加载阶段和任务阶段的眼动指标；
6. 验证实验一中的体验差异是否可由空间连续性和渐进可用性解释。

---

## 6. 条件编码推荐映射

R 程序建议内置以下条件映射表。

### 6.1 实验一条件映射

```r
exp1_condition_map <- data.frame(
  Condition = c("A", "A+", "B", "C", "C-"),
  Blocking = c(TRUE, TRUE, FALSE, FALSE, FALSE),
  HasProgress = c(FALSE, TRUE, TRUE, TRUE, FALSE),
  InScene = c(FALSE, FALSE, TRUE, TRUE, TRUE),
  ProgressiveAvailable = c(FALSE, FALSE, FALSE, TRUE, TRUE),
  Description = c(
    "Full-screen blocking, no progress",
    "Full-screen blocking, image/progress",
    "In-scene floating card with progress and object info",
    "Progressive availability with progress",
    "Progressive availability without progress"
  )
)
```

### 6.2 实验二条件映射

```r
exp2_condition_map <- data.frame(
  Condition = c("E1", "E2", "E3", "E4"),
  SpatialContinuity = c(TRUE, FALSE, TRUE, FALSE),
  ProgressiveAvailability = c(TRUE, TRUE, FALSE, FALSE),
  Description = c(
    "Spatial continuity + progressive availability",
    "No spatial continuity + progressive availability",
    "Spatial continuity + no progressive availability",
    "No spatial continuity + no progressive availability"
  )
)
```

---

## 7. 时间戳与阶段切分

数据分析中应尽量以 UE 事件时间戳和 EyeLink marker 对齐。推荐至少切分以下阶段：

| 阶段 | 说明 |
|---|---|
| `PreLoading` | 触发加载前的短时间窗口 |
| `Loading` | 加载开始到加载完成，或加载开始到最低可用状态 |
| `AvailableButLoading` | 仅适用于 C / C- / E1 / E2，表示已经最低可用但仍在继续变清晰 |
| `PostLoading` | 加载完成后到题目或任务结束 |
| `Question` | 题目显示到提交答案 |
| `TaskAction` | 实验二中从可行动到完成放置 |

实际切分应优先使用 UE 记录的事件时间戳；如果 EyeLink marker 完整，应使用 marker 进行校验。

---

## 8. 眼动指标建议

当前研究可优先关注以下眼动指标：

| 指标 | 解释 | 可能意义 |
|---|---|---|
| `FixationCount` | 注视次数 | 注意分配频率 |
| `TotalFixationDuration` | 总注视时长 | 对 AOI 或信息区域的关注程度 |
| `MeanFixationDuration` | 平均注视时长 | 认知加工负荷或信息处理深度 |
| `FirstFixationDuration` | 首次注视时长 | 初始注意捕获 |
| `TimeToFirstFixation` | 首次进入 AOI 的时间 | 用户多快注意到关键信息 |
| `DwellTime` | AOI 停留时间 | 对区域整体关注程度 |
| `SaccadeAmplitude` | 眼跳幅度 | 搜索范围或视觉扫描变化 |
| `PupilSize` | 瞳孔直径 | 可能反映认知负荷、唤醒水平，但需控制光照和场景差异 |

注意：

- 瞳孔指标对亮度、材质、画面变化较敏感，需要谨慎解释。
- 如果不同条件画面亮度差异明显，瞳孔不能直接简单解释为认知负荷。
- 动态 AOI 分析应优先用于加载卡片、模型区域、题目区域、可交互对象等明确区域。

---

## 9. 动态 AOI 说明

三维场景中的 AOI 可能不是固定屏幕区域。尤其是 B、C、C-、E1、E2、E3 中，用户视角变化或对象位置变化会导致 AOI 屏幕坐标动态变化。

当前 UE 方案会导出动态 AOI 坐标 CSV。R 程序分析时应理解：

1. AOI 是随时间变化的；
2. AOI 坐标通常应按时间戳与眼动采样点或注视事件进行匹配；
3. 如果 AOI CSV 的时间分辨率低于眼动采样率，应使用最近时间点、线性插值或时间窗口匹配；
4. 应保留 AOI 类型，例如：
   - `LoadingCard`
   - `ProgressBar`
   - `Model`
   - `QuestionPanel`
   - `TargetObject`
   - `DistractorObject`
5. 动态 AOI 分析结果建议输出为长表：

```text
ParticipantOutputID
ParticipantID
Experiment
Condition
TrialID
Phase
AOIName
AOIType
FixationCount
TotalFixationDuration
DwellTime
HitRatio
```

---

## 10. 主观问卷与行为数据

建议 R 程序将主观问卷和行为数据按以下层级组织：

| 层级 | 示例字段 |
|---|---|
| 被试级 | ParticipantID, GroupOrder, VisionInfo, GameExperience |
| 会话级 | ParticipantOutputID, SessionVersion, DateTime |
| 实验级 | Experiment = exp01 / exp02 |
| 条件级 | Condition, ConditionOrder |
| 试次级 | TrialID, ModelID, CorrectAnswer, UserAnswer, Accuracy, RT |
| 阶段级 | Phase, StartTime, EndTime |
| AOI 级 | AOIName, AOIType, EyeMetric |

---

## 11. R 程序读取建议

### 11.1 读取单位

建议以最终打包后的被试文件夹为读取单位：

```text
Saved/ExperimentData/Participants/<ParticipantOutputID>/
```

每读取一个文件夹，就添加：

```r
ParticipantOutputID <- basename(folder)
```

然后从 CSV 内部读取：

```r
ParticipantID <- csv$ParticipantID
```

### 11.2 重复编号处理

如果存在：

```text
A001/
A001_v2/
```

R 程序不应自动把它们都当作正式独立被试。应提供策略：

1. 默认保留所有 session，但标记 `SessionVersion`；
2. 可选择每名被试只保留最高版本；
3. 可选择人工指定有效 session；
4. 默认排除 `TEST`。

### 11.3 条件字段标准化

建议将条件字段统一为：

```r
Experiment
Condition
ConditionLabel
```

示例：

```text
exp01, A
exp01, A+
exp01, B
exp01, C
exp01, C-
exp02, E1
exp02, E2
exp02, E3
exp02, E4
```

避免把实验一的 `C` 与实验二的机制变量混淆。

---

## 12. 推荐输出长表

R 程序最终至少应能输出以下表：

### 12.1 被试-条件主观与行为汇总表

```text
ParticipantID
ParticipantOutputID
Experiment
Condition
ConditionOrder
Accuracy
ReactionTime
TaskCompletionTime
PAD_Pleasure
PAD_Arousal
PAD_Dominance
Satisfaction
PerceivedWaitingTime
Uncertainty
Fluency
```

### 12.2 眼动阶段长表

```text
ParticipantID
ParticipantOutputID
Experiment
Condition
TrialID
Phase
StartTime
EndTime
FixationCount
TotalFixationDuration
MeanFixationDuration
SaccadeCount
MeanSaccadeAmplitude
MeanPupilSize
```

### 12.3 AOI 长表

```text
ParticipantID
ParticipantOutputID
Experiment
Condition
TrialID
Phase
AOIName
AOIType
FixationCount
TotalFixationDuration
DwellTime
TimeToFirstFixation
HitRatio
```

### 12.4 实验二 2×2 汇总表

```text
ParticipantID
ParticipantOutputID
Condition
SpatialContinuity
ProgressiveAvailability
Accuracy
TaskCompletionTime
SubjectiveWaiting
Fluency
Uncertainty
EyeMetric...
```

---

## 13. 统计分析建议

### 13.1 实验一

实验一是五水平被试内设计。可考虑：

```text
因变量 ~ Condition + (1 | ParticipantID)
```

如果样本量和数据质量允许，可加入：

```text
因变量 ~ Condition + ConditionOrder + (1 | ParticipantID)
```

重点比较：

```text
A vs A+
A+ vs B
B vs C
C vs C-
A vs B
A vs C
```

### 13.2 实验二

实验二是 2×2 被试内设计。推荐将 E1/E2/E3/E4 转换为两个因子：

```text
因变量 ~ SpatialContinuity * ProgressiveAvailability + (1 | ParticipantID)
```

重点看：

1. 空间连续性的主效应；
2. 渐进可用性的主效应；
3. 二者交互效应。

---

## 14. 重要注意事项

1. `TEST` 数据默认不进入正式分析。
2. `ParticipantID` 表示被试，`ParticipantOutputID` 表示采集会话。
3. 若同一被试存在多个版本，例如 `A001` 和 `A001_v2`，正式分析前必须决定使用哪一次。
4. 文件名里的 `_v2` 不应简单当作新被试编号。
5. 实验一和实验二的条件编码不能混用。
6. 实验二应优先按 2×2 因子分析，而不仅是四条件均值比较。
7. 动态 AOI 必须按时间戳匹配，不能直接当成静态屏幕矩形。
8. 瞳孔指标受画面亮度、材质、加载阶段变化影响较大，需要谨慎解释。
9. 如果 UE 本地时间戳与 EyeLink marker 存在轻微偏差，应优先建立对齐校正逻辑。
10. 每个输出文件应尽量保留来源路径和原始文件名，方便追溯。

---

## 15. 给 R 分析程序 AI 的核心理解摘要

本项目不是单纯的眼动数据清洗工具，而是一个面向三维加载体验研究的实验数据分析流程。R 程序需要同时理解：

1. 实验一是五水平加载方式比较：`A / A+ / B / C / C-`。
2. 实验二是机制拆解：`E1 / E2 / E3 / E4`，本质是 `空间连续性 × 渐进可用性` 的 2×2 设计。
3. `ParticipantID` 是被试编号，`ParticipantOutputID` 是输出会话编号。
4. 重复测试不会覆盖旧数据，而是生成 `A001_v2` 等新会话。
5. `TEST` 是调试数据，应默认排除。
6. 数据分析应整合 UE CSV、动态 AOI、EyeLink ASC/EDF、主观问卷与任务表现。
7. 最终输出应尽量采用长表结构，便于混合效应模型、重复测量 ANOVA、条件比较和可视化。
---

## 16. 拉丁方与顺序平衡说明

本项目中 `G1 / G2 / G3...` 不是实验条件本身，而是**拉丁方 / 顺序平衡组**。  
R 分析程序必须区分：

| 概念 | 示例 | 含义 |
|---|---|---|
| 实验条件 | `A`, `A+`, `B`, `C`, `C-`, `E1`, `E2`, `E3`, `E4` | 被试实际经历的加载方式 |
| 拉丁方组别 | `G1`, `G2`, `G3`, `G4`, `G5` | 条件出现顺序的平衡方案 |
| 顺序位置 | `1`, `2`, `3`, `4`, `5` | 当前条件在该被试流程中的第几个出现 |
| 会话输出编号 | `A001`, `A001_v2` | 文件夹 / 输出会话，不等同于实验组 |

因此，如果数据中看到：

```text
实验一：G1
实验二：G2
```

含义应理解为：

```text
该被试实验一使用实验一拉丁方 G1 顺序；
该被试实验二使用实验二拉丁方 G2 顺序。
```

不能解释为“这个被试属于 G1 组或 G2 组的实验处理组”。  
`G1/G2` 主要用于控制条件顺序、目标内容、目标位置等顺序效应。

---

## 17. 实验一拉丁方结构

实验一是五水平被试内设计，五个条件分别为：

```text
A, A+, B, C-, C
```

当前实验一的拉丁方通过 `Experiment1LatinManager` 控制。每个被试只选择一个实验一拉丁方组别。该组别决定五个展台 / 五个试次依次使用哪种加载条件。

### 17.1 实验一拉丁方组别映射

| 实验一拉丁方组 | 第 1 个条件 | 第 2 个条件 | 第 3 个条件 | 第 4 个条件 | 第 5 个条件 |
|---|---|---|---|---|---|
| `G1` | `A` | `A+` | `B` | `C-` | `C` |
| `G2` | `A+` | `B` | `C-` | `C` | `A` |
| `G3` | `B` | `C-` | `C` | `A` | `A+` |
| `G4` | `C-` | `C` | `A` | `A+` | `B` |
| `G5` | `C` | `A` | `A+` | `B` | `C-` |

### 17.2 实验一 CSV 中的相关字段

实验一答题 CSV 中应重点读取以下字段：

| 字段名 | 含义 | 示例 |
|---|---|---|
| `Experiment` | 实验编号 | `exp01` |
| `LoadingCondition` | 实际加载条件 | `A`, `A_PLUS`, `B`, `C_MINUS`, `C` |
| `Experiment1LatinGroup` | 实验一拉丁方组别 | `G1` |
| `Experiment1SequenceIndex` | 当前条件在该组顺序中的位置，1-based | `1`, `2`, `3`, `4`, `5` |
| `Experiment1SequenceLabel` | 组别与顺序位置组合标签 | `G1_T01`, `G1_T02` |

R 程序应把 `Experiment1LatinGroup` 和 `Experiment1SequenceIndex` 作为顺序控制变量，而不是作为主要实验条件。

### 17.3 实验一条件编码标准化建议

源码中可能出现较长或兼容性编码。建议 R 程序标准化为论文中使用的简短条件名：

| 原始编码可能值 | 标准条件名 |
|---|---|
| `A` 或 `NoObviousFeedback` | `A` |
| `A_PLUS` 或 `FullscreenPreview` | `A+` |
| `B` 或 `PlaceholderFeedback` | `B` |
| `C_MINUS` 或 `ProgressiveNoProgressBar` | `C-` |
| `C` 或 `ProgressiveLoading` | `C` |

推荐在 R 中新增字段：

```r
Exp1ConditionStd
```

并将其统一为：

```r
A, A+, B, C-, C
```

### 17.4 实验一统计分析中的处理方式

实验一主效应应分析：

```text
因变量 ~ Exp1ConditionStd
```

顺序效应控制变量可加入：

```text
因变量 ~ Exp1ConditionStd + Experiment1SequenceIndex + Experiment1LatinGroup
```

如果使用混合模型，可考虑：

```text
因变量 ~ Exp1ConditionStd + Experiment1SequenceIndex + (1 | ParticipantID)
```

在样本量较小的情况下，`Experiment1LatinGroup` 只作为检查或控制变量即可，不建议把它当作核心理论因素解释。

---

## 18. 实验二拉丁方结构

实验二是四条件 2×2 被试内设计，四个条件分别为：

| 条件 | 空间连续性 | 渐进可用性 |
|---|---:|---:|
| `E1` | 有 | 有 |
| `E2` | 无 | 有 |
| `E3` | 有 | 无 |
| `E4` | 无 | 无 |

实验二的拉丁方通过 `Experiment2TrialManager` 控制。每个被试选择一个实验二 `SequenceGroup`，即 G1-G4。该组别同时平衡：

1. 四个实验二条件的出现顺序；
2. 目标内容；
3. 目标显示位置。

### 18.1 实验二条件顺序映射

实验二代码中 `SequenceGroup` 是数字字段：

```text
SequenceGroup = 1 代表 G1
SequenceGroup = 2 代表 G2
SequenceGroup = 3 代表 G3
SequenceGroup = 4 代表 G4
```

条件顺序如下：

| 实验二拉丁方组 | `SequenceGroup` | 第 1 个条件 | 第 2 个条件 | 第 3 个条件 | 第 4 个条件 |
|---|---:|---|---|---|---|
| `G1` | `1` | `E1` | `E2` | `E4` | `E3` |
| `G2` | `2` | `E2` | `E3` | `E1` | `E4` |
| `G3` | `3` | `E3` | `E4` | `E2` | `E1` |
| `G4` | `4` | `E4` | `E1` | `E3` | `E2` |

注意：实验二 G1-G4 与实验一 G1-G5 是两个不同系统。  
一个被试可以是：

```text
实验一 LatinGroup = G1
实验二 SequenceGroup = 2
```

这表示该被试实验一采用 G1 顺序，实验二采用 G2 顺序。

### 18.2 实验二 CSV 中的相关字段

实验二 CSV 中应重点读取以下字段：

| 字段名 | 含义 | 示例 |
|---|---|---|
| `Experiment` | 实验编号 | `exp02` |
| `Condition` | 实际实验二条件 | `E1_SPATIAL_PROGRESSIVE` |
| `SpatialContinuity` | 是否空间连续 | `1` / `0` |
| `ProgressiveAvailability` | 是否渐进可用 | `1` / `0` |
| `SequenceGroup` | 实验二拉丁方组，数字 1-4 | `2` |
| `SequenceIndex` | 当前条件在该组顺序中的位置，1-based | `1`, `2`, `3`, `4` |
| `TargetContentIndex` | 当前试次目标内容编号 | `1`-`4` |
| `TargetDisplayIndex` | 当前试次目标显示位置 | `1`-`4` |
| `SlotPermutation` | 四个显示槽位与内容的对应关系 | 例如 `1,3,2,4` |
| `SubmitCorrect` | 最终提交是否正确 | `1` / `0` |

### 18.3 实验二条件编码标准化建议

建议 R 程序新增字段：

```r
Exp2ConditionStd
```

映射如下：

| 原始编码 | 标准条件名 |
|---|---|
| `E1_SPATIAL_PROGRESSIVE` | `E1` |
| `E2_FIXED_PROGRESSIVE` | `E2` |
| `E3_SPATIAL_NONPROGRESSIVE` | `E3` |
| `E4_FIXED_NONPROGRESSIVE` | `E4` |

同时保留或派生：

```r
SpatialContinuity = TRUE/FALSE
ProgressiveAvailability = TRUE/FALSE
Exp2LatinGroup = paste0("G", SequenceGroup)
```

### 18.4 实验二统计分析中的处理方式

实验二不应只做四条件均值比较，还应转成 2×2 因子结构：

```text
因变量 ~ SpatialContinuity * ProgressiveAvailability
```

顺序控制变量可加入：

```text
因变量 ~ SpatialContinuity * ProgressiveAvailability + SequenceIndex + SequenceGroup
```

混合模型可考虑：

```text
因变量 ~ SpatialContinuity * ProgressiveAvailability + SequenceIndex + (1 | ParticipantID)
```

其中：

- `SpatialContinuity` 和 `ProgressiveAvailability` 是理论主变量；
- `SequenceGroup` 和 `SequenceIndex` 是顺序平衡 / 控制变量；
- `TargetContentIndex` 和 `TargetDisplayIndex` 可用于检查目标内容和位置是否造成偏差。

---

## 19. R 程序读取 G1/G2 时的最低要求

如果 R 程序只能看到类似：

```text
ParticipantID = A001
Experiment1LatinGroup = G1
Experiment2SequenceGroup = 2
```

应解析为：

```text
A001 的实验一条件顺序：A → A+ → B → C- → C
A001 的实验二条件顺序：E2 → E3 → E1 → E4
```

不要把它解析为：

```text
A001 属于实验组 G1 或 G2
```

更不要把实验一的 G1 和实验二的 G2 合并成一个统一的 `Group` 字段。  
推荐使用两个独立字段：

```r
Exp1LatinGroup
Exp2LatinGroup
```

以及两个独立的顺序字段：

```r
Exp1SequenceIndex
Exp2SequenceIndex
```

---

## 20. 推荐新增的 R 派生字段

读取数据后，建议 R 程序派生以下字段：

```r
ParticipantOutputID
ParticipantID
Experiment
Exp1LatinGroup
Exp1SequenceIndex
Exp2LatinGroup
Exp2SequenceIndex
ConditionRaw
ConditionStd
ConditionOrder
SpatialContinuity
ProgressiveAvailability
SessionVersion
IsTestRun
```

字段说明：

| 字段 | 说明 |
|---|---|
| `ParticipantOutputID` | 文件夹名，例如 `A001_v2` |
| `ParticipantID` | CSV 内部被试编号，例如 `A001` |
| `Experiment` | `exp01` 或 `exp02` |
| `Exp1LatinGroup` | 实验一拉丁方组，G1-G5 |
| `Exp1SequenceIndex` | 实验一条件顺序位置，1-5 |
| `Exp2LatinGroup` | 实验二拉丁方组，G1-G4 |
| `Exp2SequenceIndex` | 实验二条件顺序位置，1-4 |
| `ConditionRaw` | 原始条件编码 |
| `ConditionStd` | 标准化条件编码，A/A+/B/C-/C 或 E1/E2/E3/E4 |
| `ConditionOrder` | 当前实验内部的条件出现顺序 |
| `SpatialContinuity` | 实验二机制变量 |
| `ProgressiveAvailability` | 实验二机制变量 |
| `SessionVersion` | A001=1，A001_v2=2 |
| `IsTestRun` | 是否 TEST 调试数据 |

