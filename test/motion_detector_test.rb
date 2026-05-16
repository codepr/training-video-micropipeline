require_relative "test_helper"

class MotionDetectorTest < Minitest::Test
  FakeFFmpeg = Struct.new(:duration_value, :motion_scores, :anchor_scores, :presence_scores, keyword_init: true) do
    def duration(_path)
      duration_value
    end

    def frame_difference_scores(_path, sample_fps:, width:, height:)
      @frame_difference_calls ||= 0
      @frame_difference_calls += 1
      @frame_difference_calls == 1 ? motion_scores : (anchor_scores || motion_scores)
    end

    def background_difference_scores(_path, sample_fps:, width:, height:, reference_seconds:)
      presence_scores
    end
  end

  def test_activity_window_selects_largest_motion_group_and_applies_buffers
    config = TrainingVideoPipeline::Config.load(File.expand_path("../config/config.yml", __dir__))
    detector = TrainingVideoPipeline::MotionDetector.new(
      ffmpeg: nil,
      config: config,
      logger: Logger.new(File::NULL)
    )

    window = detector.activity_window([16.0, 18.0, 20.0, 41.0, 42.0], 70.0)

    assert_equal 13.0, window.start_time
    assert_equal 21.0, window.end_time
  end

  def test_activity_window_uses_full_clip_when_no_motion_events_exist
    config = TrainingVideoPipeline::Config.load(File.expand_path("../config/config.yml", __dir__))
    detector = TrainingVideoPipeline::MotionDetector.new(
      ffmpeg: nil,
      config: config,
      logger: Logger.new(File::NULL)
    )

    window = detector.activity_window([], 12.5)

    assert_equal 0.0, window.start_time
    assert_equal 12.5, window.end_time
  end

  def test_activity_window_ignores_configured_tail_motion
    config = TrainingVideoPipeline::Config.load(File.expand_path("../config/config.yml", __dir__))
    detector = TrainingVideoPipeline::MotionDetector.new(
      ffmpeg: nil,
      config: config,
      logger: Logger.new(File::NULL)
    )

    window = detector.activity_window([12.0, 13.0, 14.0, 57.0, 58.0, 59.0], 60.0)

    assert_equal 9.0, window.start_time
    assert_equal 15.0, window.end_time
  end

  def test_activity_window_prefers_later_group_when_groups_are_similar
    config = TrainingVideoPipeline::Config.load(File.expand_path("../config/config.yml", __dir__))
    detector = TrainingVideoPipeline::MotionDetector.new(
      ffmpeg: nil,
      config: config,
      logger: Logger.new(File::NULL)
    )

    window = detector.activity_window([12.0, 13.0, 14.0, 15.0, 32.5, 33.0, 34.0, 35.0], 50.0)

    assert_equal 29.5, window.start_time
    assert_equal 36.0, window.end_time
  end

  def test_activity_window_ignores_configured_head_motion
    config = TrainingVideoPipeline::Config.load(File.expand_path("../config/config.yml", __dir__))
    detector = TrainingVideoPipeline::MotionDetector.new(
      ffmpeg: nil,
      config: config,
      logger: Logger.new(File::NULL)
    )

    window = detector.activity_window([1.0, 2.0, 3.0, 32.5, 33.0, 33.5], 50.0)

    assert_equal 29.5, window.start_time
    assert_equal 34.5, window.end_time
  end

  def test_activity_window_can_discard_terminal_motion_cluster_before_grouping
    config_path = File.expand_path("../tmp_terminal_motion_config.yml", __dir__)
    File.write(config_path, <<~YAML)
      motion_detection:
        discard_terminal_motion: true
    YAML
    config = TrainingVideoPipeline::Config.load(config_path)
    detector = TrainingVideoPipeline::MotionDetector.new(
      ffmpeg: nil,
      config: config,
      logger: Logger.new(File::NULL)
    )

    timestamps = [32.5, 33.0, 33.5, 35.5, 36.0, 36.5, 37.0, 37.5, 38.0, 38.5, 39.0, 39.5]
    window = detector.activity_window(timestamps, 44.725544)

    assert_equal 29.5, window.start_time
    assert_equal 34.5, window.end_time
  ensure
    FileUtils.rm_f(config_path) if config_path
  end

  def test_activity_window_keeps_lift_finish_when_terminal_discard_is_disabled
    config = TrainingVideoPipeline::Config.load(File.expand_path("../config/config.yml", __dir__))
    detector = TrainingVideoPipeline::MotionDetector.new(
      ffmpeg: nil,
      config: config,
      logger: Logger.new(File::NULL)
    )

    timestamps = [32.5, 33.0, 33.5, 35.5, 36.0, 36.5, 37.0, 37.5, 38.0, 38.5, 39.0, 39.5]
    window = detector.activity_window(timestamps, 44.725544)

    assert_equal 29.5, window.start_time
    assert_equal 40.5, window.end_time
  end

  def test_activity_window_falls_back_when_lift_is_near_tail
    config = TrainingVideoPipeline::Config.load(File.expand_path("../config/config.yml", __dir__))
    detector = TrainingVideoPipeline::MotionDetector.new(
      ffmpeg: nil,
      config: config,
      logger: Logger.new(File::NULL)
    )

    window = detector.activity_window([10.5, 11.0, 13.5, 51.5, 52.0, 52.5, 53.0, 53.5], 58.9)

    assert_equal 48.5, window.start_time
    assert_equal 54.5, window.end_time
  end

  def test_detect_uses_presence_fallback_for_short_motion_window
    config = TrainingVideoPipeline::Config.load(File.expand_path("../config/config.yml", __dir__))
    ffmpeg = FakeFFmpeg.new(
      duration_value: 58.9,
      motion_scores: [[51.5, 10.0], [52.0, 12.0], [52.5, 11.0]],
      anchor_scores: [[10.5, 4.0], [11.0, 5.0], [13.0, 4.0], [13.5, 4.5]],
      presence_scores: (13..50).map { |second| [second.to_f, 20.0] }
    )
    detector = TrainingVideoPipeline::MotionDetector.new(
      ffmpeg: ffmpeg,
      config: config,
      logger: Logger.new(File::NULL)
    )

    window = detector.detect("bench.mp4")

    assert_equal 10.0, window.start_time
    assert_equal 51.0, window.end_time
  end

  def test_detect_uses_presence_fallback_for_late_motion_window
    config = TrainingVideoPipeline::Config.load(File.expand_path("../config/config.yml", __dir__))
    ffmpeg = FakeFFmpeg.new(
      duration_value: 63.0,
      motion_scores: [[50.5, 6.1], [51.0, 6.6], [54.0, 8.8], [55.0, 6.6], [56.0, 7.7]],
      anchor_scores: [[22.0, 4.0], [22.5, 4.5], [23.0, 4.2], [53.0, 4.0]],
      presence_scores: (22..56).map { |second| [second.to_f, 20.0] }
    )
    detector = TrainingVideoPipeline::MotionDetector.new(
      ffmpeg: ffmpeg,
      config: config,
      logger: Logger.new(File::NULL)
    )

    window = detector.detect("squat.mp4")

    assert_equal 19.0, window.start_time
    assert_equal 54.0, window.end_time
  end
end
