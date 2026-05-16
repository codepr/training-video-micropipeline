module TrainingVideoPipeline
  class Processor
    def initialize(config:, database:, ffmpeg:, motion_detector:, logger:)
      @config = config
      @database = database
      @ffmpeg = ffmpeg
      @motion_detector = motion_detector
      @logger = logger
    end

    def process(path)
      started_at = Time.now
      original_filename = File.basename(path)
      id = @database.create_video(
        original_filename: original_filename,
        original_path: path,
        status: "processing"
      )

      processing_path = move_to_processing(path)
      begin
        duration_original = @ffmpeg.duration(processing_path)
        window = @motion_detector.detect(processing_path)
        output_path = output_path_for(processing_path)

        @logger.info(
          "trim.window path=#{processing_path} start=#{window.start_time} end=#{window.end_time}"
        )
        @ffmpeg.trim_and_compress(
          input: processing_path,
          output: output_path,
          start_time: window.start_time,
          end_time: window.end_time,
          compression: @config.fetch("compression")
        )

        duration_processed = @ffmpeg.duration(output_path)
        archive_raw(processing_path)
        @database.mark_processed(
          id: id,
          processed_filename: File.basename(output_path),
          processed_path: output_path,
          duration_original: duration_original,
          duration_processed: duration_processed,
          activity_start: window.start_time,
          activity_end: window.end_time
        )
        @logger.info("processing.complete path=#{path} seconds=#{Time.now - started_at}")
        output_path
      rescue StandardError => error
        @logger.error("processing.failed path=#{path} error=#{error.class}: #{error.message}")
        move_to_failed(processing_path) if processing_path && File.exist?(processing_path)
        @database.mark_failed(id: id, error_message: "#{error.class}: #{error.message}")
        nil
      end
    end

    private

    def move_to_processing(path)
      destination = unique_path(@config.path("processing_dir"), File.basename(path))
      FileUtils.mv(path, destination)
      destination
    end

    def archive_raw(path)
      destination = unique_path(@config.path("raw_archive_dir"), File.basename(path))
      FileUtils.mv(path, destination)
      destination
    end

    def move_to_failed(path)
      destination = unique_path(@config.path("failed_dir"), File.basename(path))
      FileUtils.mv(path, destination)
      destination
    end

    def output_path_for(path)
      timestamp = File.mtime(path).strftime("%Y-%m-%d_%H%M%S")
      unique_path(@config.path("processed_dir"), "#{timestamp}_trimmed.mp4")
    end

    def unique_path(directory, filename)
      candidate = File.join(directory, filename)
      return candidate unless File.exist?(candidate)

      basename = File.basename(filename, ".*")
      extension = File.extname(filename)
      File.join(directory, "#{basename}_#{SecureRandom.hex(4)}#{extension}")
    end
  end
end
