# frozen_string_literal: true

RSpec.describe Pidgely::Webhook do
  # Official Standard Webhooks / Svix test vector.
  secret = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"
  msg_id = "msg_p5jXN8AQM9LWM0D4loKWxJek"
  ts = 1_614_265_330
  payload = '{"test": 2432232314}'
  signature = "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE="
  headers = { "svix-id" => msg_id, "svix-timestamp" => ts.to_s, "svix-signature" => signature }

  it "matches the signing vector" do
    expect(described_class.sign(secret, msg_id, ts, payload)).to eq(signature)
    expect(described_class.sign(secret.delete_prefix("whsec_"), msg_id, ts.to_s, payload)).to eq(signature)
  end

  it "verifies svix headers and returns the event" do
    expect(described_class.verify(payload: payload, headers: headers, webhook_secret: secret, now: ts)).to eq({ test: 2_432_232_314 })
  end

  it "accepts webhook-* headers, Rack env, Resend-style and symbol keys" do
    variants = [
      { "Webhook-Id" => msg_id, "Webhook-Timestamp" => ts.to_s, "Webhook-Signature" => signature },
      { "HTTP_WEBHOOK_ID" => msg_id, "HTTP_WEBHOOK_TIMESTAMP" => ts.to_s, "HTTP_WEBHOOK_SIGNATURE" => signature },
      { id: msg_id, timestamp: ts.to_s, signature: [signature] }
    ]
    variants.each do |h|
      expect(described_class.verify(payload: payload, headers: h, secret: secret, now: ts)[:test]).to eq(2_432_232_314)
    end
  end

  it "accepts any matching signature and timestamps within the tolerance" do
    many = headers.merge("svix-signature" => "v1,bm90IHRoaXMgb25l #{signature} v2,other")
    expect(described_class.verify(payload: payload, headers: many, webhook_secret: secret, now: ts)).to be_a(Hash)
    expect(described_class.verify(payload: payload, headers: headers, webhook_secret: secret, now: ts + 299)).to be_a(Hash)
    expect(described_class.verify(payload: payload, headers: headers, webhook_secret: secret, now: ts - 299)).to be_a(Hash)
  end

  it "is available from the client, the module API and Pidgely.verify_webhook without an API key" do
    expect(Pidgely::Webhooks.verify(payload: payload, headers: headers, webhook_secret: secret, now: ts)).to eq({ test: 2_432_232_314 })
    expect(Pidgely.verify_webhook(payload: payload, headers: headers, webhook_secret: secret, now: ts)).to eq({ test: 2_432_232_314 })
    c = Pidgely::Client.new(api_key: "pdg_x")
    expect(c.webhooks.verify(payload: payload, headers: headers, webhook_secret: secret, now: ts)).to eq({ test: 2_432_232_314 })
  end

  other = "whsec_#{['another secret value!!'].pack('m0')}"
  {
    "a tampered payload" => [{ payload: '{"test": 2432232315}' }, "No matching signature"],
    "a wrong secret" => [{ webhook_secret: other }, "No matching signature"],
    "a wrong id" => [{ headers: headers.merge("svix-id" => "msg_other") }, "No matching signature"],
    "an old timestamp" => [{ now: ts + 301 }, "too old"],
    "a future timestamp" => [{ now: ts - 301 }, "too new"],
    "a custom tolerance" => [{ now: ts + 11, tolerance: 10 }, "too old"],
    "a non-numeric timestamp" => [{ headers: headers.merge("svix-timestamp" => "12abc") }, "Invalid signature headers"],
    "missing headers" => [{ headers: { "svix-id" => msg_id } }, "Missing required headers"],
    "a missing secret" => [{ webhook_secret: "" }, "Missing webhook secret"],
    "an empty secret key" => [{ webhook_secret: "whsec_" }, "Invalid webhook secret"],
    "an invalid secret" => [{ webhook_secret: "whsec_!!!" }, "Invalid webhook secret"],
    "a badly padded secret" => [{ webhook_secret: "whsec_abc" }, "Invalid webhook secret"]
  }.each do |label, (overrides, message)|
    it "rejects #{label}" do
      args = { payload: payload, headers: headers, webhook_secret: secret, now: ts }.merge(overrides)
      expect { described_class.verify(**args) }.to raise_error(Pidgely::WebhookVerificationError, /#{message}/)
    end
  end

  it "rejects a non-JSON payload" do
    sig = described_class.sign(secret, msg_id, ts, "nope")
    expect { described_class.verify(payload: "nope", headers: headers.merge("svix-signature" => sig), webhook_secret: secret, now: ts) }
      .to raise_error(Pidgely::WebhookVerificationError, /not valid JSON/)
  end

  it "uses the current time by default" do
    expect { described_class.verify(payload: payload, headers: headers, webhook_secret: secret) }.to raise_error(Pidgely::WebhookVerificationError, /too old/)
  end
end
