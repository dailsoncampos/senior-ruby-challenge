require "rails_helper"

RSpec.describe DocumentProcessingJob do
  it "stores deterministic extraction data from the mock provider" do
    document = create(:document, filename: "invoice-42.pdf", status: "pending")

    described_class.new.perform(document.id)

    document.reload
    expect(document.status).to eq("processed")
    expect(document.extracted_data).to include(
      "invoice_number" => "INV-42",
      "amount_cents" => 25_000,
      "currency" => "USD",
      "vendor_name" => "FlowOps Demo Vendor"
    )
    expect(document.extraction_runs.count).to eq(1)
  end

  it "fails the document when retries are exhausted" do
    document = create(:document, filename: "scenario-timeout.pdf", status: "pending")

    described_class.sidekiq_retries_exhausted_block.call(
      { "args" => [document.id] }, Ai::ProviderTimeoutError.new("timeout")
    )

    expect(document.reload.status).to eq("failed")
  end
end
