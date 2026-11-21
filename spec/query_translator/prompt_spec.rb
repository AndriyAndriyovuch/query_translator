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

  describe "#instructions with a filter that allows several values" do
    subject(:prompt) { described_class.new(resources: [bookings], today: Date.new(2026, 11, 21)) }

    let(:bookings) { bookings_resource.with(filters: [bookings_resource.filters.first.with(multiple: true)]) }

    it "says so next to the filter" do
      expect(prompt.instructions).to include("Values: pending, paid, cancelled. Several values allowed.")
    end
  end

  describe "#instructions with the app's own rules" do
    it "adds them after the gem's rules" do
      allow(QueryTranslator.config).to receive(:extra_instructions).and_return("Prices are per time slot.")

      expect(prompt.instructions).to end_with("More rules from the app:\nPrices are per time slot.\n")
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
