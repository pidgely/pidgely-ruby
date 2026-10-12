# frozen_string_literal: true

require "logger"

RSpec.describe Pidgely::Client do
  let(:unavailable) { json(503, { statusCode: 503, name: "internal_server_error", message: "busy" }) }
  let(:rate_limited) { json(429, { statusCode: 429, name: "rate_limit_exceeded", message: "slow down" }) }

  describe "configuration" do
    it "reads the environment" do
      ENV["PIDGELY_API_KEY"] = "pdg_env"
      ENV["PIDGELY_BASE_URL"] = "https://env.test/"
      expect(described_class.new.base_url).to eq("https://env.test")
      expect(described_class.new(api_key: "x", base_url: "https://other.test/").base_url).to eq("https://other.test")
      ENV.delete("PIDGELY_BASE_URL")
      expect(described_class.new.base_url).to eq(Pidgely::Client::DEFAULT_BASE_URL)
    end

    it "requires an API key" do
      expect { described_class.new }.to raise_error(Pidgely::MissingApiKeyError) { |e| expect(e.name).to eq("missing_api_key") }
    end

    it "sends the user agent and custom headers" do
      stub = stub_request(:get, "#{BASE}/domains").with(headers: {
                                                          "User-Agent" => "pidgely-ruby/#{Pidgely::VERSION} my-app/1.2",
                                                          "X-Team" => "growth", "X-Trace" => "abc", "Authorization" => "Bearer #{API_KEY}"
                                                        }).to_return(json(200, {}))
      c = client(user_agent: "my-app/1.2", headers: { "X-Team" => "growth" })
      c.domains.list({}, { headers: { "X-Trace" => "abc", "Authorization" => "Bearer other" } })
      expect(stub).to have_been_requested
      expect(c.audiences).to be(c.segments)
    end
  end

  it "never leaks the API key" do
    stub_request(:get, "#{BASE}/emails/e1").to_return(json(401, { statusCode: 401, name: "invalid_api_key", message: "API key is invalid" }))
    stub_request(:get, "#{BASE}/emails/e2").to_raise(SocketError.new("getaddrinfo failed for #{API_KEY}"))
    c = client(max_retries: 0)
    outputs = [c.inspect, c.to_s, c.emails.inspect, c.transport.inspect, c.instance_variables.map { |v| c.instance_variable_get(v).inspect }.join,
               c.transport.instance_variables.map { |v| c.transport.instance_variable_get(v).inspect }.join]
    io = StringIO.new
    Logger.new(io).info(c)
    outputs << io.string
    begin
      c.emails.get("e1")
    rescue Pidgely::AuthenticationError => e
      outputs.push(e.message, e.inspect, e.full_message)
    end
    begin
      c.emails.get("e2")
    rescue Pidgely::APIConnectionError => e
      outputs.push(e.message, e.inspect)
      expect(e.message).to include("[REDACTED]")
    end
    outputs.each do |output|
      expect(output).not_to include(API_KEY)
      expect(output).not_to include("0123456789abcdef")
    end
  end

  describe "errors" do
    {
      "422" => [{ status: 422, body: { statusCode: 422, name: "validation_error", message: "bad to" } }, Pidgely::ValidationError, 422, "validation_error", "bad to"],
      "400" => [{ status: 400, body: { name: "validation_error", message: "bad" } }, Pidgely::ValidationError, 400, "validation_error", "bad"],
      "404" => [{ status: 404, body: { name: "not_found", message: "nope" } }, Pidgely::NotFoundError, 404, "not_found", "nope"],
      "native" => [{ status: 403, body: { error: { code: "forbidden", message: "no" } } }, Pidgely::PermissionDeniedError, 403, "forbidden", "no"],
      "native without message" => [{ status: 403, body: { error: { code: "forbidden" } } }, Pidgely::PermissionDeniedError, 403, "forbidden", "forbidden"],
      "409" => [{ status: 409, body: { name: "invalid_idempotent_request", message: "x" } }, Pidgely::ConflictError, 409, "invalid_idempotent_request", "x"],
      "quota" => [{ status: 429, body: { name: "daily_quota_exceeded", message: "q" } }, Pidgely::RateLimitError, 429, "daily_quota_exceeded", "q"],
      "html" => [{ status: 501, body: "<html>Bad</html>" }, Pidgely::InternalServerError, 501, "internal_server_error", "<html>Bad</html>"],
      "empty" => [{ status: [418, "I'm a teapot"], body: "" }, Pidgely::Error, 418, "application_error", "I'm a teapot"],
      "json list" => [{ status: 400, body: "[1]" }, Pidgely::ValidationError, 400, "application_error", "[1]"]
    }.each do |label, (response, klass, status, name, message)|
      it "maps #{label}" do
        body = response[:body].is_a?(String) ? response[:body] : JSON.generate(response[:body])
        stub_request(:get, "#{BASE}/domains/d").to_return(status: response[:status], body: body)
        expect { client.domains.get("d") }.to raise_error(klass) { |e|
          expect([e.status_code, e.name, e.message]).to eq([status, name, message])
          expect(e).to be_a(Pidgely::Error)
          expect(e.headers).to be_a(Hash)
        }
      end
    end

    it "reports invalid success JSON" do
      stub_request(:get, "#{BASE}/emails/x").to_return(status: 200, body: "{not json")
      expect { client.emails.get("x") }.to raise_error(Pidgely::Error, "Unable to parse the API response")
    end

    it "returns {} for an empty success body" do
      stub_request(:delete, "#{BASE}/domains/d").to_return(status: 200, body: "")
      expect(client.domains.remove("d")).to eq({})
    end

    it "reports timeouts" do
      stub_request(:get, "#{BASE}/emails/x").to_timeout
      expect { client.emails.get("x", { timeout: 1.5, max_retries: 0 }) }.to raise_error(Pidgely::APITimeoutError) { |e|
        expect(e.message).to eq("Request timed out after 1.5s")
        expect(e.status_code).to be_nil
        expect(e.name).to eq("application_error")
      }
    end
  end

  describe "retries" do
    it "retries GET on 5xx with backoff" do
      stub = stub_request(:get, "#{BASE}/emails/e1").to_return(unavailable, unavailable, json(200, { id: "e1" }))
      expect(client.emails.get("e1")).to eq({ id: "e1" })
      expect(stub).to have_been_requested.times(3)
      expect(sleeps[0]).to be_between(0.25, 0.5)
      expect(sleeps[1]).to be_between(0.5, 1.0)
    end

    it "stops after max_retries" do
      stub = stub_request(:get, "#{BASE}/domains").to_return(unavailable)
      expect { client.domains.list }.to raise_error(Pidgely::InternalServerError)
      expect(stub).to have_been_requested.times(3)
    end

    it "honours max_retries options" do
      stub = stub_request(:get, "#{BASE}/domains").to_return(unavailable)
      c = client(max_retries: 0)
      expect { c.domains.list }.to raise_error(Pidgely::InternalServerError)
      expect { c.domains.list({}, { max_retries: 4 }) }.to raise_error(Pidgely::InternalServerError)
      expect(stub).to have_been_requested.times(6)
    end

    it "never retries a POST without an idempotency key" do
      [unavailable, rate_limited, { status: 500, body: "oops" }].each do |failure|
        WebMock.reset!
        stub = stub_request(:post, "#{BASE}/emails").to_return(failure, json(200, { id: "dup" }))
        expect { client.emails.send({ to: "a@b.c" }) }.to raise_error(Pidgely::Error)
        expect(stub).to have_been_requested.once
      end
      WebMock.reset!
      stub = stub_request(:post, "#{BASE}/emails").to_raise(Errno::ECONNRESET)
      expect { client.emails.send({ to: "a@b.c" }) }.to raise_error(Pidgely::APIConnectionError)
      expect(stub).to have_been_requested.once
      expect(sleeps).to be_empty
    end

    it "retries a POST with an idempotency key" do
      stub = stub_request(:post, "#{BASE}/emails")
             .with(headers: { "Idempotency-Key" => "k1" }, body: '{"to":"a@b.c"}')
             .to_return(unavailable, rate_limited).then.to_raise(Errno::ECONNREFUSED).then.to_return(json(200, { id: "e1" }))
      expect(client(max_retries: 3).emails.send({ to: "a@b.c" }, { idempotency_key: "k1" })).to eq({ id: "e1" })
      expect(stub).to have_been_requested.times(4)
    end

    it "retries PATCH and DELETE" do
      patch = stub_request(:patch, "#{BASE}/domains/d").to_return(unavailable, json(200, {}))
      delete = stub_request(:delete, "#{BASE}/domains/d").to_return(unavailable, json(200, {}))
      client.domains.update({ id: "d", tls: "enforced" })
      client.domains.remove("d")
      expect(patch).to have_been_requested.twice
      expect(delete).to have_been_requested.twice
    end

    it "honours Retry-After" do
      stub_request(:get, "#{BASE}/domains").to_return(json(429, { name: "rate_limit_exceeded", message: "x" }, { "Retry-After" => "3" }), json(200, {}))
      client.domains.list
      expect(sleeps).to eq([3.0])
    end

    it "does not wait for a Retry-After over 60 seconds" do
      stub = stub_request(:get, "#{BASE}/domains").to_return(json(429, { name: "rate_limit_exceeded", message: "x" }, { "Retry-After" => "120" }))
      expect { client.domains.list }.to raise_error(Pidgely::RateLimitError) { |e| expect(e.headers["retry-after"]).to eq("120") }
      expect(stub).to have_been_requested.once
    end

    it "never retries quota errors or 422" do
      stub = stub_request(:get, "#{BASE}/domains").to_return(json(429, { name: "monthly_quota_exceeded", message: "q" }), json(422, { name: "validation_error", message: "x" }))
      expect { client.domains.list }.to raise_error(Pidgely::RateLimitError)
      expect { client.domains.list }.to raise_error(Pidgely::ValidationError)
      expect(stub).to have_been_requested.twice
    end

    it "retries GET on network errors" do
      stub = stub_request(:get, "#{BASE}/domains").to_raise(SocketError.new("down"))
      expect { client.domains.list }.to raise_error(Pidgely::APIConnectionError, "Unable to reach the Pidgely API: down")
      expect(stub).to have_been_requested.times(3)
      expect(sleeps.size).to eq(2)
    end
  end

  describe "helpers" do
    it "parses Retry-After" do
      now = Time.utc(2026, 10, 12, 12)
      t = Pidgely::Transport
      expect(t.parse_retry_after(nil)).to be_nil
      expect(t.parse_retry_after("")).to be_nil
      expect(t.parse_retry_after("2")).to eq(2.0)
      expect(t.parse_retry_after("1.5")).to eq(1.5)
      expect(t.parse_retry_after("-1")).to be_nil
      expect(t.parse_retry_after("soon")).to be_nil
      expect(t.parse_retry_after((now + 5).httpdate, now)).to eq(5.0)
      expect(t.parse_retry_after((now - 3600).httpdate, now)).to eq(0.0)
    end

    it "bounds the backoff" do
      expect(Pidgely::Transport.backoff(0, 0.0)).to eq(0.25)
      expect(Pidgely::Transport.backoff(0, 1.0)).to eq(0.5)
      expect(Pidgely::Transport.backoff(10, 1.0)).to eq(8.0)
      8.times do |attempt|
        cap = [8.0, 0.5 * (2**attempt)].min
        expect(Pidgely::Transport.backoff(attempt)).to be_between(cap / 2, cap)
      end
    end

    it "escapes path segments" do
      expect(Pidgely::Util.seg("a b/c")).to eq("a%20b%2Fc")
      expect(Pidgely::Util.seg("ana+x@example.com")).to eq("ana+x@example.com")
    end
  end
end
