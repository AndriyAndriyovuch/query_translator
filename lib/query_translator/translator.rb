# frozen_string_literal: true

class QueryTranslator::Translator
  def self.call(query:, resources:, today: Date.today)
    new(query:, resources:, today:).call
  end

  def initialize(query:, resources:, today:)
    @query = query.to_s.strip[0, QueryTranslator.config.max_query_length]
    @resources = resources
    @today = today
  end

  def call
    return QueryTranslator::Result.empty if @query.empty?

    QueryTranslator::Result.new(resource:, filters: check.filters, errors: check.errors, **answer_details)
  end

  private

  def answer
    @answer ||= chat.ask(@query).parsed || raise(QueryTranslator::Error, "the model gave no answer")
  rescue RubyLLM::Error, JSON::ParserError => e
    raise QueryTranslator::Error, e.message
  end

  def chat
    prompt = QueryTranslator::Prompt.new(resources: @resources, today: @today)
    RubyLLM.chat(model: QueryTranslator.config.model).with_instructions(prompt.instructions).with_schema(prompt.schema)
  end

  def resource
    @resource ||= @resources.find { |item| item.name.to_s == answer["resource"] }
  end

  def check
    @check ||= resource ? QueryTranslator::FilterCheck.call(resource:, filters: answered_filters) : unknown_resource
  end

  def unknown_resource
    QueryTranslator::FilterCheck::Result.new(filters: {}, errors: ["unknown resource #{answer["resource"]}"])
  end

  def answer_details
    { confidence: answer["confidence"].to_f, unmapped: answer["unmapped"].to_a,
      question: answer["question"].to_s, options: answer["options"].to_a }
  end

  def answered_filters
    answer["filters"].to_a.to_h { |filter| [filter["name"], filter["value"]] }
  end
end
