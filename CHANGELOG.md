# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-12

### Added

- First release of the official Pidgely SDK for Ruby (3.1+), using only the standard library (`net/http`, `json`, `openssl`).
- Resend-style module API (`Pidgely.api_key = ...; Pidgely::Emails.send({...})`) and `Pidgely::Client.new(api_key:)`, both reading `PIDGELY_API_KEY` / `PIDGELY_BASE_URL`.
- Resources: `Emails` (with `Attachments`), `Batch`, `Domains`, `ApiKeys`, `Contacts` (with `Segments`), `Segments` (with the `Audiences` alias), `Broadcasts`, `Templates`, `Webhooks` and `Suppressions` (with `Batch`). Responses are hashes with symbol keys.
- Errors for every failure: `Pidgely::Error` and `ValidationError`, `AuthenticationError`, `PermissionDeniedError`, `NotFoundError`, `ConflictError`, `RateLimitError`, `InternalServerError`, `APIConnectionError`, `APITimeoutError`, `MissingApiKeyError`.
- `idempotency_key` request option (`Idempotency-Key` header), plus per-request `headers`, `timeout` and `max_retries`.
- Automatic retries with exponential backoff and jitter on 408/429/5xx/network errors, honouring `Retry-After`. A POST is only retried when it carries an idempotency key, so an email is never sent twice.
- Per-attempt timeouts and the `pidgely-ruby/<version>` user agent. The API key never appears in `#inspect`, logs or errors.
- `Pidgely::Webhook.verify` / `Pidgely::Webhooks.verify` for Standard Webhooks (Svix) signatures, with constant-time comparison and a 5-minute timestamp tolerance.

[Unreleased]: https://github.com/pidgely/pidgely-ruby/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/pidgely/pidgely-ruby/releases/tag/v0.1.0
