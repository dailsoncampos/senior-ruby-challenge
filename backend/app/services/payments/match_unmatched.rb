module Payments
  class MatchUnmatched
    # Patterns to extract invoice numbers from payment references
    # Examples: "pgto nf 42", "invoice 42", "fatura #42", "inv-42"
    INVOICE_NUMBER_PATTERNS = [
      /\b(?:nf|invoice|fatura|inv)[\s\-#]*(\w+)/i,
      /#(\w+)/,
      /\b(\d+)\b/
    ].freeze

    def call(payment_event)
      return nil unless payment_event.reference.present?
      return nil unless payment_event.amount_cents.present?

      invoice_numbers = extract_invoice_numbers(payment_event.reference)
      return nil if invoice_numbers.empty?

      find_matching_invoice(
        payment_event.account_id,
        invoice_numbers,
        payment_event.amount_cents
      )
    end

    private

    def extract_invoice_numbers(reference)
      numbers = []

      INVOICE_NUMBER_PATTERNS.each do |pattern|
        matches = reference.scan(pattern)
        matches.flatten.each do |match|
          numbers << match.strip
        end
      end

      numbers.uniq
    end

    def find_matching_invoice(account_id, invoice_numbers, amount_cents)
      Invoice
        .where(account_id: account_id)
        .where(invoice_number: invoice_numbers)
        .where(amount_cents: amount_cents)
        .where(status: 'pending')
        .first
    end
  end
end
