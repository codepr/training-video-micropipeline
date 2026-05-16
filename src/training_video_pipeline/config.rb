module TrainingVideoPipeline
  class Config
    DEFAULTS = {
      "incoming_dir" => "./incoming",
      "processing_dir" => "./processing",
      "processed_dir" => "./processed",
      "failed_dir" => "./failed",
      "raw_archive_dir" => "./archive/raw",
      "log_file" => "./logs/pipeline.log",
      "database_path" => "./db/metadata.sqlite3",
      "video_extensions" => [".mp4", ".mov", ".m4v", ".mkv"],
      "upload" => {
        "stabilization_seconds" => 10,
        "poll_interval_seconds" => 5
      },
      "motion_detection" => {
        "strategy" => "frame_difference",
        "threshold" => 0.02,
        "frame_difference_threshold" => 6.0,
        "maximum_frame_difference" => 60.0,
        "minimum_activity_duration" => 0.5,
        "merge_gap_seconds" => 3,
        "ignore_head_seconds" => 10,
        "ignore_tail_seconds" => 5,
        "discard_terminal_motion" => false,
        "terminal_motion_gap_seconds" => 1.25,
        "terminal_motion_margin_seconds" => 1.0,
        "sample_fps" => 2,
        "frame_width" => 64,
        "frame_height" => 36,
        "activity_selection" => "exercise_group",
        "later_group_weight" => 0.1,
        "presence_fallback" => {
          "enabled" => true,
          "threshold" => 18.0,
          "reference_seconds" => 1.0,
          "minimum_motion_window_seconds" => 8.0,
          "late_motion_start_seconds" => 40.0,
          "minimum_presence_window_seconds" => 12.0,
          "low_motion_anchor_threshold" => 3.0,
          "low_motion_anchor_minimum_events" => 3,
          "low_motion_anchor_trim_margin_seconds" => 3.0,
          "low_motion_anchor_max_end_trim_seconds" => 5.0
        }
      },
      "trimming" => {
        "pre_buffer_seconds" => 3,
        "post_buffer_seconds" => 1
      },
      "compression" => {
        "crf" => 28,
        "preset" => "medium",
        "video_codec" => "libx264",
        "audio_codec" => "aac"
      }
    }.freeze

    attr_reader :root

    def self.load(path)
      new(path)
    end

    def initialize(path)
      @path = File.expand_path(path)
      @root = File.expand_path("..", File.dirname(@path))
      loaded = File.exist?(@path) ? YAML.safe_load(File.read(@path)) : {}
      @data = deep_merge(DEFAULTS, loaded || {})
    end

    def [](key)
      @data.fetch(key.to_s)
    end

    def fetch(*keys)
      keys.reduce(@data) { |memo, key| memo.fetch(key.to_s) }
    end

    def path(key)
      value = self[key]
      File.expand_path(value, root)
    end

    def ensure_directories!
      %w[incoming_dir processing_dir processed_dir failed_dir raw_archive_dir].each do |key|
        FileUtils.mkdir_p(path(key))
      end

      FileUtils.mkdir_p(File.dirname(path("log_file")))
      FileUtils.mkdir_p(File.dirname(path("database_path")))
      FileUtils.mkdir_p(File.expand_path("tmp", root))
    end

    private

    def deep_merge(left, right)
      left.merge(right) do |_key, old_value, new_value|
        if old_value.is_a?(Hash) && new_value.is_a?(Hash)
          deep_merge(old_value, new_value)
        else
          new_value
        end
      end
    end
  end
end
