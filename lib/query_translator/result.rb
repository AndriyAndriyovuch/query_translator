# frozen_string_literal: true

class QueryTranslator::Result < Data.define(:resource, :filters, :confidence, :unmapped, :errors, :question, :options)
  CONFIDENCE_THRESHOLD = 0.7

  def self.empty
    new(resource: nil, filters: {}, confidence: 0.0, unmapped: [], errors: [], question: "", options: [])
  end

  def path
    resource&.path
  end

  def clarify?
    !question.to_s.strip.empty?
  end

  def low_confidence?
    confidence.to_f < CONFIDENCE_THRESHOLD || filters.empty? || unmapped.any? || errors.any?
  end
end
