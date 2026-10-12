# frozen_string_literal: true

module Pidgely
  # Pidgely API client.
  #
  #   client = Pidgely::Client.new(api_key: ENV["PIDGELY_API_KEY"])
  #   client.emails.send({ from: "...", to: "...", subject: "...", html: "..." })
  #
  # The API key never appears in #inspect, logs or raised errors.
  class Client
    DEFAULT_BASE_URL = "https://api.pidgely.com"

    attr_reader :emails, :batch, :domains, :api_keys, :contacts, :segments, :broadcasts, :templates, :webhooks,
                :suppressions

    # @param api_key [String, nil] pdg_... key; defaults to PIDGELY_API_KEY
    # @param base_url [String, nil] defaults to PIDGELY_BASE_URL or https://api.pidgely.com
    # @param timeout [Numeric] seconds per attempt (default 30, 0 disables)
    # @param max_retries [Integer] automatic retries (default 2)
    # @param user_agent [String, nil] appended to pidgely-ruby/<version>
    # @param headers [Hash] headers sent with every request
    # @raise [Pidgely::MissingApiKeyError]
    def initialize(api_key: nil, base_url: nil, timeout: nil, max_retries: nil, user_agent: nil, headers: {})
      key = api_key.to_s.empty? ? ENV.fetch("PIDGELY_API_KEY", "") : api_key.to_s
      if key.empty?
        raise MissingApiKeyError.new(
          'Missing API key. Set Pidgely.api_key, pass Pidgely::Client.new(api_key: "pdg_..."), or set PIDGELY_API_KEY.',
          name: "missing_api_key"
        )
      end

      url = base_url.to_s.empty? ? ENV.fetch("PIDGELY_BASE_URL", "") : base_url.to_s
      url = DEFAULT_BASE_URL if url.empty?
      ua = "pidgely-ruby/#{VERSION}"
      ua = "#{ua} #{user_agent}" unless user_agent.to_s.empty?
      @transport = Transport.new(
        api_key: key, base_url: url.chomp("/").sub(%r{/+\z}, ""), timeout: (timeout || 30).to_f,
        max_retries: [Integer(max_retries || 2), 0].max, user_agent: ua, headers: Util.stringify(headers || {})
      )
      build_resources
    end

    # The legacy name of #segments, kept for Resend compatibility.
    def audiences
      @segments
    end

    def base_url
      @transport.base_url
    end

    # @api private
    attr_reader :transport

    def inspect
      "#<Pidgely::Client base_url=#{base_url.inspect}>"
    end
    alias to_s inspect

    private

    def build_resources
      @emails = Resources::Emails.new(@transport)
      @batch = Resources::Batch.new(@transport)
      @domains = Resources::Domains.new(@transport)
      @api_keys = Resources::ApiKeys.new(@transport)
      @contacts = Resources::Contacts.new(@transport)
      @segments = Resources::Segments.new(@transport)
      @broadcasts = Resources::Broadcasts.new(@transport)
      @templates = Resources::Templates.new(@transport)
      @webhooks = Resources::Webhooks.new(@transport)
      @suppressions = Resources::Suppressions.new(@transport)
    end
  end
end
