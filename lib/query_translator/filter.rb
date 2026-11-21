# frozen_string_literal: true

class QueryTranslator::Filter < Data.define(:name, :type, :description, :values)
  TYPES = %w[string integer decimal date boolean enum].freeze

  def initialize(name:, type:, description:, values: nil)
    raise ArgumentError, "unknown filter type: #{type}" unless TYPES.include?(type.to_s)
    raise ArgumentError, "enum filter #{name} needs values" if type.to_s == "enum" && Array(values).empty?

    super
  end
end
