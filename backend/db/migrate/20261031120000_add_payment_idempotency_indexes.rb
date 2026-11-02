class AddPaymentIdempotencyIndexes < ActiveRecord::Migration[7.2]
  def change
    remove_index :payment_events, %i[provider external_event_id]
    add_index :payment_events, %i[provider external_event_id], unique: true

    remove_index :ledger_entries, :payment_event_id
    add_index :ledger_entries, :payment_event_id, unique: true
  end
end
