# frozen_string_literal: true

require "vcr"
require "webmock/rspec"

VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("../cassettes", __dir__)
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.default_cassette_options = { record: ENV["ANTHROPIC_API_KEY"] ? :once : :none,
                                      match_requests_on: %i[method uri body] }
  config.before_record do |interaction|
    interaction.ignore! unless interaction.response.status.code == 200
    interaction.request.headers.reject! { |name, _| name.casecmp?("x-api-key") }
    interaction.response.headers.select! { |name, _| name.casecmp?("content-type") }
  end
end
