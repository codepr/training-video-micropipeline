require "fileutils"
require "logger"
require "open3"
require "securerandom"
require "shellwords"
require "sqlite3"
require "time"
require "yaml"

require_relative "training_video_pipeline/config"
require_relative "training_video_pipeline/database"
require_relative "training_video_pipeline/daemon"
require_relative "training_video_pipeline/ffmpeg"
require_relative "training_video_pipeline/motion_detector"
require_relative "training_video_pipeline/processor"
require_relative "training_video_pipeline/upload_stabilizer"

module TrainingVideoPipeline
  VERSION = "0.1.0"
end
