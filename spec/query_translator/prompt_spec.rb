# frozen_string_literal: true

RSpec.describe QueryTranslator::Prompt do
  subject(:prompt) do
    described_class.new(resources: [venues_resource, bookings_resource], today: Date.new(2026, 11, 21))
  end

  describe "#instructions" do
    it "names today, every resource and every filter with its type" do
      expect(prompt.instructions).to include("Saturday, 2026-11-21", "venues: Halls and studios for rent",
                                             "by_capacity_gte (integer): Minimum guests",
                                             "by_status (enum): Booking status Values: pending, paid, cancelled.")
    end
  end

  describe "#schema" do
    it "lets the model pick only the listed resources and filters" do
      properties = prompt.schema[:properties]

      expect(properties[:resource][:enum]).to eq(%w[venues bookings])
      expect(properties[:filters][:items][:properties][:name][:enum])
        .to eq(%w[by_city_match by_capacity_gte max_price available_on by_category by_status])
    end
  end
end
