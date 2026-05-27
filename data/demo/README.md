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
