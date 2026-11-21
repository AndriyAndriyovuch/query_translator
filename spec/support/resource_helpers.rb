# frozen_string_literal: true

module ResourceHelpers
  def venues_resource
    QueryTranslator::Resource.new(name: "venues", path: "/api/v1/venues", description: "Halls and studios for rent",
                                  filters: venue_filters)
  end

  def bookings_resource
    QueryTranslator::Resource.new(
      name: "bookings", path: "/api/v1/bookings", description: "The signed-in client's own bookings",
      filters: [
        QueryTranslator::Filter.new(name: "by_status", type: "enum", description: "Booking status",
                                    values: %w[pending paid cancelled])
      ]
    )
  end

  def venue_filters
    [
      QueryTranslator::Filter.new(name: "by_city_match", type: "string", description: "US city name in English"),
      QueryTranslator::Filter.new(name: "by_capacity_gte", type: "integer", description: "Minimum guests"),
      QueryTranslator::Filter.new(name: "max_price", type: "decimal", description: "Highest hourly price in USD"),
      QueryTranslator::Filter.new(name: "available_on", type: "date", description: "Date with a free slot"),
      QueryTranslator::Filter.new(name: "by_category", type: "enum", description: "Kind of place",
                                  values: %w[hall studio loft])
    ]
  end
end
