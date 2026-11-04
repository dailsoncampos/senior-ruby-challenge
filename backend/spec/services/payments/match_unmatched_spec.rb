require "rails_helper"

RSpec.describe Payments::MatchUnmatched do
  let(:account) { create(:account) }
  let(:customer) { create(:customer, account: account) }
  let(:service) { described_class.new }

  describe "#call" do
    it "matches an invoice by invoice number and amount" do
      invoice = create(:invoice, account: account, customer: customer, invoice_number: "42", amount_cents: 64_000, status: "pending")

      payment_event = PaymentEvent.create!(
        account: account,
        provider: "northstar_pay",
        external_event_id: "evt-test",
        event_type: "payment.received",
        payload: {},
        payer_name: "Test Payer",
        reference: "pgto nf 42 outubro",
        amount_cents: 64_000
      )

      result = service.call(payment_event)

      expect(result).to eq(invoice)
    end

    it "extracts invoice number from various reference formats" do
      invoice = create(:invoice, account: account, customer: customer, invoice_number: "123", amount_cents: 50_000, status: "pending")

      [
        "pgto nf 123",
        "invoice 123",
        "fatura #123",
        "inv-123",
        "payment for #123",
        "ref 123"
      ].each do |reference|
        payment_event = PaymentEvent.create!(
          account: account,
          provider: "northstar_pay",
          external_event_id: "evt-#{reference.gsub(/\s+/, '-')}",
          event_type: "payment.received",
          payload: {},
          payer_name: "Test Payer",
          reference: reference,
          amount_cents: 50_000
        )

        result = service.call(payment_event)
        expect(result).to eq(invoice), "Failed to match for reference: #{reference}"
      end
    end

    it "returns nil when reference is blank" do
      payment_event = PaymentEvent.create!(
        account: account,
        provider: "northstar_pay",
        external_event_id: "evt-blank",
        event_type: "payment.received",
        payload: {},
        payer_name: "Test Payer",
        reference: nil,
        amount_cents: 64_000
      )

      result = service.call(payment_event)

      expect(result).to be_nil
    end

    it "returns nil when amount_cents is blank" do
      payment_event = PaymentEvent.create!(
        account: account,
        provider: "northstar_pay",
        external_event_id: "evt-no-amount",
        event_type: "payment.received",
        payload: {},
        payer_name: "Test Payer",
        reference: "nf 42",
        amount_cents: nil
      )

      result = service.call(payment_event)

      expect(result).to be_nil
    end

    it "returns nil when no invoice matches the reference" do
      payment_event = PaymentEvent.create!(
        account: account,
        provider: "northstar_pay",
        external_event_id: "evt-no-match",
        event_type: "payment.received",
        payload: {},
        payer_name: "Test Payer",
        reference: "random text without invoice number",
        amount_cents: 64_000
      )

      result = service.call(payment_event)

      expect(result).to be_nil
    end

    it "returns nil when invoice number matches but amount doesn't" do
      invoice = create(:invoice, account: account, customer: customer, invoice_number: "42", amount_cents: 64_000, status: "pending")

      payment_event = PaymentEvent.create!(
        account: account,
        provider: "northstar_pay",
        external_event_id: "evt-wrong-amount",
        event_type: "payment.received",
        payload: {},
        payer_name: "Test Payer",
        reference: "nf 42",
        amount_cents: 50_000 # different amount
      )

      result = service.call(payment_event)

      expect(result).to be_nil
    end

    it "returns nil when invoice is already processed" do
      invoice = create(:invoice, account: account, customer: customer, invoice_number: "42", amount_cents: 64_000, status: "processed")

      payment_event = PaymentEvent.create!(
        account: account,
        provider: "northstar_pay",
        external_event_id: "evt-processed",
        event_type: "payment.received",
        payload: {},
        payer_name: "Test Payer",
        reference: "nf 42",
        amount_cents: 64_000
      )

      result = service.call(payment_event)

      expect(result).to be_nil
    end

    it "only matches invoices from the same account" do
      invoice = create(:invoice, account: account, customer: customer, invoice_number: "42", amount_cents: 64_000, status: "pending")

      other_account = create(:account)
      other_customer = create(:customer, account: other_account)
      other_invoice = create(:invoice, account: other_account, customer: other_customer, invoice_number: "42", amount_cents: 64_000, status: "pending")

      payment_event = PaymentEvent.create!(
        account: other_account,
        provider: "northstar_pay",
        external_event_id: "evt-other-account",
        event_type: "payment.received",
        payload: {},
        payer_name: "Test Payer",
        reference: "nf 42",
        amount_cents: 64_000
      )

      result = service.call(payment_event)

      expect(result).to eq(other_invoice)
      expect(result).not_to eq(invoice)
    end

    it "matches the invoice when reference contains the exact invoice number" do
      invoice1 = create(:invoice, account: account, customer: customer, invoice_number: "INV-1001", amount_cents: 64_000, status: "pending")
      invoice2 = create(:invoice, account: account, customer: customer, invoice_number: "42", amount_cents: 64_000, status: "pending")

      payment_event = PaymentEvent.create!(
        account: account,
        provider: "northstar_pay",
        external_event_id: "evt-exact-match",
        event_type: "payment.received",
        payload: {},
        payer_name: "Test Payer",
        reference: "nf 42",
        amount_cents: 64_000
      )

      result = service.call(payment_event)

      expect(result).to eq(invoice2)
    end
  end
end
