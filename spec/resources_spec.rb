# frozen_string_literal: true

RSpec.describe "resources" do
  ok = { object: "x", id: "1" }

  cases = {
    "emails.get" => [->(c) { c.emails.get("e 1") }, :get, "/emails/e%201", nil, nil],
    "emails.list" => [->(c) { c.emails.list({ limit: 10, after: "cur" }) }, :get, "/emails", { "limit" => "10", "after" => "cur" }, nil],
    "emails.update" => [->(c) { c.emails.update({ id: "e1", scheduled_at: "in 2 hours" }) }, :patch, "/emails/e1", nil, { "scheduled_at" => "in 2 hours" }],
    "emails.cancel" => [->(c) { c.emails.cancel("e1") }, :post, "/emails/e1/cancel", nil, nil],
    "emails.attachments.list" => [->(c) { c.emails.attachments.list({ email_id: "e1" }) }, :get, "/emails/e1/attachments", nil, nil],
    "emails.attachments.get" => [->(c) { c.emails.attachments.get({ email_id: "e1", id: "a1" }) }, :get, "/emails/e1/attachments/a1", nil, nil],
    "batch.create" => [->(c) { c.batch.create([{ to: "a@b.c" }]) }, :post, "/emails/batch", nil, [{ "to" => "a@b.c" }]],
    "domains.create" => [->(c) { c.domains.create({ name: "acme.com", tls: "opportunistic" }) }, :post, "/domains", nil, { "name" => "acme.com", "tls" => "opportunistic" }],
    "domains.get" => [->(c) { c.domains.get("d1") }, :get, "/domains/d1", nil, nil],
    "domains.list" => [->(c) { c.domains.list({ before: "x" }) }, :get, "/domains", { "before" => "x" }, nil],
    "domains.update" => [->(c) { c.domains.update({ id: "d1", tls: "enforced" }) }, :patch, "/domains/d1", nil, { "tls" => "enforced" }],
    "domains.remove" => [->(c) { c.domains.remove("d1") }, :delete, "/domains/d1", nil, nil],
    "domains.verify" => [->(c) { c.domains.verify("d1") }, :post, "/domains/d1/verify", nil, nil],
    "api_keys.create" => [->(c) { c.api_keys.create({ name: "Prod", domain_id: "d1" }) }, :post, "/api-keys", nil, { "name" => "Prod", "domain_id" => "d1" }],
    "api_keys.list" => [->(c) { c.api_keys.list }, :get, "/api-keys", nil, nil],
    "api_keys.update" => [->(c) { c.api_keys.update("k1", { name: "New" }) }, :patch, "/api-keys/k1", nil, { "name" => "New" }],
    "api_keys.remove" => [->(c) { c.api_keys.remove("k1") }, :delete, "/api-keys/k1", nil, nil],
    "contacts.create" => [->(c) { c.contacts.create({ email: "ana@x.y", segments: [{ id: "s1" }] }) }, :post, "/contacts", nil, { "email" => "ana@x.y", "segments" => [{ "id" => "s1" }] }],
    "contacts.create audience" => [->(c) { c.contacts.create({ email: "ana@x.y", audience_id: "aud1" }) }, :post, "/audiences/aud1/contacts", nil, { "email" => "ana@x.y" }],
    "contacts.list" => [->(c) { c.contacts.list({ segment_id: "s1", limit: 100 }) }, :get, "/contacts", { "limit" => "100", "segment_id" => "s1" }, nil],
    "contacts.list audience" => [->(c) { c.contacts.list({ audience_id: "a1" }) }, :get, "/contacts", { "audience_id" => "a1" }, nil],
    "contacts.get string" => [->(c) { c.contacts.get("ana+x@x.y") }, :get, "/contacts/ana+x@x.y", nil, nil],
    "contacts.get email" => [->(c) { c.contacts.get({ email: "ana@x.y" }) }, :get, "/contacts/ana@x.y", nil, nil],
    "contacts.get audience" => [->(c) { c.contacts.get({ "email" => "ana@x.y", "audience_id" => "a1" }) }, :get, "/audiences/a1/contacts/ana@x.y", nil, nil],
    "contacts.update" => [->(c) { c.contacts.update({ email: "ana@x.y", unsubscribed: true }) }, :patch, "/contacts/ana@x.y", nil, { "unsubscribed" => true }],
    "contacts.remove" => [->(c) { c.contacts.remove({ id: "c1" }) }, :delete, "/contacts/c1", nil, nil],
    "contacts.segments.list" => [->(c) { c.contacts.segments.list({ email: "ana@x.y" }) }, :get, "/contacts/ana@x.y/segments", nil, nil],
    "contacts.segments.add" => [->(c) { c.contacts.segments.add({ email: "ana@x.y", segment_id: "s1" }) }, :post, "/contacts/ana@x.y/segments/s1", nil, nil],
    "contacts.segments.remove" => [->(c) { c.contacts.segments.remove({ contact_id: "c1", segment_id: "s1" }) }, :delete, "/contacts/c1/segments/s1", nil, nil],
    "segments.create" => [->(c) { c.segments.create({ name: "Pro" }) }, :post, "/segments", nil, { "name" => "Pro" }],
    "segments.list" => [->(c) { c.segments.list }, :get, "/segments", nil, nil],
    "segments.get" => [->(c) { c.segments.get("s1") }, :get, "/segments/s1", nil, nil],
    "segments.update" => [->(c) { c.segments.update("s1", { name: "Team" }) }, :patch, "/segments/s1", nil, { "name" => "Team" }],
    "segments.remove" => [->(c) { c.segments.remove("s1") }, :delete, "/segments/s1", nil, nil],
    "segments.list_contacts" => [->(c) { c.segments.list_contacts("s1", { limit: 50 }) }, :get, "/segments/s1/contacts", { "limit" => "50" }, nil],
    "audiences alias" => [->(c) { c.audiences.get("s1") }, :get, "/segments/s1", nil, nil],
    "broadcasts.create" => [->(c) { c.broadcasts.create({ segment_id: "s1", from: "n@acme.com", send: true }) }, :post, "/broadcasts", nil, { "segment_id" => "s1", "from" => "n@acme.com", "send" => true }],
    "broadcasts.list" => [->(c) { c.broadcasts.list }, :get, "/broadcasts", nil, nil],
    "broadcasts.get" => [->(c) { c.broadcasts.get("b1") }, :get, "/broadcasts/b1", nil, nil],
    "broadcasts.update" => [->(c) { c.broadcasts.update("b1", { subject: "New" }) }, :patch, "/broadcasts/b1", nil, { "subject" => "New" }],
    "broadcasts.remove" => [->(c) { c.broadcasts.remove("b1") }, :delete, "/broadcasts/b1", nil, nil],
    "broadcasts.send now" => [->(c) { c.broadcasts.send("b1") }, :post, "/broadcasts/b1/send", nil, {}],
    "broadcasts.send later" => [->(c) { c.broadcasts.send("b1", { scheduled_at: "in 1 hour" }) }, :post, "/broadcasts/b1/send", nil, { "scheduled_at" => "in 1 hour" }],
    "broadcasts.cancel" => [->(c) { c.broadcasts.cancel("b1") }, :post, "/broadcasts/b1/cancel", nil, nil],
    "broadcasts.duplicate" => [->(c) { c.broadcasts.duplicate("b1") }, :post, "/broadcasts/b1/duplicate", nil, nil],
    "templates.create" => [->(c) { c.templates.create({ name: "Welcome", variables: [{ key: "N", type: "number", fallback_value: 14 }] }) }, :post, "/templates", nil,
                           { "name" => "Welcome", "variables" => [{ "key" => "N", "type" => "number", "fallback_value" => 14 }] }],
    "templates.list" => [->(c) { c.templates.list }, :get, "/templates", nil, nil],
    "templates.get" => [->(c) { c.templates.get("welcome") }, :get, "/templates/welcome", nil, nil],
    "templates.update" => [->(c) { c.templates.update("welcome", { subject: "New" }) }, :patch, "/templates/welcome", nil, { "subject" => "New" }],
    "templates.remove" => [->(c) { c.templates.remove("welcome") }, :delete, "/templates/welcome", nil, nil],
    "templates.publish" => [->(c) { c.templates.publish("welcome") }, :post, "/templates/welcome/publish", nil, nil],
    "templates.duplicate" => [->(c) { c.templates.duplicate("welcome") }, :post, "/templates/welcome/duplicate", nil, nil],
    "webhooks.create" => [->(c) { c.webhooks.create({ endpoint: "https://acme.com/wh", events: ["email.delivered"] }) }, :post, "/webhooks", nil,
                          { "endpoint" => "https://acme.com/wh", "events" => ["email.delivered"] }],
    "webhooks.list" => [->(c) { c.webhooks.list }, :get, "/webhooks", nil, nil],
    "webhooks.get" => [->(c) { c.webhooks.get("w1") }, :get, "/webhooks/w1", nil, nil],
    "webhooks.update" => [->(c) { c.webhooks.update("w1", { status: "disabled" }) }, :patch, "/webhooks/w1", nil, { "status" => "disabled" }],
    "webhooks.remove" => [->(c) { c.webhooks.remove("w1") }, :delete, "/webhooks/w1", nil, nil],
    "webhooks.rotate" => [->(c) { c.webhooks.rotate_signing_secret("w1") }, :post, "/webhooks/w1/signing-secret/rotate", nil, nil],
    "suppressions.add" => [->(c) { c.suppressions.add({ email: "x@y.z" }) }, :post, "/suppressions", nil, { "email" => "x@y.z" }],
    "suppressions.create" => [->(c) { c.suppressions.create({ email: "x@y.z" }) }, :post, "/suppressions", nil, { "email" => "x@y.z" }],
    "suppressions.list" => [->(c) { c.suppressions.list({ origin: "bounce" }) }, :get, "/suppressions", { "origin" => "bounce" }, nil],
    "suppressions.get" => [->(c) { c.suppressions.get("x@y.z") }, :get, "/suppressions/x@y.z", nil, nil],
    "suppressions.remove" => [->(c) { c.suppressions.remove("x@y.z") }, :delete, "/suppressions/x@y.z", nil, nil],
    "suppressions.batch.add" => [->(c) { c.suppressions.batch.add({ emails: ["a@x.y"] }) }, :post, "/suppressions/batch/add", nil, { "emails" => ["a@x.y"] }],
    "suppressions.batch.remove" => [->(c) { c.suppressions.batch.remove({ ids: ["i1"] }) }, :post, "/suppressions/batch/remove", nil, { "ids" => ["i1"] }]
  }

  cases.each do |name, (call, method, path, query, body)|
    it "calls #{name}" do
      seen = nil
      stub_request(:any, /api\.pidgely\.test/).with { |req| seen = req }.to_return(json(200, ok))
      expect(call.call(client)).to eq(ok)
      expect(seen.method).to eq(method)
      expect(seen.uri.path).to eq(path)
      expect(seen.uri.query_values || {}).to eq(query || {})
      if body.nil?
        expect(seen.body.to_s).to eq("")
        expect(seen.headers).not_to have_key("Content-Type")
      else
        expect(JSON.parse(seen.body)).to eq(body)
        expect(seen.headers["Content-Type"]).to eq("application/json")
      end
    end
  end

  it "sends an email with attachments and an idempotency key" do
    stub = stub_request(:post, "#{BASE}/emails").to_return(json(200, { id: "e1" }))
    result = client.emails.send(
      {
        from: "Acme <hello@acme.com>", to: "ana@example.org", subject: "Welcome to Acme", html: "<p>Your account is ready.</p>",
        attachments: [{ filename: "a.txt", content: [104, 105] }, { filename: "b.txt", content: StringIO.new("hi") },
                      { filename: "c.txt", content: "aGk=" }, { "filename" => "d.txt", "content" => [104, 105] }]
      },
      { idempotency_key: "welcome-ana" }
    )
    expect(result).to eq({ id: "e1" })
    expect(stub.with(headers: {
                       "Authorization" => "Bearer #{API_KEY}", "User-Agent" => "pidgely-ruby/#{Pidgely::VERSION}",
                       "Idempotency-Key" => "welcome-ana", "Accept" => "application/json"
                     }) { |req| JSON.parse(req.body)["attachments"].map { |a| a["content"] } == %w[aGk= aGk= aGk= aGk=] }).to have_been_requested
  end

  it "sends emails.create and batches with validation mode" do
    stub_request(:post, "#{BASE}/emails").to_return(json(200, { id: "e2" }))
    batch = stub_request(:post, "#{BASE}/emails/batch")
            .with(headers: { "x-batch-validation" => "permissive", "Idempotency-Key" => "b1" })
            .to_return(json(200, { data: [{ id: "a" }], errors: [{ index: 1, message: "bad" }] }))
    expect(client.emails.create({ to: "a@b.c" })).to eq({ id: "e2" })
    result = client.batch.send([{ to: "a@b.c" }, { to: "nope" }], { batch_validation: "permissive", idempotency_key: "b1" })
    expect(result[:errors].first[:index]).to eq(1)
    expect(batch).to have_been_requested
  end

  it "returns symbol-keyed hashes" do
    stub_request(:get, "#{BASE}/domains/d1").to_return(json(200, { id: "d1", records: [{ record: "DKIM", priority: 10 }] }))
    expect(client.domains.get("d1")[:records].first[:priority]).to eq(10)
  end

  [
    ["emails.get", ->(c) { c.emails.get("") }],
    ["emails.update", ->(c) { c.emails.update({ scheduled_at: "x" }) }],
    ["attachments.list", ->(c) { c.emails.attachments.list({}) }],
    ["attachments.get", ->(c) { c.emails.attachments.get({ email_id: "e" }) }],
    ["domains.update", ->(c) { c.domains.update({ tls: "enforced" }) }],
    ["contacts.get", ->(c) { c.contacts.get({}) }],
    ["contacts.get empty", ->(c) { c.contacts.get("") }],
    ["contacts.update", ->(c) { c.contacts.update({ first_name: "x" }) }],
    ["contacts.segments.add", ->(c) { c.contacts.segments.add({ email: "a@b.c" }) }],
    ["templates.publish", ->(c) { c.templates.publish(nil) }]
  ].each do |name, call|
    it "rejects #{name} without its required id" do
      expect { call.call(client) }.to raise_error(Pidgely::Error) { |e|
        expect(e.name).to eq("missing_required_field")
        expect(e.status_code).to be_nil
      }
      expect(a_request(:any, /pidgely/)).not_to have_been_made
    end
  end
end
