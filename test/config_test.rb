require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_loads_defaults_and_overrides_nested_values
    Dir.mktmpdir do |dir|
      config_path = File.join(dir, "config.yml")
      File.write(config_path, <<~YAML)
        upload:
          poll_interval_seconds: 1
        compression:
          crf: 24
      YAML

      config = TrainingVideoPipeline::Config.load(config_path)

      assert_equal 1, config.fetch("upload", "poll_interval_seconds")
      assert_equal 10, config.fetch("upload", "stabilization_seconds")
      assert_equal 24, config.fetch("compression", "crf")
      assert_equal "medium", config.fetch("compression", "preset")
    end
  end
end
