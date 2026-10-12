# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch
end

require "pidgely"
require "webmock/rspec"

API_KEY = "pdg_test_0123456789abcdef"
BASE = "https://api.pidgely.test"

module SpecHelpers
  def client(**options)
    c = Pidgely::Client.new(api_key: API_KEY, base_url: BASE, **options)
    c.transport.sleeper = ->(seconds) { sleeps << seconds }
    c
  end

  def sleeps
    @sleeps ||= []
  end

  def json(status, body, headers = {})
    { status: status, body: body.is_a?(String) ? body : JSON.generate(body), headers: { "Content-Type" => "application/json" }.merge(headers) }
  end
end

RSpec.configure do |config|
  config.include SpecHelpers
  config.disable_monkey_patching!
  config.order = :random
  config.example_status_persistence_file_path = ".rspec_status"
  config.before do
    WebMock.disable_net_connect!
    Pidgely.reset!
    @saved_env = ENV.to_h.slice("PIDGELY_API_KEY", "PIDGELY_BASE_URL")
    ENV.delete("PIDGELY_API_KEY")
    ENV.delete("PIDGELY_BASE_URL")
  end
  config.after do
    ENV.update(@saved_env)
  end
end
