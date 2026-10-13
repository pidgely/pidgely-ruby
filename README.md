<p align="center">
  <a href="https://pidgely.com"><img src="https://raw.githubusercontent.com/pidgely/.github/main/assets/banner.png" alt="Pidgely — Email API for developers" width="100%"></a>
</p>

<p align="center">
  <a href="https://github.com/pidgely/pidgely-ruby/actions/workflows/ci.yml"><img src="https://github.com/pidgely/pidgely-ruby/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://rubygems.org/gems/pidgely"><img src="https://img.shields.io/gem/v/pidgely?color=E2793F" alt="Gem"></a>
  <img src="https://img.shields.io/badge/ruby-%E2%89%A53.1-CC342D?logo=ruby&logoColor=white" alt="Ruby ≥ 3.1">
  <img src="https://img.shields.io/badge/dependencies-0-success" alt="Zero dependencies">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT"></a>
</p>

# pidgely-ruby

The official Ruby SDK for [Pidgely](https://pidgely.com), the Resend-compatible email API.

- **Drop-in for Resend.** The same module API as the `resend` gem (`Pidgely::Emails.send({...})`), plus `Pidgely::Client`. Migrating means changing a constant and a key.
- **Standard library only.** `net/http`, `json` and `openssl`; no runtime dependencies. Ruby 3.1+.
- **Built for production.** Idempotency keys, automatic retries with backoff that honour `Retry-After`, per-attempt timeouts.
- **Webhook verification.** Standard Webhooks (Svix) signatures, checked in constant time with timestamp tolerance.

Full documentation lives at **[docs.pidgely.com](https://docs.pidgely.com)**.

## Install

```sh
bundle add pidgely
# or: gem install pidgely
```

## Quickstart

Create an API key in the [dashboard](https://app.pidgely.com), verify a sending domain, then:

```ruby
require "pidgely"

Pidgely.api_key = ENV["PIDGELY_API_KEY"]

email = Pidgely::Emails.send({
  from: "Acme <hello@acme.com>",
  to: "ana@example.org",
  subject: "Welcome to Acme",
  html: "<p>Your account is ready.</p>"
})
puts email[:id]
```

Prefer an explicit client (several keys, dependency injection)? Every resource is also available on a client, with snake_case names:

```ruby
client = Pidgely::Client.new(api_key: ENV["PIDGELY_API_KEY"]) # or Client.new to read PIDGELY_API_KEY
client.emails.send({ ... })
```

### Configuration

```ruby
client = Pidgely::Client.new(
  api_key: "pdg_...",                   # default: PIDGELY_API_KEY
  base_url: "https://api.pidgely.com",  # default: PIDGELY_BASE_URL
  timeout: 30,                          # seconds per attempt (0 disables)
  max_retries: 2,                       # automatic retries, see below
  user_agent: "my-app/1.2.3",           # appended to pidgely-ruby/<version>
  headers: { "X-Team" => "growth" }     # sent with every request
)
```

The module API reads `Pidgely.api_key`, `Pidgely.base_url`, `Pidgely.timeout` and `Pidgely.max_retries` (falling back to the environment variables) and rebuilds its client when they change. In Rails, set them in `config/initializers/pidgely.rb`.

| Environment variable | Used for |
|---|---|
| `PIDGELY_API_KEY` | API key when none is given |
| `PIDGELY_BASE_URL` | Base URL when none is given (default `https://api.pidgely.com`) |

The API key never appears in `#inspect`, log output or raised errors.

### Errors

Methods return the API's JSON as hashes with symbol keys and raise on failure:

```ruby
begin
  Pidgely::Emails.send({ ... })
rescue Pidgely::ValidationError => e   # 400 / 422
  puts e.status_code, e.name, e.message
rescue Pidgely::RateLimitError => e    # 429
  puts e.headers["retry-after"]
rescue Pidgely::Error => e             # everything else
end
```

| Error | When |
|---|---|
| `Pidgely::ValidationError` | 400, 422 |
| `Pidgely::AuthenticationError` | 401 |
| `Pidgely::PermissionDeniedError` | 403 |
| `Pidgely::NotFoundError` | 404 |
| `Pidgely::ConflictError` | 409 (e.g. idempotency key reused with another body) |
| `Pidgely::RateLimitError` | 429 |
| `Pidgely::InternalServerError` | 5xx |
| `Pidgely::APIConnectionError` / `Pidgely::APITimeoutError` | no response (`status_code` is `nil`) |
| `Pidgely::MissingApiKeyError` | no API key configured |

All of them inherit from `Pidgely::Error`, which has `status_code`, `name` (machine-readable: `validation_error`, `not_found`, `invalid_api_key`, `rate_limit_exceeded`, `daily_quota_exceeded`, ...), `message` and `headers`.

Every method takes an optional last hash of request options: `idempotency_key`, `headers`, `timeout` and `max_retries`.

### Idempotency

```ruby
Pidgely::Emails.send(
  { from: "Acme <billing@acme.com>", to: "ana@example.com", subject: "Receipt #1042", html: html },
  { idempotency_key: "receipt-1042" }
)
```

The key is sent as `Idempotency-Key`. For 24 hours the API replays the stored response for the same key (the reply carries the header `idempotent-replayed: true`) and answers `409` when the body differs.

### Retries

Failed requests are retried up to `max_retries` times (default 2) with exponential backoff and jitter (0.5 s, 1 s, 2 s and so on, capped at 8 s), or after the delay given in `Retry-After`:

| Failure | Retried when |
|---|---|
| `408`, `429`, `500`, `502`, `503`, `504`, network error, timeout | `GET`, `PATCH`, `DELETE`, or a `POST` that has an `idempotency_key` |

**A `POST` without an idempotency key is never retried**, whatever the failure, because the email might already have been accepted. Quota errors (`daily_quota_exceeded`, `monthly_quota_exceeded`) are never retried, and a `Retry-After` longer than 60 seconds raises instead of waiting.

## Resources

Params are hashes with the API's snake_case keys (symbols or strings). Examples use the module API; with a client, replace `Pidgely::Emails` by `client.emails`, `Pidgely::ApiKeys` by `client.api_keys`, `Pidgely::Emails::Attachments` by `client.emails.attachments` and so on. List methods take `{ limit:, after:, before: }` (cursor pagination) and return `{ object: "list", has_more:, data: }`.

### Emails

```ruby
email = Pidgely::Emails.send({
  from: "Acme <hello@acme.com>",
  to: ["ana@example.com"],
  cc: "team@acme.com",
  reply_to: "support@acme.com",
  subject: "Your invoice",
  html: "<p>Invoice attached.</p>", # text is generated when omitted
  attachments: [
    { filename: "invoice.pdf", content: File.open("invoice.pdf", "rb") }, # IO, byte array or base64 string
    { filename: "logo.png", path: "https://acme.com/logo.png", content_id: "logo" } # <img src="cid:logo">
  ],
  tags: [{ name: "category", value: "billing" }],
  headers: { "X-Entity-Ref-ID" => "inv_1042" },
  scheduled_at: "tomorrow at 9am" # ISO 8601 or natural language, up to 30 days ahead
})

# Send a published template
Pidgely::Emails.send({
  from: "Acme <hello@acme.com>",
  to: "ana@example.com",
  template: { id: "welcome", variables: { NAME: "Ana", TRIAL_DAYS: 14 } }
})

Pidgely::Emails.get("4ef9a417-02e9-4d39-ad75-9611e0fcc33c") # includes :last_event
Pidgely::Emails.list({ limit: 20 })
Pidgely::Emails.update({ id: email_id, scheduled_at: "in 2 hours" }) # reschedule
Pidgely::Emails.cancel(email_id) # cancel a scheduled email
Pidgely::Emails::Attachments.list({ email_id: email_id })
Pidgely::Emails::Attachments.get({ email_id: email_id, id: attachment_id }) # signed :download_url, valid for 1 hour
```

### Batch

```ruby
result = Pidgely::Batch.send(
  [
    { from: "Acme <hello@acme.com>", to: "ana@example.com", subject: "Hi Ana", html: "<p>Hi</p>" },
    { from: "Acme <hello@acme.com>", to: "bob@example.com", subject: "Hi Bob", html: "<p>Hi</p>" }
  ],
  { idempotency_key: "digest-2026-10-12", batch_validation: "permissive" }
)
# result[:data] → [{ id: }]; with "permissive", result[:errors] → [{ index:, message: }]
```

Up to 100 emails per request. `strict` (the default) sends all of them or none. `permissive` sends the valid ones and reports the invalid ones.

### Domains

```ruby
domain = Pidgely::Domains.create({ name: "acme.com", custom_return_path: "bounces", tls: "opportunistic" })
domain[:records].each { |r| puts "#{r[:type]} #{r[:name]} #{r[:value]}" } # DKIM TXT, return-path MX + SPF TXT, DMARC

Pidgely::Domains.verify(domain[:id]) # check DNS now
Pidgely::Domains.get(domain[:id])    # :status is not_started | pending | verified | failed
Pidgely::Domains.list
Pidgely::Domains.update({ id: domain[:id], tls: "enforced" })
Pidgely::Domains.remove(domain[:id])
```

### API keys

```ruby
key = Pidgely::ApiKeys.create({ name: "Production", permission: "sending_access", domain_id: domain_id })
puts key[:token] # pdg_…, shown only once
Pidgely::ApiKeys.list
Pidgely::ApiKeys.update(key[:id], { name: "Production (web)" })
Pidgely::ApiKeys.remove(key[:id])
```

### Contacts

```ruby
Pidgely::Contacts.create({
  email: "ana@example.com",
  first_name: "Ana",
  last_name: "Lima",
  properties: { plan: "pro", seats: 5 },
  segments: [{ id: segment_id }]
})
Pidgely::Contacts.list({ segment_id: segment_id, limit: 100 })
Pidgely::Contacts.get({ email: "ana@example.com" }) # or get("ana@example.com") / get({ id: ... })
Pidgely::Contacts.update({ email: "ana@example.com", unsubscribed: true }) # kept in sync with the suppression list
Pidgely::Contacts.remove({ email: "ana@example.com" })

# Upsert up to 1,000 contacts; invalid rows are reported with their index instead of failing the request
result = Pidgely::Contacts.batch({
  contacts: [
    { email: "ana@example.com", first_name: "Ana" },
    { email: "bruno@example.com", properties: { plan: "team" } }
  ],
  segment_id: segment_id # optional: added to every row
})
# result[:data] → [{ index:, id: }], result[:errors] → [{ index:, message: }]

Pidgely::Contacts::Segments.list({ email: "ana@example.com" })
Pidgely::Contacts::Segments.add({ email: "ana@example.com", segment_id: segment_id })
Pidgely::Contacts::Segments.remove({ contact_id: contact_id, segment_id: segment_id })
```

### Segments (and legacy audiences)

```ruby
segment = Pidgely::Segments.create({ name: "Pro customers" })
Pidgely::Segments.list
Pidgely::Segments.get(segment[:id])
Pidgely::Segments.update(segment[:id], { name: "Pro & Team customers" })
Pidgely::Segments.list_contacts(segment[:id], { limit: 50 })
Pidgely::Segments.remove(segment[:id])
```

`Pidgely::Audiences` (and `client.audiences`) is a deprecated alias of `Segments`, kept for Resend compatibility. `Contacts.create/list/get/update/remove` also take a legacy `audience_id`.

### Broadcasts

```ruby
broadcast = Pidgely::Broadcasts.create({
  segment_id: segment_id,
  from: "Acme News <news@acme.com>",
  subject: "What’s new in October",
  preview_text: "Three features you asked for",
  html: '<p>Hi {{{FIRST_NAME|there}}},</p>…<a href="{{{PIDGELY_UNSUBSCRIBE_URL}}}">Unsubscribe</a>',
  name: "October newsletter"
})

Pidgely::Broadcasts.send(broadcast[:id], { scheduled_at: "tomorrow at 10am" }) # omit to send now
Pidgely::Broadcasts.cancel(broadcast[:id])
Pidgely::Broadcasts.duplicate(broadcast[:id])
Pidgely::Broadcasts.update(broadcast[:id], { subject: "New subject" }) # drafts only
Pidgely::Broadcasts.get(broadcast[:id]) # includes per-status :stats
Pidgely::Broadcasts.list
Pidgely::Broadcasts.remove(broadcast[:id])
```

Pass `send: true` (with an optional `scheduled_at`) to `create` to send without a separate call. Every broadcast message includes RFC 8058 one-click unsubscribe. Personalisation supports `{{{FIRST_NAME|fallback}}}`, `{{{LAST_NAME}}}`, `{{{EMAIL}}}`, `{{{contact.<property>}}}` and `{{{RESEND_UNSUBSCRIBE_URL}}}` / `{{{PIDGELY_UNSUBSCRIBE_URL}}}`.

### Templates

```ruby
template = Pidgely::Templates.create({
  name: "Welcome",
  alias: "welcome",
  from: "Acme <hello@acme.com>",
  subject: "Welcome, {{{NAME}}}!",
  html: "<p>Hi {{{NAME}}}, your trial lasts {{{TRIAL_DAYS}}} days.</p>",
  variables: [
    { key: "NAME", type: "string", fallback_value: "there" },
    { key: "TRIAL_DAYS", type: "number", fallback_value: 14 }
  ]
})
Pidgely::Templates.publish(template[:id]) # the published version is what `template:` sends

# Render the draft without sending; missing_variables lists variables with no value and no fallback
preview = Pidgely::Templates.preview("welcome", { variables: { NAME: "Ana", TRIAL_DAYS: 30 } })

Pidgely::Templates.get("welcome") # by id or alias (draft)
Pidgely::Templates.update("welcome", { subject: "Welcome aboard, {{{NAME}}}!" })
Pidgely::Templates.duplicate("welcome")
Pidgely::Templates.list
Pidgely::Templates.remove("welcome")
```

### Webhooks

```ruby
webhook = Pidgely::Webhooks.create({
  endpoint: "https://acme.com/webhooks/pidgely",
  events: ["email.delivered", "email.bounced", "email.complained"]
})
puts webhook[:signing_secret] # whsec_…, store it to verify deliveries

Pidgely::Webhooks.list
Pidgely::Webhooks.get(webhook[:id])
Pidgely::Webhooks.update(webhook[:id], { status: "disabled" })
Pidgely::Webhooks.rotate_signing_secret(webhook[:id])
Pidgely::Webhooks.remove(webhook[:id])
```

Events: `email.sent`, `email.delivered`, `email.delivery_delayed`, `email.bounced`, `email.complained`, `email.failed`, `email.suppressed`, `domain.updated`, `contact.created`, `contact.updated`, `contact.deleted`.

### Suppressions

```ruby
Pidgely::Suppressions.add({ email: "noreply@example.com" })
Pidgely::Suppressions.list({ origin: "bounce" }) # bounce | complaint | manual | unsubscribe
Pidgely::Suppressions.get("noreply@example.com") # by id or email
Pidgely::Suppressions.remove("noreply@example.com")
Pidgely::Suppressions::Batch.add({ emails: ["a@example.com", "b@example.com"] }) # up to 100
Pidgely::Suppressions::Batch.remove({ emails: ["a@example.com"] })
```

## Verifying webhooks

Pidgely signs every delivery with the [Standard Webhooks](https://www.standardwebhooks.com) scheme. The same values are sent under both the `webhook-*` and `svix-*` header names. `Pidgely::Webhooks.verify` checks the HMAC-SHA256 signature in constant time, rejects timestamps more than 5 minutes from now, and returns the parsed event. Pass the **raw** request body. No API key is needed.

```ruby
# Rails
class PidgelyWebhooksController < ActionController::API
  def create
    event = Pidgely::Webhooks.verify(
      payload: request.raw_post,
      headers: request.headers.to_h, # Rack env keys such as HTTP_WEBHOOK_ID work too
      webhook_secret: ENV.fetch("PIDGELY_WEBHOOK_SECRET")
    )
    if event[:type] == "email.bounced"
      # event[:data][:email_id], event[:data][:to], ...
    end
    head :no_content
  rescue Pidgely::WebhookVerificationError
    head :bad_request
  end
end
```

`Pidgely::Webhook.verify`, `Pidgely.verify_webhook` and `client.webhooks.verify` are the same check. Set a different window with `tolerance:` (seconds).

## Migrating from Resend

Pidgely serves the Resend REST API at the same paths, and this SDK mirrors the `resend` gem:

```diff
- require "resend"
- Resend.api_key = ENV["RESEND_API_KEY"]
- Resend::Emails.send({ from:, to:, subject:, html: })
+ require "pidgely"
+ Pidgely.api_key = ENV["PIDGELY_API_KEY"]
+ Pidgely::Emails.send({ from:, to:, subject:, html: })
```

1. Replace `gem "resend"` with `gem "pidgely"` and run `bundle install`.
2. Rename `Resend` to `Pidgely` and swap `re_…` for your `pdg_…` key.
3. Verify your domain in Pidgely and publish the DNS records it returns.
4. If you verify webhooks, use `Pidgely::Webhooks.verify` with the `whsec_…` secret from your Pidgely webhook.

Params use the same snake_case keys and the resources keep their names (`Emails`, `Batch`, `Domains`, `ApiKeys`, `Contacts`, `Segments`/`Audiences`, `Broadcasts`, `Templates`, `Webhooks`). Errors are `Pidgely::Error` subclasses. Pidgely additions include `Emails::Attachments`, `ApiKeys.update`, `Segments.update/list_contacts`, `Contacts.batch`, `Templates.preview`, `Broadcasts.cancel/duplicate`, `Suppressions`, the `stream` field on emails and built-in retries. Some Resend features are not supported yet: open/click tracking, topics, inbound email, automations, events and logs. See the migration guide at [docs.pidgely.com](https://docs.pidgely.com) for the full list.

## Development

```sh
bundle install
bundle exec rubocop
bundle exec rspec   # WebMock, no network; coverage in coverage/
gem build pidgely.gemspec
```

### Publishing

Releases are published from GitHub Actions ([`release.yml`](.github/workflows/release.yml)) when a `v*` tag is pushed. The workflow checks that the tag matches `Pidgely::VERSION`, runs RuboCop and the specs, builds the gem, pushes it to RubyGems and creates the GitHub release.

1. One-time setup: create a RubyGems API key with the *Push rubygem* scope (limited to the `pidgely` gem once it exists) and save it as the repository secret `RUBYGEMS_API_KEY`. The RubyGems account's MFA level must allow API-key pushes ("UI and gem signin").
2. Update `CHANGELOG.md` and `lib/pidgely/version.rb`, commit, wait for CI on `main`, then `git tag v0.2.0 && git push origin v0.2.0`.

## Links

- Documentation: https://docs.pidgely.com
- API reference (OpenAPI 3.1): [`openapi/pidgely.yaml`](openapi/pidgely.yaml)
- Other SDKs: [Node.js](https://github.com/pidgely/pidgely-node) · [Python](https://github.com/pidgely/pidgely-python) · [Go](https://github.com/pidgely/pidgely-go) · [PHP](https://github.com/pidgely/pidgely-php)
- Security: see [SECURITY.md](https://github.com/pidgely/.github/blob/main/SECURITY.md)

## License

[MIT](LICENSE) © Caotec Serviços em Tecnologia Ltda
