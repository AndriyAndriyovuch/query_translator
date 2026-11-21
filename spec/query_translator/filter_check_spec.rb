# frozen_string_literal: true

RSpec.describe QueryTranslator::FilterCheck do
  subject(:result) { described_class.call(resource:, filters:) }

  let(:resource) do
    QueryTranslator::Resource.new(
      name: "venues", path: "/api/v1/venues", description: "Venues for rent",
      filters: [
        QueryTranslator::Filter.new(name: "by_city_match", type: "string", description: "City"),
        QueryTranslator::Filter.new(name: "by_capacity_gte", type: "integer", description: "Minimum guests"),
        QueryTranslator::Filter.new(name: "max_price", type: "decimal", description: "Highest hourly price"),
        QueryTranslator::Filter.new(name: "available_on", type: "date", description: "Date with a free slot"),
        QueryTranslator::Filter.new(name: "with_parking", type: "boolean", description: "Has parking"),
        QueryTranslator::Filter.new(name: "by_state", type: "enum", description: "State", values: %w[IL NY])
      ]
    )
  end

  context "when every filter is known and valid" do
    let(:filters) do
      { "by_city_match" => " Chicago ", "by_capacity_gte" => "50", "max_price" => 300,
        "available_on" => "2026-11-28", "with_parking" => "true", "by_state" => "IL" }
    end

    it "returns the cast filters and no errors" do
      expect(result).to have_attributes(
        filters: { "by_city_match" => "Chicago", "by_capacity_gte" => 50, "max_price" => 300.0,
                   "available_on" => Date.new(2026, 11, 28), "with_parking" => true, "by_state" => "IL" },
        errors: []
      )
    end
  end

  context "when a filter is made up and a value is bad" do
    let(:filters) { { "by_city_match" => "Chicago", "by_view" => "sea", "available_on" => "next Saturday" } }

    it "keeps only the valid filter and lists both problems" do
      expect(result.filters).to eq("by_city_match" => "Chicago")
      expect(result.errors).to contain_exactly(match(/unknown filter by_view/), match(/bad date for available_on/))
    end
  end
end
