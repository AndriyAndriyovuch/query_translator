# frozen_string_literal: true

class QueryTranslator::Configuration
  attr_accessor :model, :confidence_threshold, :max_query_length, :extra_instructions

  def initialize
    @model = "claude-haiku-5-5"
    @confidence_threshold = 0.7
    @max_query_length = 500
    @extra_instructions = nil
  end
end
