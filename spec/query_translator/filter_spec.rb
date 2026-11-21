# frozen_string_literal: true

RSpec.describe QueryTranslator::Filter do
  describe ".new" do
    it "builds a filter with a known type" do
      filter = described_class.new(name: "by_status", type: "enum", description: "Booking status",
                                   values: %w[paid cancelled])

      expect(filter).to have_attributes(name: "by_status", type: "enum", values: %w[paid cancelled])
    end

    it "rejects an unknown type" do
      expect { described_class.new(name: "by_city_match", type: "text", description: "City") }
        .to raise_error(ArgumentError, /unknown filter type/)
    end

    it "rejects an enum without values" do
      expect { described_class.new(name: "by_status", type: "enum", description: "Booking status") }
        .to raise_error(ArgumentError, /needs values/)
    end
  end
end
