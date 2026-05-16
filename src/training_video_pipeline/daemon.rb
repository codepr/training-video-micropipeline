begin
  require "listen"
rescue LoadError
  # The dependency is loaded when running with Bundler. Keeping this soft lets
  # pure unit tests exercise the rest of the pipeline without installed gems.
end

module TrainingVideoPipeline
  class Daemon
    def initialize(config_path)
      @config = Config.load(config_path)
      @config.ensure_directories!
      @logger = Logger.new(@config.path("log_file"))
      @logger.level = Logger::INFO
      @database = Database.new(@config.path("database_path"))
      @ffmpeg = FFmpeg.new(logger: @logger)
      @motion_detector = MotionDetector.new(ffmpeg: @ffmpeg, config: @config, logger: @logger)
      @processor = Processor.new(
        config: @config,
        database: @database,
        ffmpeg: @ffmpeg,
        motion_detector: @motion_detector,
        logger: @logger
      )
      upload = @config.fetch("upload")
      @stabilizer = UploadStabilizer.new(
        poll_interval: upload.fetch("poll_interval_seconds"),
        stabilization_seconds: upload.fetch("stabilization_seconds"),
        logger: @logger
      )
      @queue = Queue.new
    end

    def run
      raise "listen gem is required to run the daemon" unless defined?(Listen)

      enqueue_existing_files
      listener = Listen.to(@config.path("incoming_dir")) do |modified, added, _removed|
        (modified + added).each { |path| enqueue(path) }
      end

      @logger.info("daemon.start incoming=#{@config.path("incoming_dir")}")
      listener.start
      consume_queue
    ensure
      listener&.stop
    end

    private

    def enqueue_existing_files
      Dir.children(@config.path("incoming_dir")).each do |entry|
        enqueue(File.join(@config.path("incoming_dir"), entry))
      end
    end

    def enqueue(path)
      return unless File.file?(path)
      return unless video_file?(path)

      @logger.info("file.detected path=#{path}")
      @queue << path
    end

    def consume_queue
      loop do
        path = @queue.pop
        next unless File.exist?(path)

        begin
          @stabilizer.wait_until_stable(path)
          @processor.process(path)
        rescue StandardError => error
          @logger.error("daemon.item_failed path=#{path} error=#{error.class}: #{error.message}")
        end
      end
    end

    def video_file?(path)
      extensions = @config["video_extensions"].map(&:downcase)
      extensions.include?(File.extname(path).downcase)
    end
  end
end
