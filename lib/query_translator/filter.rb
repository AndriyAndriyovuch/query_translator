# frozen_string_literal: true

class QueryTranslator::Filter < Data.define(:name, :type, :description, :values, :multiple)
  TYPES = %w[string integer decimal date datetime boolean enum].freeze

  def initialize(name:, type:, description:, values: nil, multiple: false)
    raise ArgumentError, "unknown filter type: #{type}" unless TYPES.include?(type.to_s)
    raise ArgumentError, "enum filter #{name} needs values" if type.to_s == "enum" && Array(values).empty?

    super
  end
end
