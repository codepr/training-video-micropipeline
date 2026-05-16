require_relative "test_helper"

class FFmpegPipelineTest < Minitest::Test
  def test_processor_creates_trimmed_video_and_metadata
    skip "ffmpeg is not available" unless system("ffmpeg -version > /dev/null 2>&1")
    skip "ffprobe is not available" unless system("ffprobe -version > /dev/null 2>&1")

    Dir.mktmpdir do |dir|
      make_directories(dir)
      input = File.join(dir, "incoming", "synthetic_motion.mp4")
      create_synthetic_video(input)
      config_path = write_config(dir)

      config = TrainingVideoPipeline::Config.load(config_path)
      logger = Logger.new(File::NULL)
      database = TrainingVideoPipeline::Database.new(config.path("database_path"))
      ffmpeg = TrainingVideoPipeline::FFmpeg.new(logger: logger)
      detector = TrainingVideoPipeline::MotionDetector.new(
        ffmpeg: ffmpeg,
        config: config,
        logger: logger
      )
      processor = TrainingVideoPipeline::Processor.new(
        config: config,
        database: database,
        ffmpeg: ffmpeg,
        motion_detector: detector,
        logger: logger
      )

      output = processor.process(input)

      assert File.exist?(output), "expected processed video to exist"
      assert_operator ffmpeg.duration(output), :>, 0
      refute File.exist?(input), "expected original file to move out of incoming"
      assert_equal ["synthetic_motion.mp4"], Dir.children(File.join(dir, "archive", "raw"))
    end
  end

  private

  def make_directories(dir)
    %w[incoming processing processed failed logs db tmp].each do |name|
      FileUtils.mkdir_p(File.join(dir, name))
    end
    FileUtils.mkdir_p(File.join(dir, "archive", "raw"))
  end

  def write_config(dir)
    FileUtils.mkdir_p(File.join(dir, "config"))
    path = File.join(dir, "config", "config.yml")
    File.write(path, <<~YAML)
      incoming_dir: "./incoming"
      processing_dir: "./processing"
      processed_dir: "./processed"
      failed_dir: "./failed"
      raw_archive_dir: "./archive/raw"
      log_file: "./logs/pipeline.log"
      database_path: "./db/metadata.sqlite3"

      upload:
        stabilization_seconds: 0
        poll_interval_seconds: 0

      motion_detection:
        threshold: 0.02
        minimum_activity_duration: 0.1
        merge_gap_seconds: 3
        sample_fps: 2

      trimming:
        pre_buffer_seconds: 0.25
        post_buffer_seconds: 0.25

      compression:
        crf: 28
        preset: "medium"
        video_codec: "libx264"
        audio_codec: "aac"
    YAML
    path
  end

  def create_synthetic_video(output)
    command = [
      "ffmpeg",
      "-hide_banner",
      "-y",
      "-f", "lavfi", "-i", "color=c=black:s=160x120:r=15:d=1",
      "-f", "lavfi", "-i", "testsrc2=s=160x120:r=15:d=2",
      "-f", "lavfi", "-i", "color=c=black:s=160x120:r=15:d=1",
      "-filter_complex", "[0:v][1:v][2:v]concat=n=3:v=1:a=0[v]",
      "-map", "[v]",
      "-c:v", "libx264",
      "-pix_fmt", "yuv420p",
      output
    ]

    system(*command, out: File::NULL, err: File::NULL) || flunk("failed to create synthetic video")
  end
end
