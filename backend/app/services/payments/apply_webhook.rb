module Payments
  class ApplyWebhook
    SUPPORTED_TYPES = %w[payment.succeeded payment.failed].freeze

    def call(payload)
      payload = payload.deep_stringify_keys
      event_type = payload.fetch("type")
      raise ArgumentError, "unsupported event" unless SUPPORTED_TYPES.include?(event_type)

      invoice = Invoice.find(payload.fetch("data").fetch("invoice_id"))
      external_event_id = payload.fetch("id")
      provider = payload.fetch("provider")

      # Redelivery of an already processed event: acknowledge without applying cash again.
      existing = PaymentEvent.find_by(provider: provider, external_event_id: external_event_id)
      return result_for(existing) if existing

      event = nil
      ActiveRecord::Base.transaction do
        event = PaymentEvent.create!(
          account_id: invoice.account_id,
          invoice: invoice,
          provider: provider,
          external_event_id: external_event_id,
          event_type: event_type,
          payload: payload,
          processed_at: Time.current
        )

        if event_type == "payment.succeeded"
          LedgerEntry.create!(
            account_id: invoice.account_id,
            invoice: invoice,
            payment_event: event,
            amount_cents: invoice.amount_cents,
            entry_type: "payment_applied",
            external_event_id: external_event_id
          )
          invoice.update!(status: "processed", processed_at: invoice.processed_at || Time.current)
        else
          invoice.update!(status: "failed")
        end
      end

      result_for(event)
    rescue ActiveRecord::RecordNotUnique
      # A concurrent delivery of the same event committed first; the unique index rejected ours.
      result_for(PaymentEvent.find_by!(provider: provider, external_event_id: external_event_id))
    end

    private

    def result_for(event)
      {
        invoice_id: event.invoice_id,
        status: event.invoice.reload.status,
        ledger_entry_id: event.ledger_entry&.id,
        external_event_id: event.external_event_id
      }
    end
  end
end
