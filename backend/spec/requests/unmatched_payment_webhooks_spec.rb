require "rails_helper"

RSpec.describe "unmatched payment webhooks", type: :request do
  let(:account) { create(:account) }
  let(:customer) { create(:customer, account: account, name: "Acme Traffic Ltda") }
  let(:invoice) { create(:invoice, account: account, customer: customer, invoice_number: "42", amount_cents: 64_000, status: "pending") }

  before do
    invoice # ensure invoice exists
  end

  it "receives an unmatched payment and creates a suggestion when reference matches" do
    post "/api/webhooks/payments",
         params: {
           id: "evt-9001",
           type: "payment.received",
           provider: "northstar_pay",
           data: {
             account_id: account.id,
             amount_cents: 64_000,
             payer_name: "Acme Traffic Ltda",
             reference: "pgto nf 42 outubro"
           }
         },
         headers: webhook_headers,
         as: :json

    expect(response).to have_http_status(:ok)

    result = JSON.parse(response.body)
    expect(result["external_event_id"]).to eq("evt-9001")
    expect(result["amount_cents"]).to eq(64_000)
    expect(result["payer_name"]).to eq("Acme Traffic Ltda")
    expect(result["reference"]).to eq("pgto nf 42 outubro")
    expect(result["suggestion"]).to be_present
    expect(result["suggestion"]["invoice_id"]).to eq(invoice.id)
    expect(result["suggestion"]["invoice_number"]).to eq("42")
    expect(result["suggestion"]["status"]).to eq("pending")

    event = PaymentEvent.find_by(external_event_id: "evt-9001")
    expect(event).to be_present
    expect(event.event_type).to eq("payment.received")
    expect(event.invoice_id).to be_nil
    expect(event.amount_cents).to eq(64_000)
    expect(event.payer_name).to eq("Acme Traffic Ltda")
    expect(event.reference).to eq("pgto nf 42 outubro")

    suggestion = PaymentSuggestion.find_by(payment_event: event)
    expect(suggestion).to be_present
    expect(suggestion.invoice).to eq(invoice)
    expect(suggestion.status).to eq("pending")
    expect(suggestion.matched_by).to eq("reference_and_amount")
  end

  it "receives an unmatched payment without suggestion when no invoice matches" do
    post "/api/webhooks/payments",
         params: {
           id: "evt-9002",
           type: "payment.received",
           provider: "northstar_pay",
           data: {
             account_id: account.id,
             amount_cents: 50_000,
             payer_name: "Unknown Company",
             reference: "random payment"
           }
         },
         headers: webhook_headers,
         as: :json

    expect(response).to have_http_status(:ok)

    result = JSON.parse(response.body)
    expect(result["suggestion"]).to be_nil

    event = PaymentEvent.find_by(external_event_id: "evt-9002")
    expect(event).to be_present
    expect(event.payment_suggestions).to be_empty
  end

  it "handles redelivery of the same unmatched payment event" do
    # First delivery
    post "/api/webhooks/payments",
         params: {
           id: "evt-9003",
           type: "payment.received",
           provider: "northstar_pay",
           data: {
             account_id: account.id,
             amount_cents: 64_000,
             payer_name: "Acme Traffic Ltda",
             reference: "pgto nf 42 outubro"
           }
         },
         headers: webhook_headers,
         as: :json

    expect(response).to have_http_status(:ok)
    first_result = JSON.parse(response.body)

    # Second delivery (redelivery)
    post "/api/webhooks/payments",
         params: {
           id: "evt-9003",
           type: "payment.received",
           provider: "northstar_pay",
           data: {
             account_id: account.id,
             amount_cents: 64_000,
             payer_name: "Acme Traffic Ltda",
             reference: "pgto nf 42 outubro"
           }
         },
         headers: webhook_headers,
         as: :json

    expect(response).to have_http_status(:ok)
    second_result = JSON.parse(response.body)

    # Should return the same event
    expect(second_result["payment_event_id"]).to eq(first_result["payment_event_id"])
    expect(PaymentEvent.where(external_event_id: "evt-9003").count).to eq(1)
  end

  it "does not match invoices from different accounts" do
    other_account = create(:account)
    other_customer = create(:customer, account: other_account)
    other_invoice = create(:invoice, account: other_account, customer: other_customer, invoice_number: "42", amount_cents: 64_000, status: "pending")

    post "/api/webhooks/payments",
         params: {
           id: "evt-9004",
           type: "payment.received",
           provider: "northstar_pay",
           data: {
             account_id: account.id,
             amount_cents: 64_000,
             payer_name: "Acme Traffic Ltda",
             reference: "pgto nf 42"
           }
         },
         headers: webhook_headers,
         as: :json

    expect(response).to have_http_status(:ok)

    result = JSON.parse(response.body)
    # Should match the invoice from the same account, not the other account
    if invoice.present?
      expect(result["suggestion"]).to be_present
      expect(result["suggestion"]["invoice_id"]).to eq(invoice.id)
    else
      expect(result["suggestion"]).to be_nil
    end
  end

  it "does not match already processed invoices" do
    invoice.update!(status: "processed")

    post "/api/webhooks/payments",
         params: {
           id: "evt-9005",
           type: "payment.received",
           provider: "northstar_pay",
           data: {
             account_id: account.id,
             amount_cents: 64_000,
             payer_name: "Acme Traffic Ltda",
             reference: "pgto nf 42"
           }
         },
         headers: webhook_headers,
         as: :json

    expect(response).to have_http_status(:ok)

    result = JSON.parse(response.body)
    expect(result["suggestion"]).to be_nil
  end
end
