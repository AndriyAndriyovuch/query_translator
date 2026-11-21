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
        QueryTranslator::Filter.new(name: "by_state", type: "enum", description: "State", values: %w[IL NY]),
        QueryTranslator::Filter.new(name: "by_status", type: "enum", description: "Status", values: %w[draft paid],
                                    multiple: true),
        QueryTranslator::Filter.new(name: "by_created_at_gte", type: "datetime", description: "Created since")
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

  context "when a filter allows several values and a datetime is given" do
    let(:filters) { { "by_status" => %w[draft paid draft], "by_created_at_gte" => "2026-11-01T00:00:00Z" } }

    it "keeps every distinct value and the parsed time" do
      expect(result).to have_attributes(
        filters: { "by_status" => %w[draft paid], "by_created_at_gte" => Time.utc(2026, 11, 1) }, errors: []
      )
    end
  end

  context "when a filter that takes one value gets several" do
    let(:filters) { { "by_state" => %w[IL NY] } }

    it "keeps none of them and reports it" do
      expect(result).to have_attributes(filters: {}, errors: [a_string_including("by_state takes one value")])
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
