# frozen_string_literal: true

RSpec.describe "module API" do
  it "sends with Pidgely.api_key" do
    Pidgely.api_key = API_KEY
    Pidgely.base_url = BASE
    stub = stub_request(:post, "#{BASE}/emails").with(headers: { "Authorization" => "Bearer #{API_KEY}" }).to_return(json(200, { id: "e1" }))
    result = Pidgely::Emails.send({ from: "Acme <hello@acme.com>", to: "ana@example.org", subject: "Welcome to Acme", html: "<p>Your account is ready.</p>" })
    expect(result).to eq({ id: "e1" })
    expect(stub).to have_been_requested
  end

  it "exposes every resource, nested ones included" do
    Pidgely.api_key = API_KEY
    Pidgely.base_url = BASE
    paths = []
    stub_request(:any, /api\.pidgely\.test/).with { |req| paths << [req.method, req.uri.path] }.to_return(json(200, { ok: true }))
    Pidgely::Emails::Attachments.list({ email_id: "e1" })
    Pidgely::Contacts::Segments.add({ email: "a@b.c", segment_id: "s1" })
    Pidgely::Suppressions::Batch.add({ emails: ["a@b.c"] })
    Pidgely::ApiKeys.list
    Pidgely::Audiences.get("s1")
    Pidgely::Segments.list_contacts("s1", { limit: 10 })
    Pidgely::Domains.verify("d1")
    Pidgely::Batch.send([{ to: "a@b.c" }])
    Pidgely::Broadcasts.send("b1")
    Pidgely::Templates.publish("t1")
    Pidgely::Webhooks.rotate_signing_secret("w1")
    Pidgely::Contacts.get({ email: "a@b.c" })
    Pidgely::Suppressions.add({ email: "a@b.c" })
    Pidgely::Templates.preview("t1", { variables: { NAME: "Ana" } })
    Pidgely::Contacts.batch({ contacts: [{ email: "a@b.c" }], segment_id: "s1" })
    expect(paths).to eq([
                          [:get, "/emails/e1/attachments"], [:post, "/contacts/a@b.c/segments/s1"], [:post, "/suppressions/batch/add"],
                          [:get, "/api-keys"], [:get, "/segments/s1"], [:get, "/segments/s1/contacts"], [:post, "/domains/d1/verify"],
                          [:post, "/emails/batch"], [:post, "/broadcasts/b1/send"], [:post, "/templates/t1/publish"],
                          [:post, "/webhooks/w1/signing-secret/rotate"], [:get, "/contacts/a@b.c"], [:post, "/suppressions"],
                          [:post, "/templates/t1/preview"], [:post, "/contacts/batch"]
                        ])
  end

  it "rebuilds the client when the key changes" do
    Pidgely.base_url = BASE
    Pidgely.api_key = "pdg_first"
    first = Pidgely.client
    expect(Pidgely.client).to be(first)
    Pidgely.api_key = "pdg_second"
    stub = stub_request(:get, "#{BASE}/domains").with(headers: { "Authorization" => "Bearer pdg_second" }).to_return(json(200, {}))
    Pidgely::Domains.list
    expect(stub).to have_been_requested
    expect(Pidgely.client).not_to be(first)
  end

  it "uses PIDGELY_API_KEY" do
    ENV["PIDGELY_API_KEY"] = "pdg_env"
    ENV["PIDGELY_BASE_URL"] = BASE
    stub = stub_request(:get, "#{BASE}/domains").with(headers: { "Authorization" => "Bearer pdg_env" }).to_return(json(200, {}))
    Pidgely::Domains.list
    expect(stub).to have_been_requested
  end

  it "raises without a key" do
    expect { Pidgely::Emails.send({ to: "a@b.c" }) }.to raise_error(Pidgely::MissingApiKeyError)
  end
end
