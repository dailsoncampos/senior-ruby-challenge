class DocumentProcessingJob
  include Sidekiq::Job

  sidekiq_options retry: 5, queue: "default"

  sidekiq_retries_exhausted do |job, error|
    Document.where(id: job["args"].first, status: %w[pending processing])
            .update_all(status: "failed", updated_at: Time.current)
    Sidekiq.logger.warn("[DocumentProcessingJob] retries exhausted document=#{job["args"].first}: #{error.class}")
  end

  def perform(document_id)
    document = Document.find(document_id)
    return if already_processed?(document)
    return unless claim(document)

    document.reload
    payload = Ai::InvoiceExtractionService.new.extract(filename: document.filename)

    ActiveRecord::Base.transaction do
      ExtractionRun.create!(
        account_id: document.account_id,
        document: document,
        outcome: "completed",
        provider_name: Ai::ProviderRegistry.current_name,
        result: payload
      )
      document.update!(status: "processed", extracted_data: payload)
    end
  rescue Ai::RetryableError
    document.update!(status: "pending")
    raise
  rescue Ai::Error => error
    document.update!(status: "failed")
    Rails.logger.warn("[DocumentProcessingJob] document=#{document.id} failed: #{error.class}: #{error.message}")
  end

  def already_processed?(document)
    document.status == "processed"
  end

  private

  def claim(document)
    Document.where(id: document.id, status: %w[pending failed])
            .update_all(status: "processing", updated_at: Time.current) == 1
  end
end
