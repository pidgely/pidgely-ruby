# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

module Pidgely
  # HTTP layer: auth, JSON, timeouts, retries. Uses only the standard library.
  #
  # @api private
  class Transport
    RETRYABLE_STATUS = [408, 429, 500, 502, 503, 504].freeze
    BACKOFF_BASE = 0.5
    BACKOFF_CAP = 8.0
    MAX_RETRY_AFTER = 60.0
    TIMEOUT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout].freeze
    NETWORK_ERRORS = [
      SocketError, SystemCallError, IOError, EOFError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
    ].freeze

    attr_reader :base_url, :timeout, :max_retries
    attr_writer :sleeper

    def initialize(api_key:, base_url:, timeout:, max_retries:, user_agent:, headers:)
      # Held in a closure so it never shows up in #inspect, instance_variables or dumps.
      @credentials = -> { api_key }
      @base_url = base_url
      @timeout = timeout
      @max_retries = max_retries
      @user_agent = user_agent
      @headers = headers
      @sleeper = ->(seconds) { sleep(seconds) }
    end

    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect}>"
    end

    # Performs a request with retries and returns the parsed JSON (symbol keys), or {} for an empty body.
    def request(method, path, query: nil, body: nil, options: {}, headers: {})
      options = Util.symbolize(options || {})
      uri = build_uri(path, query)
      req = build_request(method, uri, body, options, headers)
      timeout = (options[:timeout] || @timeout).to_f
      max_retries = [Integer(options[:max_retries] || @max_retries), 0].max
      # A POST without an idempotency key is never retried: the API might already have
      # accepted it, and a retry could send the email twice.
      can_retry = method != :post || !options[:idempotency_key].to_s.empty?

      attempt = 0
      loop do
        network = false
        begin
          response = perform(uri, req, timeout)
          return decode(response) if response.code.to_i.between?(200, 299)

          error = parse_error(response)
        rescue *TIMEOUT_ERRORS
          network = true
          error = APITimeoutError.new("Request timed out after #{format_seconds(timeout)}s")
        rescue *NETWORK_ERRORS => e
          network = true
          error = APIConnectionError.new("Unable to reach the Pidgely API: #{redact(e.message.to_s.empty? ? e.class.name : e.message)}")
        end
        delay = retry_delay(error, attempt, max_retries, can_retry, network)
        raise error if delay.nil?

        @sleeper.call(delay)
        attempt += 1
      end
    end

    # Exponential backoff with jitter: 50-100% of min(cap, base * 2**attempt), in seconds.
    def self.backoff(attempt, random = rand)
      exp = [BACKOFF_CAP, BACKOFF_BASE * (2**[attempt, 10].min)].min
      (exp / 2) + (random * exp / 2)
    end

    # Retry-After in seconds or as an HTTP date, converted to seconds.
    def self.parse_retry_after(value, now = Time.now)
      return nil if value.nil? || value.strip.empty?

      value = value.strip
      if value.match?(/\A-?\d+(\.\d+)?\z/)
        seconds = value.to_f
        return seconds.negative? ? nil : seconds
      end
      [Time.httpdate(value) - now, 0.0].max.to_f
    rescue ArgumentError
      nil
    end

    private

    def build_uri(path, query)
      uri = URI.parse(@base_url + path)
      params = (query || {}).compact.transform_values(&:to_s)
      uri.query = URI.encode_www_form(params) unless params.empty?
      uri
    end

    def build_request(method, uri, body, options, headers)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }.fetch(method)
      req = klass.new(uri)
      req["Accept"] = "application/json"
      req["User-Agent"] = @user_agent
      @headers.merge(headers).merge(Util.stringify(options[:headers] || {})).each { |k, v| req[k.to_s] = v.to_s }
      req["Authorization"] = "Bearer #{@credentials.call}"
      unless body.nil?
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end
      req["Idempotency-Key"] = options[:idempotency_key].to_s unless options[:idempotency_key].to_s.empty?
      req
    end

    def perform(uri, req, timeout)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      if timeout.positive?
        http.open_timeout = [timeout, 10].min
        http.read_timeout = timeout
        http.write_timeout = timeout
      end
      http.start { |conn| conn.request(req) }
    end

    def decode(response)
      text = response.body.to_s
      return {} if text.strip.empty?

      data = JSON.parse(text, symbolize_names: true)
      data.is_a?(Hash) ? data : { data: data }
    rescue JSON::ParserError
      raise Error.new("Unable to parse the API response", headers: response_headers(response))
    end

    def parse_error(response)
      status = response.code.to_i
      headers = response_headers(response)
      text = response.body.to_s
      body = begin
        JSON.parse(text)
      rescue JSON::ParserError
        nil
      end
      if body.is_a?(Hash)
        return Pidgely.error_for(status, body["name"], body["message"], headers) if body["name"].is_a?(String) && body["message"].is_a?(String)

        native = body["error"]
        if native.is_a?(Hash) && native["code"].is_a?(String)
          message = native["message"].is_a?(String) ? native["message"] : native["code"]
          return Pidgely.error_for(status, native["code"], message, headers)
        end
      end
      name = status >= 500 ? "internal_server_error" : "application_error"
      message = text.strip
      message = response.message.to_s.strip if message.empty?
      message = "HTTP #{status}" if message.empty?
      Pidgely.error_for(status, name, message, headers)
    end

    def retry_delay(error, attempt, max_retries, can_retry, network)
      return nil if attempt >= max_retries || !can_retry
      return self.class.backoff(attempt) if network
      return nil if !RETRYABLE_STATUS.include?(error.status_code) || error.name.to_s.end_with?("quota_exceeded")

      retry_after = self.class.parse_retry_after(error.headers["retry-after"])
      return self.class.backoff(attempt) if retry_after.nil?

      retry_after > MAX_RETRY_AFTER ? nil : retry_after
    end

    def response_headers(response)
      response.to_hash.transform_keys(&:downcase).transform_values { |v| v.join(", ") }
    end

    def redact(text)
      text.gsub(@credentials.call, "[REDACTED]")
    end

    def format_seconds(seconds)
      seconds == seconds.to_i ? seconds.to_i.to_s : seconds.to_s
    end
  end

  # @api private
  module Util
    module_function

    def symbolize(hash)
      hash.to_h.transform_keys(&:to_sym)
    end

    def stringify(hash)
      hash.to_h.transform_keys(&:to_s)
    end

    # Escapes a path segment (ids, emails, template aliases).
    def seg(value)
      URI.encode_www_form_component(value.to_s).gsub("+", "%20").gsub("%40", "@").gsub("%2B", "+")
    end

    def fetch(params, *keys)
      keys.each do |key|
        value = params[key.to_sym] || params[key.to_s]
        return value.to_s unless value.nil? || value.to_s.empty?
      end
      raise Error.new("Missing #{keys.map { |k| "`#{k}`" }.join(" or ")} field.", name: "missing_required_field")
    end

    def id!(value, name = "id")
      raise Error.new("Missing `#{name}`.", name: "missing_required_field") if value.nil? || value.to_s.empty?

      seg(value)
    end

    def without(params, *keys)
      names = keys.flat_map { |k| [k.to_s, k.to_sym] }
      params.to_h.except(*names)
    end

    def page(params, *extra)
      params = symbolize(params || {})
      %i[limit after before].concat(extra).each_with_object({}) do |key, out|
        out[key] = params[key] unless params[key].nil?
      end
    end
  end
end
