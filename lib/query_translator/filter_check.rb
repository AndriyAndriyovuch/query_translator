# frozen_string_literal: true

require "date"
require "time"

class QueryTranslator::FilterCheck
  Result = Data.define(:filters, :errors)
  SWITCHED_ON = [true, "true"].freeze

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
    @filters.each { |name, value| check(name.to_s, Array(value).compact) }
    Result.new(filters: @checked, errors: @errors)
  end

  private

  def check(name, values)
    return if values.empty?

    filter = find_filter(name)
    return @errors << "unknown filter #{name}" unless filter
    return @errors << "#{name} takes one value, got #{values.size}" if values.size > 1 && !filter.multiple

    keep(filter, name, values.map { |value| cast_or_report(filter, name, value) }.compact)
  end

  def find_filter(name)
    @resource.filters.find { |filter| filter.name.to_s == name }
  end

  def keep(filter, name, cast_values)
    return if cast_values.empty?

    @checked[name] = filter.multiple ? cast_values.uniq : cast_values.first
  end

  def cast_or_report(filter, name, value)
    cast_value = cast(filter, value)
    @errors << "bad #{filter.type} for #{name}: #{value.inspect}" if cast_value.nil?
    cast_value
  end

  def cast(filter, value)
    case filter.type.to_s
    when "string" then cast_string(value)
    when "integer", "decimal" then cast_number(filter, value)
    when "date" then cast_date(value)
    when "datetime" then cast_datetime(value)
    when "boolean" then cast_boolean(value)
    when "enum" then cast_enum(filter, value)
    end
  end

  def cast_string(value)
    value.strip if value.is_a?(String) && !value.strip.empty?
  end

  def cast_boolean(value)
    true if SWITCHED_ON.include?(value)
  end

  def cast_number(filter, value)
    filter.type.to_s == "integer" ? Integer(value.to_s, 10, exception: false) : Float(value.to_s, exception: false)
  end

  def cast_enum(filter, value)
    value.to_s if filter.values.map(&:to_s).include?(value.to_s)
  end

  def cast_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  def cast_datetime(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
