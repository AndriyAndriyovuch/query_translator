# frozen_string_literal: true

require "date"

class QueryTranslator::FilterCheck
  Result = Data.define(:filters, :errors)
  BOOLEANS = { true => true, false => false, "true" => true, "false" => false }.freeze

  def self.call(resource:, filters:)
    new(resource:, filters:).call
  end

  def initialize(resource:, filters:)
    @resource = resource
    @filters = filters.to_h
    @checked = {}
    @errors = []
  end

  def call
    @filters.each { |name, value| check(name.to_s, value) unless value.nil? }
    Result.new(filters: @checked, errors: @errors)
  end

  private

  def check(name, value)
    filter = @resource.filters.find { |item| item.name.to_s == name }
    return @errors << "unknown filter #{name}" unless filter

    cast_value = cast(filter, value)
    return @errors << "bad #{filter.type} for #{name}: #{value.inspect}" if cast_value.nil?

    @checked[name] = cast_value
  end

  def cast(filter, value)
    case filter.type.to_s
    when "string" then cast_string(value)
    when "integer" then Integer(value.to_s, 10, exception: false)
    when "decimal" then Float(value.to_s, exception: false)
    when "date" then cast_date(value)
    when "boolean" then BOOLEANS[value]
    when "enum" then cast_enum(filter, value)
    end
  end

  def cast_string(value)
    value.strip if value.is_a?(String) && !value.strip.empty?
  end

  def cast_enum(filter, value)
    value.to_s if filter.values.map(&:to_s).include?(value.to_s)
  end

  def cast_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end
end
