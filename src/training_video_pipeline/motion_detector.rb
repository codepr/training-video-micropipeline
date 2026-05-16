module TrainingVideoPipeline
  class MotionDetector
    Window = Struct.new(:start_time, :end_time, keyword_init: true)

    def initialize(ffmpeg:, config:, logger:)
      @ffmpeg = ffmpeg
      @config = config
      @logger = logger
    end

    def detect(path)
      duration = @ffmpeg.duration(path)
      settings = @config.fetch("motion_detection")
      timestamps = motion_timestamps(path, settings)

      @logger.info("motion.events count=#{timestamps.length} path=#{path}")
      window = activity_window(timestamps, duration)
      presence_fallback(path, settings, duration, window) || window
    end

    def activity_window(timestamps, duration)
      return full_window(duration) if timestamps.empty?

      window = activity_window_with_tail_ignore(timestamps, duration, use_tail_ignore: true)
      fallback = activity_window_with_tail_ignore(timestamps, duration, use_tail_ignore: false)
      return fallback if prefer_tail_fallback?(window, fallback, duration)

      window
    end

    def activity_window_with_tail_ignore(timestamps, duration, use_tail_ignore:)
      settings = @config.fetch("motion_detection")
      trimming = @config.fetch("trimming")
      merge_gap = settings.fetch("merge_gap_seconds").to_f
      minimum = settings.fetch("minimum_activity_duration").to_f
      ignore_before = settings.fetch("ignore_head_seconds").to_f
      ignore_after = if use_tail_ignore
                       duration - settings.fetch("ignore_tail_seconds").to_f
                     else
                       duration
                     end
      timestamps = timestamps.select do |timestamp|
        timestamp >= ignore_before && timestamp <= ignore_after
      end
      timestamps = discard_terminal_motion(timestamps, ignore_after, settings)
      return full_window(duration) if timestamps.empty?

      groups = group_timestamps(timestamps, merge_gap)
      total_motion_span = timestamps.last - timestamps.first
      return full_window(duration) if total_motion_span < minimum

      selected_groups = select_activity_groups(groups, settings)

      start_time = selected_groups.first.first - trimming.fetch("pre_buffer_seconds").to_f
      end_time = selected_groups.last.last + trimming.fetch("post_buffer_seconds").to_f

      Window.new(
        start_time: [0.0, start_time].max,
        end_time: [duration, end_time].min
      )
    end

    private

    def motion_timestamps(path, settings)
      if settings.fetch("strategy") == "scene"
        return @ffmpeg.scene_timestamps(
          path,
          threshold: settings.fetch("threshold"),
          sample_fps: settings.fetch("sample_fps")
        )
      end

      scores = @ffmpeg.frame_difference_scores(
        path,
        sample_fps: settings.fetch("sample_fps"),
        width: settings.fetch("frame_width"),
        height: settings.fetch("frame_height")
      )
      threshold = settings.fetch("frame_difference_threshold").to_f
      maximum = settings.fetch("maximum_frame_difference").to_f
      active_scores = scores.select do |_timestamp, score|
        score >= threshold && score <= maximum
      end
      log_score_summary(scores, threshold)
      active_scores.map(&:first)
    end

    def presence_fallback(path, settings, duration, motion_window)
      fallback_settings = settings.fetch("presence_fallback")
      return nil unless fallback_settings.fetch("enabled")
      return nil unless presence_fallback_candidate?(motion_window, fallback_settings)

      scores = @ffmpeg.background_difference_scores(
        path,
        sample_fps: settings.fetch("sample_fps"),
        width: settings.fetch("frame_width"),
        height: settings.fetch("frame_height"),
        reference_seconds: fallback_settings.fetch("reference_seconds")
      )
      threshold = fallback_settings.fetch("threshold").to_f
      timestamps = scores.select { |_timestamp, score| score >= threshold }.map(&:first)
      return nil if timestamps.empty?

      presence_window = activity_window(timestamps, duration)
      presence_window = refine_presence_window_with_motion_anchor(
        path,
        settings,
        fallback_settings,
        duration,
        presence_window
      )
      return nil if window_duration(presence_window) < fallback_settings.fetch("minimum_presence_window_seconds").to_f

      @logger.info(
        "motion.presence_fallback start=#{presence_window.start_time} end=#{presence_window.end_time}"
      )
      presence_window
    end

    def presence_fallback_candidate?(motion_window, fallback_settings)
      return true if window_duration(motion_window) < fallback_settings.fetch("minimum_motion_window_seconds").to_f

      motion_window.start_time >= fallback_settings.fetch("late_motion_start_seconds").to_f
    end

    def refine_presence_window_with_motion_anchor(path, settings, fallback_settings, duration, presence_window)
      scores = @ffmpeg.frame_difference_scores(
        path,
        sample_fps: settings.fetch("sample_fps"),
        width: settings.fetch("frame_width"),
        height: settings.fetch("frame_height")
      )
      threshold = fallback_settings.fetch("low_motion_anchor_threshold").to_f
      maximum = settings.fetch("maximum_frame_difference").to_f
      ignore_before = settings.fetch("ignore_head_seconds").to_f
      ignore_after = duration - settings.fetch("ignore_tail_seconds").to_f
      timestamps = scores.select do |timestamp, score|
        timestamp >= ignore_before &&
          timestamp <= ignore_after &&
          score >= threshold &&
          score <= maximum
      end.map(&:first)
      return presence_window if timestamps.empty?

      groups = group_timestamps(timestamps, settings.fetch("merge_gap_seconds").to_f)
      minimum_events = fallback_settings.fetch("low_motion_anchor_minimum_events").to_i
      anchor = groups.find { |group| group.length >= minimum_events }
      return presence_window unless anchor

      trim_margin = fallback_settings.fetch("low_motion_anchor_trim_margin_seconds").to_f
      post_buffer = @config.fetch("trimming", "post_buffer_seconds").to_f
      max_end_trim = fallback_settings.fetch("low_motion_anchor_max_end_trim_seconds").to_f
      start_time = [presence_window.start_time, anchor.first - trim_margin].max
      anchored_end = timestamps.last + post_buffer
      end_time = if presence_window.end_time - anchored_end <= max_end_trim
                   [presence_window.end_time, anchored_end].min
                 else
                   presence_window.end_time
                 end

      Window.new(start_time: start_time, end_time: end_time)
    end

    def group_timestamps(timestamps, merge_gap)
      timestamps.each_with_object([]) do |timestamp, groups|
        if groups.empty? || timestamp - groups.last.last > merge_gap
          groups << [timestamp]
        else
          groups.last << timestamp
        end
      end
    end

    def discard_terminal_motion(timestamps, ignore_after, settings)
      return timestamps unless settings.fetch("discard_terminal_motion")

      terminal_gap = settings.fetch("terminal_motion_gap_seconds").to_f
      terminal_margin = settings.fetch("terminal_motion_margin_seconds").to_f
      groups = group_timestamps(timestamps, terminal_gap)
      return timestamps unless groups.length > 1
      return timestamps unless ignore_after - groups.last.last <= terminal_margin

      dropped = groups.pop
      @logger.info(
        "motion.terminal_discard start=#{dropped.first} end=#{dropped.last} count=#{dropped.length}"
      )
      groups.flatten
    end

    def select_activity_groups(groups, settings)
      strategy = settings.fetch("activity_selection")
      return groups if strategy == "all_groups"

      if strategy == "exercise_group"
        later_group_weight = settings.fetch("later_group_weight").to_f
        return [groups.max_by { |group| exercise_group_score(group, later_group_weight) }]
      end

      [groups.max_by { |group| [group.last - group.first, group.length] }]
    end

    def exercise_group_score(group, later_group_weight)
      duration = group.last - group.first
      duration + group.length + (group.first * later_group_weight)
    end

    def full_window(duration)
      Window.new(start_time: 0.0, end_time: duration)
    end

    def prefer_tail_fallback?(window, fallback, duration)
      return false if fallback.end_time >= duration - 1.0
      return false unless fallback.start_time > window.start_time

      fallback.start_time - window.start_time >= 10.0
    end

    def window_duration(window)
      window.end_time - window.start_time
    end

    def log_score_summary(scores, threshold)
      values = scores.map(&:last)
      return if values.empty?

      sorted = values.sort
      median = sorted[sorted.length / 2]
      max = sorted.last
      @logger.info(
        "motion.frame_difference samples=#{scores.length} threshold=#{threshold} median=#{median.round(3)} max=#{max.round(3)}"
      )
    end
  end
end
