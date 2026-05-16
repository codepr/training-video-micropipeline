# Training Video Processing Pipeline

Lightweight Ruby pipeline for detecting newly uploaded training videos, trimming dead time with FFmpeg scene detection, compressing the result, and saving metadata to SQLite.
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
