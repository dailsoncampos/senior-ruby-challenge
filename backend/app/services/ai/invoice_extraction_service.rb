require "timeout"

module Ai
  class InvoiceExtractionService
    REQUIRED_KEYS = %w[invoice_number amount_cents currency vendor_name].freeze

    def initialize(provider: ProviderRegistry.resolve, timeout_seconds: ENV.fetch("AI_TIMEOUT_SECONDS", "2").to_f)
      @provider = provider
      @timeout_seconds = timeout_seconds
    end

    def extract(filename:)
      raw = Timeout.timeout(@timeout_seconds, ProviderTimeoutError) do
        @provider.extract_invoice(filename: filename)
      end

      validate!(stringify_keys(raw))
    end

    private

    def stringify_keys(raw)
      raise InvalidResponseError, "provider returned #{raw.class}" unless raw.is_a?(Hash)

      raw.transform_keys(&:to_s)
    end

    def validate!(payload)
      missing = REQUIRED_KEYS - payload.keys
      raise InvalidResponseError, "missing keys: #{missing.join(", ")}" if missing.any?

      unless payload["amount_cents"].is_a?(Integer) && payload["amount_cents"] >= 0
        raise InvalidResponseError, "invalid amount_cents"
      end

      payload.slice(*REQUIRED_KEYS)
    end
  end
end
