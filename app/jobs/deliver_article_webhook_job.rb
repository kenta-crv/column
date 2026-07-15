class DeliverArticleWebhookJob < ApplicationJob
  queue_as :webhooks

  RETRY_COUNT = 3
  TIMEOUT_SECONDS = 8

  # event: "created" | "updated" | "deleted"
  def perform(client_id, event, article_payload)
    client = Client.find_by(id: client_id)
    return if client.nil?

    webhook_url = client.webhook_url.to_s.strip
    return if webhook_url.blank?

    send_with_retry(webhook_url, event, article_payload)
  end

  private

  def send_with_retry(webhook_url, event, article_payload)
    attempts = 0

    begin
      attempts += 1
      response = HTTParty.post(
        webhook_url,
        body: { event: event, article: article_payload }.to_json,
        headers: { "Content-Type" => "application/json" },
        timeout: TIMEOUT_SECONDS
      )

      unless response.success?
        Rails.logger.warn("[Webhook] Non-success response from #{webhook_url}: #{response.code}")
      end
    rescue StandardError => e
      Rails.logger.error("[Webhook] Delivery failed (attempt #{attempts}/#{RETRY_COUNT}) to #{webhook_url}: #{e.message}")
      retry if attempts < RETRY_COUNT
    end
  end
end
