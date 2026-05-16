module TrainingVideoPipeline
  class FFmpeg
    class Error < StandardError; end

    def initialize(logger:)
      @logger = logger
    end

    def duration(path)
      stdout = run_capture(
        "ffprobe",
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        path
      )
      stdout.to_f
    end

    def scene_timestamps(path, threshold:, sample_fps:)
      _stdout, stderr = run_capture_with_stderr(
        "ffmpeg",
        "-hide_banner",
        "-i", path,
        "-vf", "fps=#{sample_fps},select='gt(scene,#{threshold})',metadata=print",
        "-an",
        "-f", "null",
        "-"
      )

      stderr.scan(/pts_time:([0-9.]+)/).flatten.map(&:to_f).uniq.sort
    end

    def frame_difference_scores(path, sample_fps:, width:, height:)
      frame_size = width.to_i * height.to_i
      previous_frame = nil
      scores = []
      frame_index = 0

      cmd = [
        "ffmpeg",
        "-hide_banner",
        "-v", "error",
        "-i", path,
        "-vf", "fps=#{sample_fps},scale=#{width}:#{height},format=gray",
        "-f", "rawvideo",
        "-"
      ]

      @logger.info("ffmpeg.command=#{cmd.shelljoin}")
      Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thread|
        stdin.close
        while (frame = stdout.read(frame_size)) && frame.bytesize == frame_size
          bytes = frame.bytes
          if previous_frame
            scores << [
              frame_index.to_f / sample_fps.to_f,
              mean_absolute_difference(previous_frame, bytes)
            ]
          end
          previous_frame = bytes
          frame_index += 1
        end

        error_output = stderr.read
        unless wait_thread.value.success?
          raise Error, "command failed: #{cmd.shelljoin}\n#{error_output}"
        end
      end

      scores
    end

    def background_difference_scores(path, sample_fps:, width:, height:, reference_seconds:)
      frames = raw_gray_frames(path, sample_fps: sample_fps, width: width, height: height)
      return [] if frames.empty?

      reference_index = [
        frames.length - 1,
        [(reference_seconds.to_f * sample_fps.to_f).round, 0].max
      ].min
      reference_frame = frames.fetch(reference_index)

      frames.each_with_index.map do |frame, index|
        [
          index.to_f / sample_fps.to_f,
          mean_absolute_difference(reference_frame, frame)
        ]
      end
    end

    def trim_and_compress(input:, output:, start_time:, end_time:, compression:)
      run!(
        "ffmpeg",
        "-hide_banner",
        "-y",
        "-ss", format_seconds(start_time),
        "-to", format_seconds(end_time),
        "-i", input,
        "-map", "0:v:0",
        "-map", "0:a?",
        "-c:v", compression.fetch("video_codec"),
        "-crf", compression.fetch("crf").to_s,
        "-preset", compression.fetch("preset"),
        "-c:a", compression.fetch("audio_codec"),
        "-movflags", "+faststart",
        output
      )
    end

    private

    def run!(*cmd)
      @logger.info("ffmpeg.command=#{cmd.shelljoin}")
      stdout, stderr, status = Open3.capture3(*cmd)
      return true if status.success?

      raise Error, "command failed: #{cmd.shelljoin}\n#{stdout}\n#{stderr}"
    end

    def run_capture(*cmd)
      stdout, stderr, status = Open3.capture3(*cmd)
      return stdout if status.success?

      raise Error, "command failed: #{cmd.shelljoin}\n#{stdout}\n#{stderr}"
    end

    def run_capture_with_stderr(*cmd)
      stdout, stderr, status = Open3.capture3(*cmd)
      return [stdout, stderr] if status.success?

      raise Error, "command failed: #{cmd.shelljoin}\n#{stdout}\n#{stderr}"
    end

    def format_seconds(seconds)
      format("%.3f", seconds)
    end

    def mean_absolute_difference(left, right)
      sum = 0
      left.each_index { |index| sum += (left[index] - right[index]).abs }
      sum.to_f / left.length
    end

    def raw_gray_frames(path, sample_fps:, width:, height:)
      frame_size = width.to_i * height.to_i
      frames = []
      cmd = [
        "ffmpeg",
        "-hide_banner",
        "-v", "error",
        "-i", path,
        "-vf", "fps=#{sample_fps},scale=#{width}:#{height},format=gray",
        "-f", "rawvideo",
        "-"
      ]

      @logger.info("ffmpeg.command=#{cmd.shelljoin}")
      Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thread|
        stdin.close
        while (frame = stdout.read(frame_size)) && frame.bytesize == frame_size
          frames << frame.bytes
        end

        error_output = stderr.read
        unless wait_thread.value.success?
          raise Error, "command failed: #{cmd.shelljoin}\n#{error_output}"
        end
      end

      frames
    end
  end
end
