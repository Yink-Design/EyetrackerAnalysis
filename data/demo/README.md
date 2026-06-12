# Demo data

The full `FM164641.asc` file is the recommended reference file for local testing.

Expected counts for the provided test file are stored in `FM164641_expected_counts.csv`:

- samples: 94,009
- fixations: 126
- saccades: 125
- blinks: 17
- messages: 91
- events: 21
- trials: 2
- sampling rate: 2000 Hz
- recorded eye: RIGHT
- display coordinates: 0,0,1919,1079

Place the full file here when running locally:

```text
data/demo/FM164641.asc
```

The original file is not required for package installation, but it is useful for regression testing the parser.

## Formal experiment V2 package

`data/demo/V2/610FullTrialTest/` is the current reference package for the formal
experiment output contract. Unlike the original pre-experiment demo, it represents
one continuous participant session containing two sequential experiments.

```text
610FullTrialTest/
|- DataCollectionManifest.csv
|- AOI/
|  `- 610FullTrialTest_DynamicAOI.csv
|- CSV/
|  |- 610FullTrialTest_exp01_InspectQuestionResults.csv
|  |- 610FullTrialTest_exp02_Experiment2Results.csv
|  `- 610FullTrialTest_ExperimentEndEvent.csv
|- EDF/
|  |- FM214601.EDF
|  `- FM214601.asc
|- Logs/
|  |- EyeLinkMarkers_20260610_213958_880.log
|  `- ScreenRecordingLog.csv
`- ScreenRecordings/
   `- 610FullTrialTest_20260610_214930_screen.mkv
```

### Session flow

The ASC records `EXPERIMENT_RUN_MODE EXP1_THEN_EXP2`.

| Experiment | Trial IDs | Result granularity | Main conditions |
|---|---|---|---|
| EXP1 | `T001`-`T006` | one row per question | `A`, `A_PLUS`, `B`, `C`, `C_MINUS` |
| EXP2 | `Exp2_001`-`Exp2_004` | one row per event | `E1_SPATIAL_PROGRESSIVE`, `E2_FIXED_PROGRESSIVE`, `E3_SPATIAL_NONPROGRESSIVE`, `E4_FIXED_NONPROGRESSIVE` |

EXP1 uses the existing loading/viewer/question marker contract. EXP2 uses separate
`EXP2_*` markers for loading, object stage changes, progressive usability, pending
selection, and submitted selection. The two marker families must be normalized by
experiment before constructing phases.

### Dynamic AOI contract

The V2 dynamic AOI file has 1,407 rows and includes:

- EXP1 condition B: `b_preview_panel` for `T006`.
- EXP2 conditions E1, E2, and E3: `exp2_table_objects` and `exp2_target_object`.
- No dynamic AOI rows for E4.

Use `video_time_start_ms` / `video_time_end_ms` for recording preview and the
EyeLink/UE/Unix timing fields for formal alignment. `ScreenRecordingLog.csv` contains
historical rows from multiple sessions and must be filtered to the current participant
and recording.

### Parser status

The parser now discovers all ten `TRIALID` markers, retains EXP1/EXP2 trial variables,
normalizes bare EXP2 `TRIAL_RESULT` markers, and builds experiment-specific phases.
The Shiny app can load this directory directly from the local formal-participant path
input and generate EXP1, EXP2, package-inventory, and formal dynamic AOI reports.
