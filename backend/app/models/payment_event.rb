class PaymentEvent < ApplicationRecord
  belongs_to :account
  belongs_to :invoice, optional: true
  has_one :ledger_entry
  has_many :payment_suggestions, dependent: :destroy

  validates :provider, :external_event_id, :event_type, presence: true
end
