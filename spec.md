
# Training Video Processing Pipeline — Technical Specification

## Project Overview

Build a lightweight automated video-processing pipeline for strength training and calisthenics recordings.

The system should:

1. Detect newly uploaded videos from Android
2. Wait until upload completes
3. Automatically detect the meaningful activity segment
4. Trim dead time before/after the set
5. Compress the resulting clip
6. Store processed videos in an organized archive
7. Maintain metadata for future integrations
8. Be implemented in Ruby
9. Use FFmpeg for all video processing
10. Be simple, maintainable, and extensible

---

# Goals

The primary goal is to create a low-friction workflow for training analysis.

Desired workflow:

```text
Record training set on Android
→ auto-upload/sync to server
→ automatic processing
→ short trimmed clip archived
→ optionally linked later into Google Sheets or Obsidian
```

The system should prioritize:

* simplicity
* reliability
* maintainability
* low operational overhead

The system should NOT initially include:

* AI
* pose estimation
* exercise classification
* machine learning
* cloud dependencies

---

# Technology Stack

## Language

* Ruby 3.3+

## Core Libraries

### File Watching

Use:

* `listen`

### Video Processing

Use:

* FFmpeg CLI directly
* avoid unnecessary wrappers initially

### Metadata Storage

Use:

* SQLite

### Configuration

Use:

* YAML

### Logging

Use:

* standard Ruby Logger

---

# System Architecture

## High-Level Pipeline

```text
incoming video
→ upload completion detection
→ motion analysis
→ activity window detection
→ trim
→ compress
→ archive
→ metadata persistence
```

---

# Directory Structure

```text
training-video-pipeline/
│
├── config/
│   └── config.yml
│
├── incoming/
│
├── processing/
│
├── processed/
│
├── archive/
│
├── failed/
│
├── logs/
│
├── db/
│   └── metadata.sqlite3
│
├── tmp/
│
└── src/
```

---

# Video Lifecycle

## 1. Incoming

Videos arrive from:

* Syncthing
* FolderSync
* Google Drive sync
* manual copy

Videos are initially placed in:

```text
incoming/
```

---

## 2. Upload Completion Detection

The system MUST NOT process incomplete uploads.

Implementation requirement:

* poll filesize
* wait until filesize stabilizes

Recommended algorithm:

```text
Check filesize
Wait N seconds
Check filesize again

If unchanged:
    upload considered complete
Else:
    continue waiting
```

Configurable:

* polling interval
* stabilization duration

---

## 3. Move to Processing

Once upload is stable:

```text
incoming/
→ processing/
```

This prevents duplicate processing.

---

# Motion Detection Requirements

## Objective

Detect the meaningful activity window.

Example:

```text
00:00-00:15 idle/setup
00:16-00:42 lifting activity
00:43-01:10 idle/walking
```

Output:

```text
00:14-00:45
```

---

# Motion Detection Strategy

## IMPORTANT

Do NOT use AI or ML initially.

Use simple frame-difference motion detection.

---

# Preferred Implementation

Use FFmpeg scene/motion detection filters.

Possible approaches:

## Option A — FFmpeg Scene Detection

Example:

```bash
ffmpeg -i input.mp4 -vf "select='gt(scene,0.02)',metadata=print" -f null -
```

Parse timestamps where meaningful frame changes occur.

---

## Option B — FFmpeg Blackdetect + Motion Heuristics

Optional future enhancement.

---

## Option C — OpenCV

Allowed only as future enhancement.

Initial implementation should avoid OpenCV unless necessary.

---

# Activity Window Detection

The system should:

1. Detect timestamps with significant motion
2. Group nearby motion events
3. Determine:

   * activity_start
   * activity_end
4. Apply configurable buffer:

   * pre-buffer
   * post-buffer

Example:

```yaml
pre_buffer_seconds: 3
post_buffer_seconds: 3
```

---

# Trimming Requirements

Use FFmpeg.

Example:

```bash
ffmpeg -ss START -to END -i input.mp4 output.mp4
```

Requirements:

* preserve audio
* preserve reasonable quality
* optimize for storage efficiency

---

# Compression Requirements

After trimming:

* compress final output
* target efficient archival quality

