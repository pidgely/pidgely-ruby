# frozen_string_literal: true

module Pidgely
  # Base class of every API, network and configuration error raised by the SDK.
  #
  # +name+ is the API's machine-readable error name (validation_error, not_found,
  # rate_limit_exceeded...). +status_code+ is the HTTP status, or nil when no response
  # was received. The API key never appears in an error.
  class Error < StandardError
    attr_reader :name, :status_code, :headers

    def initialize(message, name: "application_error", status_code: nil, headers: {})
      super(message)
      @name = name
      @status_code = status_code
      @headers = headers
    end

    def inspect
      "#<#{self.class.name} name=#{name.inspect} status_code=#{status_code.inspect} message=#{message.inspect}>"
    end
  end

  # 400 / 422: the request is invalid.
  class ValidationError < Error; end
  # 401: missing or invalid API key.
  class AuthenticationError < Error; end
  # 403: restricted key, unverified domain or plan limit.
  class PermissionDeniedError < Error; end
  # 404: the resource does not exist.
  class NotFoundError < Error; end
  # 409: for example an idempotency key reused with a different body.
  class ConflictError < Error; end
  # 429: rate limit or quota exceeded.
  class RateLimitError < Error; end
  # 5xx: the API failed.
  class InternalServerError < Error; end
  # The API could not be reached (DNS, connection, TLS, read errors).
  class APIConnectionError < Error; end
  # An attempt exceeded the timeout.
  class APITimeoutError < APIConnectionError; end
  # No API key was given and PIDGELY_API_KEY is not set.
  class MissingApiKeyError < Error; end

  # A webhook delivery could not be verified.
  class WebhookVerificationError < StandardError; end

  ERRORS_BY_STATUS = {
    400 => ValidationError,
    401 => AuthenticationError,
    403 => PermissionDeniedError,
    404 => NotFoundError,
    409 => ConflictError,
    422 => ValidationError,
    429 => RateLimitError
  }.freeze
  private_constant :ERRORS_BY_STATUS

  # @api private
  def self.error_for(status, name, message, headers)
    klass = ERRORS_BY_STATUS.fetch(status) { status >= 500 ? InternalServerError : Error }
    klass.new(message, name: name, status_code: status, headers: headers)
  end
end
