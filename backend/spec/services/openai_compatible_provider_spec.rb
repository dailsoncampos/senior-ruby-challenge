require "rails_helper"

RSpec.describe Ai::OpenaiCompatibleProvider do
  subject(:provider) { described_class.new(api_key: "test-key") }

  it "maps network timeouts to a retryable error" do
    allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Net::ReadTimeout)

    expect { provider.extract_invoice(filename: "a.pdf") }.to raise_error(Ai::ProviderTimeoutError)
  end

  it "maps connection failures to a retryable error" do
    allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Errno::ECONNREFUSED)

    expect { provider.extract_invoice(filename: "a.pdf") }.to raise_error(Ai::UnavailableError)
  end

  it "rejects a successful response without message content" do
    response = instance_double(Net::HTTPResponse, code: "200", body: '{"choices":[]}')
    allow_any_instance_of(Net::HTTP).to receive(:request).and_return(response)

    expect { provider.extract_invoice(filename: "a.pdf") }.to raise_error(Ai::InvalidResponseError)
  end
end
