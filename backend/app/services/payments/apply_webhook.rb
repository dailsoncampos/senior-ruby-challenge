module Payments
  class ApplyWebhook
    SUPPORTED_TYPES = %w[payment.succeeded payment.failed payment.received].freeze

    def call(payload)
      payload = payload.deep_stringify_keys
      event_type = payload.fetch("type")
      raise ArgumentError, "unsupported event" unless SUPPORTED_TYPES.include?(event_type)

      external_event_id = payload.fetch("id")
      provider = payload.fetch("provider")
      data = payload.fetch("data")

      # payment.received events don't have invoice_id
      if event_type == "payment.received"
        return handle_unmatched_payment(payload, external_event_id, provider, data)
      end

      invoice = Invoice.find(data.fetch("invoice_id"))

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

    def handle_unmatched_payment(payload, external_event_id, provider, data)
      account_id = data.fetch("account_id")

      # Check for redelivery
      existing = PaymentEvent.find_by(provider: provider, external_event_id: external_event_id)
      return result_for_unmatched(existing) if existing

      event = nil
      suggestion = nil

      ActiveRecord::Base.transaction do
        event = PaymentEvent.create!(
          account_id: account_id,
          provider: provider,
          external_event_id: external_event_id,
          event_type: "payment.received",
          payload: payload,
          payer_name: data["payer_name"],
          reference: data["reference"],
          amount_cents: data.fetch("amount_cents"),
          processed_at: Time.current
        )

        # Try to match with an invoice
        matched_invoice = MatchUnmatched.new.call(event)

        if matched_invoice
          suggestion = PaymentSuggestion.create!(
            account_id: account_id,
            payment_event: event,
            invoice: matched_invoice,
            status: "pending",
            matched_by: "reference_and_amount"
          )
        end
      end

      result_for_unmatched(event, suggestion)
    rescue ActiveRecord::RecordNotUnique
      # Concurrent delivery of the same event
      existing = PaymentEvent.find_by!(provider: provider, external_event_id: external_event_id)
      result_for_unmatched(existing)
    end

    def result_for(event)
      {
        invoice_id: event.invoice_id,
        status: event.invoice.reload.status,
        ledger_entry_id: event.ledger_entry&.id,
        external_event_id: event.external_event_id
      }
    end

    def result_for_unmatched(event, suggestion = nil)
      suggestion ||= event.payment_suggestions.first

      {
        payment_event_id: event.id,
        external_event_id: event.external_event_id,
        amount_cents: event.amount_cents,
        payer_name: event.payer_name,
        reference: event.reference,
        suggestion: suggestion ? {
          id: suggestion.id,
          invoice_id: suggestion.invoice_id,
          invoice_number: suggestion.invoice.invoice_number,
          status: suggestion.status
        } : nil
      }
    end
  end
end
