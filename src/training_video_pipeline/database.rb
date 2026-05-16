module TrainingVideoPipeline
  class Database
    def initialize(path)
      @db = SQLite3::Database.new(path)
      @db.results_as_hash = true
      migrate!
    end

    def create_video(original_filename:, original_path:, status:)
      now = Time.now.utc.iso8601
      @db.execute(
        <<~SQL,
          INSERT INTO videos (
            original_filename,
            original_path,
            created_at,
            processing_status
          ) VALUES (?, ?, ?, ?)
        SQL
        [original_filename, original_path, now, status]
      )
      @db.last_insert_row_id
    end

    def mark_processed(id:, processed_filename:, processed_path:, duration_original:, duration_processed:, activity_start:, activity_end:)
      @db.execute(
        <<~SQL,
          UPDATE videos
          SET processed_filename = ?,
              processed_path = ?,
              processed_at = ?,
              duration_original = ?,
              duration_processed = ?,
              activity_start = ?,
              activity_end = ?,
              processing_status = ?,
              error_message = NULL
          WHERE id = ?
        SQL
        [
          processed_filename,
          processed_path,
          Time.now.utc.iso8601,
          duration_original,
          duration_processed,
          activity_start,
          activity_end,
          "processed",
          id
        ]
      )
    end

    def mark_failed(id:, error_message:)
      @db.execute(
        "UPDATE videos SET processed_at = ?, processing_status = ?, error_message = ? WHERE id = ?",
        [Time.now.utc.iso8601, "failed", error_message, id]
      )
    end

    private

    def migrate!
      @db.execute <<~SQL
        CREATE TABLE IF NOT EXISTS videos (
          id INTEGER PRIMARY KEY,
          original_filename TEXT,
          processed_filename TEXT,
          original_path TEXT,
          processed_path TEXT,
          created_at DATETIME,
          processed_at DATETIME,
          duration_original REAL,
          duration_processed REAL,
          activity_start REAL,
          activity_end REAL,
          processing_status TEXT,
          error_message TEXT
        );
      SQL
    end
  end
end
