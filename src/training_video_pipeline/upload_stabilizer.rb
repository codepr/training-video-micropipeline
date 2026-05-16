module TrainingVideoPipeline
  class UploadStabilizer
    def initialize(poll_interval:, stabilization_seconds:, logger:)
      @poll_interval = poll_interval.to_f
      @stabilization_seconds = stabilization_seconds.to_f
      @logger = logger
    end

    def wait_until_stable(path)
      stable_for = 0.0
      previous_size = nil

      loop do
        raise Errno::ENOENT, path unless File.exist?(path)

        current_size = File.size(path)
        if current_size == previous_size
          stable_for += @poll_interval
        else
          stable_for = 0.0
          previous_size = current_size
        end

        @logger.info("upload.stabilizing path=#{path} size=#{current_size} stable_for=#{stable_for}")
        return true if stable_for >= @stabilization_seconds

        sleep @poll_interval
      end
    end
  end
end
