class CreatePaymentSuggestions < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_suggestions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :payment_event, null: false, foreign_key: true
      t.references :invoice, null: false, foreign_key: true
      t.string :status, null: false, default: 'pending'
      t.string :matched_by, null: false
      t.datetime :confirmed_at
      t.string :confirmed_by

      t.timestamps
    end

    add_index :payment_suggestions, [:account_id, :status]

    # Ensure one suggestion per payment-invoice pair
    add_index :payment_suggestions, [:payment_event_id, :invoice_id], unique: true

    add_check_constraint :payment_suggestions,
      "status IN ('pending', 'confirmed', 'rejected')",
      name: "payment_suggestions_status_allowed"
  end
end
