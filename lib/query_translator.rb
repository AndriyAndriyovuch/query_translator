# frozen_string_literal: true

require "date"
require "json"
require "ruby_llm"
require_relative "query_translator/version"
require_relative "query_translator/configuration"
require_relative "query_translator/filter"
require_relative "query_translator/resource"
require_relative "query_translator/filter_check"
require_relative "query_translator/prompt"
require_relative "query_translator/result"
require_relative "query_translator/translator"

module QueryTranslator
  class Error < StandardError; end

  def self.config
    @config ||= Configuration.new
  end

  def self.configure
    yield config
  end
end
