module Api
  class PaymentSuggestionsController < BaseController
    def confirm
      suggestion = current_account.payment_suggestions.find(params[:id])

      if suggestion.status != "pending"
        render json: { error: "suggestion already #{suggestion.status}" }, status: :unprocessable_entity
        return
      end

      result = nil
      ActiveRecord::Base.transaction do
        # Check if payment was already applied
        if suggestion.payment_event.ledger_entry.present?
          render json: { error: "payment already applied" }, status: :unprocessable_entity
          raise ActiveRecord::Rollback
        end

        # Apply payment to the invoice
        LedgerEntry.create!(
          account_id: suggestion.account_id,
          invoice: suggestion.invoice,
          payment_event: suggestion.payment_event,
          amount_cents: suggestion.payment_event.amount_cents,
          entry_type: "payment_applied",
          external_event_id: suggestion.payment_event.external_event_id
        )

        suggestion.invoice.update!(
          status: "processed",
          processed_at: suggestion.invoice.processed_at || Time.current
        )

        suggestion.update!(
          status: "confirmed",
          confirmed_at: Time.current,
          confirmed_by: "api_user"
        )

        result = {
          id: suggestion.id,
          status: suggestion.status,
          invoice_id: suggestion.invoice_id,
          payment_event_id: suggestion.payment_event_id,
          confirmed_at: suggestion.confirmed_at
        }
      end

      render json: result if result
    rescue ActiveRecord::RecordNotUnique
      render json: { error: "payment already applied" }, status: :unprocessable_entity
    end

    def reject
      suggestion = current_account.payment_suggestions.find(params[:id])

      if suggestion.status != "pending"
        render json: { error: "suggestion already #{suggestion.status}" }, status: :unprocessable_entity
        return
      end

      suggestion.update!(
        status: "rejected",
        confirmed_at: Time.current,
        confirmed_by: "api_user"
      )

      render json: {
        id: suggestion.id,
        status: suggestion.status,
        invoice_id: suggestion.invoice_id,
        payment_event_id: suggestion.payment_event_id,
        confirmed_at: suggestion.confirmed_at
      }
    end
  end
end
