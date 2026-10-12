# frozen_string_literal: true

require "json"
require "openssl"

module Pidgely
  # Verifies webhook deliveries (Standard Webhooks / Svix scheme).
  #
  # Pidgely signs every delivery with HMAC-SHA256 and sends the values under both the
  # webhook-* and svix-* header names.
  module Webhook
    # Maximum accepted clock difference, in seconds.
    DEFAULT_TOLERANCE = 300

    module_function

    # Verifies a delivery and returns the parsed event (a Hash with symbol keys).
    #
    # @param payload [String] the raw request body, exactly as received
    # @param headers [Hash] request headers (any case, symbol or string keys), a Rack env
    #   (HTTP_WEBHOOK_ID...), or { id:, timestamp:, signature: }
    # @param webhook_secret [String] the endpoint's signing secret (whsec_...); +secret:+ also works
    # @param tolerance [Integer] maximum clock difference in seconds
    # @param now [Integer, nil] override the current Unix time (tests)
    # @raise [Pidgely::WebhookVerificationError]
    def verify(payload:, headers:, webhook_secret: nil, secret: nil, tolerance: DEFAULT_TOLERANCE, now: nil)
      secret = webhook_secret || secret
      key(secret)
      normalized = normalize(headers)
      id = header(normalized, "id")
      timestamp = header(normalized, "timestamp")
      signature = header(normalized, "signature")
      raise WebhookVerificationError, "Missing required headers" if id.nil? || timestamp.nil? || signature.nil?
      raise WebhookVerificationError, "Invalid signature headers" unless timestamp.match?(/\A\d+\z/)

      ts = timestamp.to_i
      current = (now || Time.now).to_i
      raise WebhookVerificationError, "Message timestamp too old" if current - ts > tolerance
      raise WebhookVerificationError, "Message timestamp too new" if ts - current > tolerance

      expected = sign(secret, id, timestamp, payload)
      matched = false
      signature.split.each do |candidate|
        # Compare every candidate so timing does not reveal which one matched.
        matched = true if OpenSSL.fixed_length_secure_compare(digest(candidate), digest(expected))
      end
      raise WebhookVerificationError, "No matching signature found" unless matched

      begin
        JSON.parse(payload, symbolize_names: true)
      rescue JSON::ParserError
        raise WebhookVerificationError, "Payload is not valid JSON"
      end
    end

    # Computes the "v1,<base64>" signature of a delivery.
    def sign(secret, id, timestamp, payload)
      mac = OpenSSL::HMAC.digest("SHA256", key(secret), "#{id}.#{timestamp}.#{payload}")
      "v1,#{[mac].pack("m0")}"
    end

    def key(secret)
      raise WebhookVerificationError, "Missing webhook secret" if secret.nil? || secret.empty?

      encoded = secret.delete_prefix("whsec_")
      raise WebhookVerificationError, "Invalid webhook secret" unless encoded.match?(%r{\A[A-Za-z0-9+/]+={0,2}\z})

      decoded = encoded.unpack1("m0")
      raise WebhookVerificationError, "Invalid webhook secret" if decoded.empty?

      decoded
    rescue ArgumentError
      raise WebhookVerificationError, "Invalid webhook secret"
    end

    def digest(value)
      OpenSSL::Digest::SHA256.digest(value)
    end

    def normalize(headers)
      headers.to_h.each_with_object({}) do |(name, value), out|
        k = name.to_s.downcase.tr("_", "-").delete_prefix("http-")
        out[k] = value.is_a?(Array) ? value.join(" ") : value.to_s
      end
    end

    def header(headers, name)
      ["webhook-#{name}", "svix-#{name}", name].each do |key|
        value = headers[key]
        return value unless value.nil? || value.empty?
      end
      nil
    end

    private_class_method :key, :digest, :normalize, :header
  end
end
