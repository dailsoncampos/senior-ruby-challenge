class DocumentProcessingJob
  include Sidekiq::Job

  sidekiq_options retry: 5, queue: "default"

  def perform(document_id)
    document = Document.find(document_id)
    return if already_processed?(document)

    document.update!(status: "processing")

    begin
      payload = Ai::InvoiceExtractionService.new.extract(filename: document.filename)

      unless valid_extraction?(payload)
        document.update!(status: "failed")
        return
      end

      ExtractionRun.create!(
        account_id: document.account_id,
        document: document,
        outcome: "completed",
        provider_name: Ai::ProviderRegistry.current_name,
        result: payload
      )

      document.update!(status: "processed", extracted_data: payload)
    rescue Ai::RetryableError
      document.update!(status: "pending")
      raise
    rescue Ai::InvalidResponseError, Ai::ConfigurationError
      document.update!(status: "failed")
    end
  end

  def already_processed?(document)
    document.status == "processed"
  end

  def valid_extraction?(payload)
    return false unless payload.is_a?(Hash)
    required_fields = ["invoice_number", "amount_cents", "currency", "vendor_name"]
    required_fields.all? { |field| payload.key?(field) && !payload[field].nil? }
  end
end
