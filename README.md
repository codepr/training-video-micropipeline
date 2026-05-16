# Training Video Processing Pipeline

PoC lightweight Ruby pipeline for detecting newly uploaded training videos,
trimming dead time with FFmpeg scene detection, compressing the result, and
saving metadata to SQLite.

Ideal scenario
- record working set
- auto-upload to pre-defined cloud directory (can be Gdrive, dropbox, anything with APIs)
- watchdog will trim out the unnecessary parts and add a link automatically to a specific place in a training log spreadsheet, or anything else with APIs

Didn't type a single line of this, Codex took care of it.

## Setup

```bash
bundle install
brew install ffmpeg
```

## Run

```bash
bin/training-video-pipeline
```

The daemon watches `incoming/`, waits for file size stabilization, moves stable videos into `processing/`, detects a motion window, writes trimmed clips to `processed/`, archives originals in `archive/raw/`, and records metadata in `db/metadata.sqlite3`.

Configuration lives in `config/config.yml`.

## Test

```bash
ruby -Itest test/config_test.rb
ruby -Itest test/motion_detector_test.rb
```
