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

    unless valid_extraction?(payload)
      document.update!(status: "failed")
      return
    end

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
  rescue Ai::InvalidResponseError, Ai::ConfigurationError
    document.update!(status: "failed")
  end

  def already_processed?(document)
    document.status == "processed"
  end

  private

  def claim(document)
    Document.where(id: document.id, status: %w[pending failed])
            .update_all(status: "processing", updated_at: Time.current) == 1
  end

  def valid_extraction?(payload)
    return false unless payload.is_a?(Hash)
    required_fields = ["invoice_number", "amount_cents", "currency", "vendor_name"]
    required_fields.all? { |field| payload.key?(field) && !payload[field].nil? }
  end
end
