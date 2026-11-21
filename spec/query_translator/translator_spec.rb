# frozen_string_literal: true

RSpec.describe QueryTranslator::Translator do
  subject(:result) { described_class.call(query:, resources: [venues_resource, bookings_resource]) }

  let(:chat) { RubyLLM.chat(model: described_class::DEFAULT_MODEL) }
  let(:query) { "a hall in Chicago" }

  before { allow(RubyLLM).to receive(:chat).and_return(chat) }

  context "when the query is blank" do
    let(:query) { "   " }

    it "returns an empty result without asking the model" do
      expect(result).to have_attributes(resource: nil, filters: {}, low_confidence?: true)
      expect(RubyLLM).not_to have_received(:chat)
    end
  end

  context "when the query is too long" do
    let(:query) { "hall " * 200 }

    it "sends only the first 500 characters" do
      allow(chat).to receive(:ask).and_return(model_answer)

      result
      expect(chat).to have_received(:ask).with(a_string_matching(/\A.{500}\z/m))
    end
  end

  context "when the model gives no answer" do
    it "raises the gem's own error" do
      allow(chat).to receive(:ask).and_return(RubyLLM::Message.new(role: :assistant, content: ""))

      expect { result }.to raise_error(QueryTranslator::Error, /no answer/)
    end
  end

  context "when the model cannot be reached" do
    it "raises the gem's own error" do
      allow(chat).to receive(:ask).and_raise(RubyLLM::ConnectionError, "timeout")

      expect { result }.to raise_error(QueryTranslator::Error, /timeout/)
    end
  end

  def model_answer
    content = { resource: "venues", filters: [], confidence: 0.9, unmapped: [], question: "", options: [] }
    RubyLLM::Message.new(role: :assistant, content: content.to_json)
  end
end