Recommended FFmpeg settings:

```bash
ffmpeg -i input.mp4 \
  -vcodec libx264 \
  -crf 28 \
  -preset medium \
  output.mp4
```

Compression settings MUST be configurable.

---

# Output Naming Convention

Format:

```text
YYYY-MM-DD_HHMMSS_trimmed.mp4
```

Optional future enhancement:

* exercise name inference from folder

---

# Output Storage

Processed videos stored in:

```text
processed/
```

Original videos optionally moved to:

```text
archive/raw/
```

Failed videos moved to:

```text
failed/
```

---

# Metadata Requirements

Persist metadata in SQLite.

## Table: videos

Suggested schema:

```sql
CREATE TABLE videos (
    id INTEGER PRIMARY KEY,
    original_filename TEXT,
    processed_filename TEXT,
    original_path TEXT,
    processed_path TEXT,
    created_at DATETIME,
    processed_at DATETIME,
    duration_original REAL,
    duration_processed REAL,
    activity_start REAL,
    activity_end REAL,
    processing_status TEXT,
    error_message TEXT
);
```

---

# Logging Requirements

Log:

* file detection
* upload stabilization
* motion detection
* trim timestamps
* FFmpeg execution
* failures
* processing duration

Log file:

```text
logs/pipeline.log
```

Use structured readable logs.

---

# Configuration Requirements

Use YAML config.

Example:

```yaml
incoming_dir: "./incoming"
processing_dir: "./processing"
processed_dir: "./processed"
failed_dir: "./failed"

upload:
  stabilization_seconds: 10
  poll_interval_seconds: 5

motion_detection:
  threshold: 0.02
  minimum_activity_duration: 2
  merge_gap_seconds: 3

trimming:
  pre_buffer_seconds: 3
  post_buffer_seconds: 3

compression:
  crf: 28
  preset: "medium"
```

---

# Daemon Behavior

The service should run continuously.

Requirements:

* watch incoming directory
* process sequentially initially
* avoid concurrent processing initially
* resilient to crashes

Recommended implementation:

* simple long-running Ruby process

---

# Failure Handling

If processing fails:

1. log error
2. move file to `failed/`
3. persist error in DB
4. continue processing next file

The daemon MUST NOT crash due to a single bad file.

---

# Extensibility Requirements

The architecture should allow future additions:

## Possible Future Features

### Exercise Classification

Based on:

* folder
* metadata
* motion signature

### Spreadsheet Integration

* Google Sheets API

### Obsidian Integration

* generate markdown notes

### Thumbnail Generation

Generate representative frame preview.

### Web Dashboard

Simple Sinatra dashboard for browsing clips.

### Tagging

Exercise type, RPE, notes.

### Pose Estimation

Optional future AI feature.

---

# Non-Goals (Initial Version)

Do NOT implement initially:

* machine learning
* GPU acceleration
* real-time processing
* cloud-native architecture
* distributed queues
* user authentication
* mobile app
* web frontend

---

# Recommended Development Plan

## Phase 1 — Prototype

Implement:

* folder watcher
* upload stabilization
* FFmpeg trim
* manual timestamp testing

Goal:

* prove trimming pipeline

---

## Phase 2 — Motion Detection

Implement:

* automatic motion window detection
* buffering
* metadata persistence

Goal:

* fully automated trimming

---

## Phase 3 — Productionization

Implement:

* robust logging
* failure handling
* cleanup
* configuration system

Goal:

* stable daemon

---

# Expected Scale

The system should comfortably handle:

* 10–100 videos/day
* short clips (30s–5min)
* 1080p recordings

Performance optimization is NOT a priority initially.

---

# Success Criteria

The project is successful if:

1. New training videos are automatically detected
2. Dead time is reliably removed
3. Final clips are short and reviewable
4. Storage usage is reduced significantly
5. The workflow becomes nearly frictionless
6. The system runs unattended for long periods

---

# Implementation Philosophy

Prefer:

* simple
* explicit
* debuggable
* UNIX-style tooling
* FFmpeg-centric processing

Avoid:

* premature abstraction
* overengineering
* unnecessary AI
* complex infrastructure

The system should feel like:

* a reliable personal utility
* not a startup platform.
