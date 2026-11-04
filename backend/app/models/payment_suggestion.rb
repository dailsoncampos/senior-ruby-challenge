class PaymentSuggestion < ApplicationRecord
  STATUSES = %w[pending confirmed rejected].freeze

  belongs_to :account
  belongs_to :payment_event
  belongs_to :invoice

  validates :status, inclusion: { in: STATUSES }
  validates :matched_by, presence: true
  validate :invoice_belongs_to_account
  validate :payment_event_belongs_to_account

  private

  def invoice_belongs_to_account
    return if invoice.nil? || account_id.nil?
    return if invoice.account_id == account_id

    errors.add(:invoice, "must belong to the same account")
  end

  def payment_event_belongs_to_account
    return if payment_event.nil? || account_id.nil?
    return if payment_event.account_id == account_id

    errors.add(:payment_event, "must belong to the same account")
  end
end
