# frozen_string_literal: true

require_relative "pidgely/version"
require_relative "pidgely/errors"
require_relative "pidgely/transport"
require_relative "pidgely/webhook"
require_relative "pidgely/resources"
require_relative "pidgely/client"
require_relative "pidgely/module_api"

# Official Ruby SDK for the Pidgely email API (Resend-compatible).
#
#   require "pidgely"
#   Pidgely.api_key = ENV["PIDGELY_API_KEY"]
#   Pidgely::Emails.send({ from: "Acme <hello@acme.com>", to: "ana@example.org",
#                          subject: "Welcome to Acme", html: "<p>Your account is ready.</p>" })
#
# Documentation: https://docs.pidgely.com
module Pidgely
  @mutex = Mutex.new

  class << self
    # API key for the module API (defaults to PIDGELY_API_KEY).
    attr_accessor :api_key
    # Base URL for the module API (defaults to PIDGELY_BASE_URL or https://api.pidgely.com).
    attr_accessor :base_url
    # Per-attempt timeout in seconds for the module API (default 30).
    attr_accessor :timeout
    # Automatic retries for the module API (default 2).
    attr_accessor :max_retries

    # The client behind the module API, rebuilt when the settings above change.
    def client
      config = [api_key, base_url, timeout, max_retries, ENV.fetch("PIDGELY_API_KEY", nil), ENV.fetch("PIDGELY_BASE_URL", nil)]
      @mutex.synchronize do
        if @client.nil? || @client_config != config
          @client = Client.new(api_key: api_key, base_url: base_url, timeout: timeout, max_retries: max_retries)
          @client_config = config
        end
        @client
      end
    end

    # Clears the module API settings and client (tests).
    def reset!
      @mutex.synchronize do
        self.api_key = self.base_url = self.timeout = self.max_retries = nil
        @client = @client_config = nil
      end
    end

    # Verifies a webhook delivery; see {Pidgely::Webhook.verify}.
    def verify_webhook(**kwargs)
      Webhook.verify(**kwargs)
    end
  end
end
