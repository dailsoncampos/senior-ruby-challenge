require "rails_helper"

RSpec.describe "payment suggestions", type: :request do
  let(:account) { create(:account) }
  let(:customer) { create(:customer, account: account) }
  let(:invoice) { create(:invoice, account: account, customer: customer, amount_cents: 64_000, status: "pending") }
  let(:payment_event) do
    PaymentEvent.create!(
      account: account,
      provider: "northstar_pay",
      external_event_id: "evt-test-1",
      event_type: "payment.received",
      payload: {},
      payer_name: "Test Payer",
      reference: "test payment",
      amount_cents: 64_000,
      processed_at: Time.current
    )
  end
  let(:suggestion) do
    PaymentSuggestion.create!(
      account: account,
      payment_event: payment_event,
      invoice: invoice,
      status: "pending",
      matched_by: "reference_and_amount"
    )
  end

  describe "POST /api/payment_suggestions/:id/confirm" do
    it "confirms a pending suggestion and applies payment to the invoice" do
      post "/api/payment_suggestions/#{suggestion.id}/confirm",
           headers: auth_headers(account),
           as: :json

      expect(response).to have_http_status(:ok)

      result = JSON.parse(response.body)
      expect(result["status"]).to eq("confirmed")
      expect(result["invoice_id"]).to eq(invoice.id)
      expect(result["payment_event_id"]).to eq(payment_event.id)
      expect(result["confirmed_at"]).to be_present

      suggestion.reload
      expect(suggestion.status).to eq("confirmed")
      expect(suggestion.confirmed_at).to be_present

      invoice.reload
      expect(invoice.status).to eq("processed")
      expect(invoice.processed_at).to be_present

      ledger_entry = LedgerEntry.find_by(payment_event: payment_event)
      expect(ledger_entry).to be_present
      expect(ledger_entry.invoice).to eq(invoice)
      expect(ledger_entry.amount_cents).to eq(64_000)
      expect(ledger_entry.entry_type).to eq("payment_applied")
    end

    it "prevents confirming an already confirmed suggestion" do
      suggestion.update!(status: "confirmed", confirmed_at: Time.current)

      post "/api/payment_suggestions/#{suggestion.id}/confirm",
           headers: auth_headers(account),
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)

      result = JSON.parse(response.body)
      expect(result["error"]).to eq("suggestion already confirmed")
    end

    it "prevents confirming a rejected suggestion" do
      suggestion.update!(status: "rejected", confirmed_at: Time.current)

      post "/api/payment_suggestions/#{suggestion.id}/confirm",
           headers: auth_headers(account),
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)

      result = JSON.parse(response.body)
      expect(result["error"]).to eq("suggestion already rejected")
    end

    it "prevents confirming if payment was already applied" do
      # Manually create a ledger entry as if payment was already applied
      LedgerEntry.create!(
        account: account,
        invoice: invoice,
        payment_event: payment_event,
        amount_cents: 64_000,
        entry_type: "payment_applied",
        external_event_id: payment_event.external_event_id
      )

      post "/api/payment_suggestions/#{suggestion.id}/confirm",
           headers: auth_headers(account),
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)

      result = JSON.parse(response.body)
      expect(result["error"]).to eq("payment already applied")

      suggestion.reload
      expect(suggestion.status).to eq("pending")
    end

    it "scopes suggestions to the current account" do
      other_account = create(:account)

      post "/api/payment_suggestions/#{suggestion.id}/confirm",
           headers: auth_headers(other_account),
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/payment_suggestions/:id/reject" do
    it "rejects a pending suggestion without applying payment" do
      post "/api/payment_suggestions/#{suggestion.id}/reject",
           headers: auth_headers(account),
           as: :json

      expect(response).to have_http_status(:ok)

      result = JSON.parse(response.body)
      expect(result["status"]).to eq("rejected")
      expect(result["invoice_id"]).to eq(invoice.id)
      expect(result["confirmed_at"]).to be_present

      suggestion.reload
      expect(suggestion.status).to eq("rejected")

      invoice.reload
      expect(invoice.status).to eq("pending")

      expect(LedgerEntry.where(payment_event: payment_event)).to be_empty
    end

    it "prevents rejecting an already confirmed suggestion" do
      suggestion.update!(status: "confirmed", confirmed_at: Time.current)

      post "/api/payment_suggestions/#{suggestion.id}/reject",
           headers: auth_headers(account),
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)

      result = JSON.parse(response.body)
      expect(result["error"]).to eq("suggestion already confirmed")
    end

    it "prevents rejecting an already rejected suggestion" do
      suggestion.update!(status: "rejected", confirmed_at: Time.current)

      post "/api/payment_suggestions/#{suggestion.id}/reject",
           headers: auth_headers(account),
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)

      result = JSON.parse(response.body)
      expect(result["error"]).to eq("suggestion already rejected")
    end

    it "scopes suggestions to the current account" do
      other_account = create(:account)

      post "/api/payment_suggestions/#{suggestion.id}/reject",
           headers: auth_headers(other_account),
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
