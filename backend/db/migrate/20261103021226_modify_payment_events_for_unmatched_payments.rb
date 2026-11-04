class ModifyPaymentEventsForUnmatchedPayments < ActiveRecord::Migration[7.2]
  def change
    # Make invoice_id nullable to support unmatched payments
    change_column_null :payment_events, :invoice_id, true

    # Add fields for unmatched payments
    add_column :payment_events, :payer_name, :string
    add_column :payment_events, :reference, :text
    add_column :payment_events, :amount_cents, :integer
  end
end
