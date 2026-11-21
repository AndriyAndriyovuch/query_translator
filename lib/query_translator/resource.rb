# frozen_string_literal: true

class QueryTranslator::Resource < Data.define(:name, :path, :description, :filters)
end
