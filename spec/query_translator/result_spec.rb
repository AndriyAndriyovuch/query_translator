# frozen_string_literal: true

RSpec.describe QueryTranslator::Result do
  subject(:result) do
    described_class.new(resource: venues_resource, filters: { "by_city_match" => "Chicago" }, confidence: 0.9,
                        unmapped: [], errors: [], question: "", options: [])
  end

  context "when the model is sure and everything mapped" do
    it "is confident, asks nothing and points to the resource path" do
      expect(result).to have_attributes(low_confidence?: false, clarify?: false, path: "/api/v1/venues")
    end
  end

  context "when part of the request mapped to nothing" do
    it "is not confident even with a high score" do
      expect(result.with(unmapped: ["with a sea view"])).to be_low_confidence
    end
  end

  context "when the score is below the threshold" do
    it "is not confident" do
      expect(result.with(confidence: 0.5)).to be_low_confidence
    end
  end

  context "when the model asks a question" do
    it "asks it" do
      expect(result.with(question: "For how many guests?", options: %w[20 50 100])).to be_clarify
    end
  end
end
