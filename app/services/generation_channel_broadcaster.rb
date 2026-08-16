module GenerationChannelBroadcaster
  module_function

  def broadcast(column_or_payload)
    payload = column_or_payload.is_a?(Hash) ? column_or_payload : build_payload(column_or_payload)
    ActionCable.server.broadcast("GenerationChannel", payload)
  rescue => e
    Rails.logger.warn("[GenerationChannel] broadcast skipped: #{e.class} - #{e.message}")
  end

  def build_payload(column)
    {
      column_id: column.id,
      status: column.generation_status,
      title: column.title,
      generated_body: column.generated_body?,
      published: column.published?,
      path: "/columns/#{column.code.presence || column.id}",
      file_url: column[:file].present? ? column.file.to_s : nil
    }
  end
end
