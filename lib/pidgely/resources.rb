# frozen_string_literal: true

require "stringio"

module Pidgely
  # API resources. Use them through a {Pidgely::Client} (+client.emails+) or the
  # module API (+Pidgely::Emails.send+). Params are hashes with the API's snake_case
  # keys (symbols or strings); responses are hashes with symbol keys.
  module Resources
    # @api private
    class Base
      def initialize(transport)
        @transport = transport
      end

      def inspect
        "#<#{self.class.name}>"
      end

      private

      def get(path, query: nil, options: {})
        @transport.request(:get, path, query: query, options: options)
      end

      def post(path, body: nil, options: {}, headers: {})
        @transport.request(:post, path, body: body, options: options, headers: headers)
      end

      def patch(path, body:, options: {})
        @transport.request(:patch, path, body: body, options: options)
      end

      def delete(path, options: {})
        @transport.request(:delete, path, options: options)
      end

      def seg(value) = Util.seg(value)
      def id!(value, name = "id") = Util.id!(value, name)
      def fetch(params, *keys) = Util.fetch(params, *keys)
      def without(params, *keys) = Util.without(params, *keys)
      def page(params, *extra) = Util.page(params, *extra)
    end

    # Stored attachments of sent emails.
    class EmailAttachments < Base
      # GET /emails/{email_id}/attachments
      def list(params, options = {})
        @transport.request(:get, "/emails/#{seg(fetch(params, :email_id))}/attachments", query: page(params), options: options)
      end

      # GET /emails/{email_id}/attachments/{id}: includes a signed download_url valid for 1 hour.
      def get(params, options = {})
        super("/emails/#{seg(fetch(params, :email_id))}/attachments/#{seg(fetch(params, :id))}", options: options)
      end
    end

    # Send and manage emails.
    class Emails < Base
      # Stored attachments of sent emails.
      attr_reader :attachments

      def initialize(transport)
        super
        @attachments = EmailAttachments.new(transport)
      end

      # POST /emails. Pass { idempotency_key: "..." } as options to make it safe to retry.
      def send(params, options = {})
        post("/emails", body: Emails.body(params), options: options)
      end
      alias create send

      # GET /emails/{id}: includes last_event.
      def get(id, options = {})
        super("/emails/#{id!(id)}", options: options)
      end

      # GET /emails
      def list(params = {}, options = {})
        get_list("/emails", params, options)
      end

      # PATCH /emails/{id}: reschedule a scheduled email ({ id:, scheduled_at: }).
      def update(params, options = {})
        patch("/emails/#{seg(fetch(params, :id))}", body: without(params, :id), options: options)
      end

      # POST /emails/{id}/cancel: cancel a scheduled email.
      def cancel(id, options = {})
        post("/emails/#{id!(id)}/cancel", options: options)
      end

      # Encodes attachment content given as a byte array or an IO as base64.
      # @api private
      def self.body(params)
        params = params.to_h
        attachments = params[:attachments] || params["attachments"]
        return params unless attachments.is_a?(Array)

        key = params.key?(:attachments) ? :attachments : "attachments"
        params.merge(key => attachments.map { |a| encode_attachment(a) })
      end

      # @api private
      def self.encode_attachment(attachment)
        return attachment unless attachment.is_a?(Hash)

        key = attachment.key?(:content) ? :content : "content"
        content = attachment[key]
        case content
        when Array then attachment.merge(key => [content.pack("C*")].pack("m0"))
        when IO, StringIO then attachment.merge(key => [content.read].pack("m0"))
        else attachment
        end
      end

      private

      def get_list(path, params, options)
        @transport.request(:get, path, query: page(params), options: options)
      end
    end

    # Send up to 100 emails in one request.
    class Batch < Base
      # POST /emails/batch. Options also take batch_validation ("strict" or "permissive").
      def send(emails, options = {})
        options = Util.symbolize(options || {})
        headers = options[:batch_validation] ? { "x-batch-validation" => options[:batch_validation].to_s } : {}
        post("/emails/batch", body: emails.map { |e| Emails.body(e) }, options: options, headers: headers)
      end
      alias create send
    end

    # Sending domains and their DNS records.
    class Domains < Base
      # POST /domains: returns the DNS records to publish.
      def create(params, options = {})
        post("/domains", body: params, options: options)
      end

      # GET /domains/{id}: includes the DNS records and their status.
      def get(id, options = {})
        super("/domains/#{id!(id)}", options: options)
      end

      # GET /domains
      def list(params = {}, options = {})
        @transport.request(:get, "/domains", query: page(params), options: options)
      end

      # PATCH /domains/{id} ({ id:, tls: ... }).
      def update(params, options = {})
        patch("/domains/#{seg(fetch(params, :id))}", body: without(params, :id), options: options)
      end

      # DELETE /domains/{id}
      def remove(id, options = {})
        delete("/domains/#{id!(id)}", options: options)
      end

      # POST /domains/{id}/verify: check the DNS records now.
      def verify(id, options = {})
        post("/domains/#{id!(id)}/verify", options: options)
      end
    end

    # API keys.
    class ApiKeys < Base
      # POST /api-keys: the token is only returned once.
      def create(params, options = {})
        post("/api-keys", body: params, options: options)
      end

      # GET /api-keys
      def list(params = {}, options = {})
        @transport.request(:get, "/api-keys", query: page(params), options: options)
      end

      # PATCH /api-keys/{id}: rename a key.
      def update(id, params, options = {})
        patch("/api-keys/#{id!(id)}", body: params, options: options)
      end

      # DELETE /api-keys/{id}: revoke a key.
      def remove(id, options = {})
        delete("/api-keys/#{id!(id)}", options: options)
      end
    end

    # Segment memberships of a contact, selected by email, id or contact_id.
    class ContactSegments < Base
      # GET /contacts/{id_or_email}/segments
      def list(params, options = {})
        @transport.request(:get, "/contacts/#{key(params)}/segments", query: page(params), options: options)
      end

      # POST /contacts/{id_or_email}/segments/{segment_id}
      def add(params, options = {})
        post("/contacts/#{key(params)}/segments/#{seg(fetch(params, :segment_id))}", options: options)
      end

      # DELETE /contacts/{id_or_email}/segments/{segment_id}
      def remove(params, options = {})
        delete("/contacts/#{key(params)}/segments/#{seg(fetch(params, :segment_id))}", options: options)
      end

      private

      def key(params)
        seg(fetch(params, :contact_id, :id, :email))
      end
    end

    # Contacts, addressed by id or email.
    class Contacts < Base
      # Segment memberships of a contact.
      attr_reader :segments

      def initialize(transport)
        super
        @segments = ContactSegments.new(transport)
      end

      # POST /contacts: creates the contact or updates the one with the same email.
      # A legacy audience_id uses /audiences/{id}/contacts.
      def create(params, options = {})
        post(base(params), body: without(params, :audience_id), options: options)
      end

      # POST /contacts/batch: creates or updates up to 1,000 contacts by email
      # ({ contacts: [...], segment_id: }). Each row is saved independently; invalid rows
      # are reported in errors with their index.
      def batch(params, options = {})
        post("/contacts/batch", body: params, options: options)
      end

      # GET /contacts, optionally filtered by segment_id.
      def list(params = {}, options = {})
        @transport.request(:get, "/contacts", query: page(params, :segment_id, :audience_id), options: options)
      end

      # GET /contacts/{id_or_email}: pass an id, an email, { id: } or { email: }.
      def get(contact, options = {})
        super(path(contact), options: options)
      end

      # PATCH /contacts/{id_or_email}: unsubscribed stays in sync with the suppression list.
      def update(params, options = {})
        patch(path(params), body: without(params, :id, :email, :audience_id), options: options)
      end

      # DELETE /contacts/{id_or_email}
      def remove(contact, options = {})
        delete(path(contact), options: options)
      end

      private

      def base(params)
        audience = params[:audience_id] || params["audience_id"]
        audience.to_s.empty? ? "/contacts" : "/audiences/#{seg(audience)}/contacts"
      end

      def path(contact)
        return "/contacts/#{id!(contact, "id or email")}" unless contact.is_a?(Hash)

        "#{base(contact)}/#{seg(fetch(contact, :id, :email))}"
      end
    end

    # Segments of contacts (also available as the legacy audiences).
    class Segments < Base
      # POST /segments
      def create(params, options = {})
        post("/segments", body: params, options: options)
      end

      # GET /segments
      def list(params = {}, options = {})
        @transport.request(:get, "/segments", query: page(params), options: options)
      end

      # GET /segments/{id}
      def get(id, options = {})
        super("/segments/#{id!(id)}", options: options)
      end

      # PATCH /segments/{id}: rename a segment.
      def update(id, params, options = {})
        patch("/segments/#{id!(id)}", body: params, options: options)
      end

      # DELETE /segments/{id}
      def remove(id, options = {})
        delete("/segments/#{id!(id)}", options: options)
      end

      # GET /segments/{id}/contacts
      def list_contacts(id, params = {}, options = {})
        @transport.request(:get, "/segments/#{id!(id)}/contacts", query: page(params), options: options)
      end
    end

    # Marketing broadcasts.
    class Broadcasts < Base
      # POST /broadcasts: creates a draft, or sends it with send: true.
      def create(params, options = {})
        post("/broadcasts", body: params, options: options)
      end

      # GET /broadcasts
      def list(params = {}, options = {})
        @transport.request(:get, "/broadcasts", query: page(params), options: options)
      end

      # GET /broadcasts/{id}: includes per-status stats.
      def get(id, options = {})
        super("/broadcasts/#{id!(id)}", options: options)
      end

      # PATCH /broadcasts/{id}: drafts only.
      def update(id, params, options = {})
        patch("/broadcasts/#{id!(id)}", body: params, options: options)
      end

      # DELETE /broadcasts/{id}
      def remove(id, options = {})
        delete("/broadcasts/#{id!(id)}", options: options)
      end

      # POST /broadcasts/{id}/send: now, or at scheduled_at.
      def send(id, params = {}, options = {})
        post("/broadcasts/#{id!(id)}/send", body: params || {}, options: options)
      end

      # POST /broadcasts/{id}/cancel: cancel a scheduled or queued broadcast.
      def cancel(id, options = {})
        post("/broadcasts/#{id!(id)}/cancel", options: options)
      end

      # POST /broadcasts/{id}/duplicate: copy as a new draft.
      def duplicate(id, options = {})
        post("/broadcasts/#{id!(id)}/duplicate", options: options)
      end
    end

    # Templates, addressed by id or alias.
    class Templates < Base
      # POST /templates: creates a draft; publish it with #publish.
      def create(params, options = {})
        post("/templates", body: params, options: options)
      end

      # GET /templates
      def list(params = {}, options = {})
        @transport.request(:get, "/templates", query: page(params), options: options)
      end

      # GET /templates/{id_or_alias}: the current draft.
      def get(id_or_alias, options = {})
        super("/templates/#{id!(id_or_alias)}", options: options)
      end

      # PATCH /templates/{id_or_alias}: updates the draft.
      def update(id_or_alias, params, options = {})
        patch("/templates/#{id!(id_or_alias)}", body: params, options: options)
      end

      # DELETE /templates/{id_or_alias}
      def remove(id_or_alias, options = {})
        delete("/templates/#{id!(id_or_alias)}", options: options)
      end

      # POST /templates/{id_or_alias}/publish: the published version is what `template` sends.
      def publish(id_or_alias, options = {})
        post("/templates/#{id!(id_or_alias)}/publish", options: options)
      end

      # POST /templates/{id_or_alias}/preview: renders the draft with { variables: {...} }
      # without sending. missing_variables lists the variables with neither a value nor a fallback.
      def preview(id_or_alias, params = {}, options = {})
        post("/templates/#{id!(id_or_alias)}/preview", body: params || {}, options: options)
      end

      # POST /templates/{id_or_alias}/duplicate
      def duplicate(id_or_alias, options = {})
        post("/templates/#{id!(id_or_alias)}/duplicate", options: options)
      end
    end

    # Webhook endpoints.
    class Webhooks < Base
      # POST /webhooks: returns the signing_secret (whsec_...).
      def create(params, options = {})
        post("/webhooks", body: params, options: options)
      end

      # GET /webhooks
      def list(params = {}, options = {})
        @transport.request(:get, "/webhooks", query: page(params), options: options)
      end

      # GET /webhooks/{id}
      def get(id, options = {})
        super("/webhooks/#{id!(id)}", options: options)
      end

      # PATCH /webhooks/{id}
      def update(id, params, options = {})
        patch("/webhooks/#{id!(id)}", body: params, options: options)
      end

      # DELETE /webhooks/{id}
      def remove(id, options = {})
        delete("/webhooks/#{id!(id)}", options: options)
      end

      # POST /webhooks/{id}/signing-secret/rotate
      def rotate_signing_secret(id, options = {})
        post("/webhooks/#{id!(id)}/signing-secret/rotate", options: options)
      end

      # Verifies a delivery; see {Pidgely::Webhook.verify}. Needs no API key.
      def verify(**kwargs)
        Webhook.verify(**kwargs)
      end
    end

    # Bulk suppression changes (up to 100 addresses).
    class SuppressionsBatch < Base
      # POST /suppressions/batch/add ({ emails: [...] }).
      def add(params, options = {})
        post("/suppressions/batch/add", body: params, options: options)
      end

      # POST /suppressions/batch/remove ({ emails: [...] } and/or { ids: [...] }).
      def remove(params, options = {})
        post("/suppressions/batch/remove", body: params, options: options)
      end
    end

    # The suppression list.
    class Suppressions < Base
      # Bulk changes.
      attr_reader :batch

      def initialize(transport)
        super
        @batch = SuppressionsBatch.new(transport)
      end

      # POST /suppressions: stop sending to an address.
      def add(params, options = {})
        post("/suppressions", body: params, options: options)
      end
      alias create add

      # GET /suppressions, optionally filtered by origin.
      def list(params = {}, options = {})
        @transport.request(:get, "/suppressions", query: page(params, :origin), options: options)
      end

      # GET /suppressions/{id_or_email}
      def get(id_or_email, options = {})
        super("/suppressions/#{id!(id_or_email)}", options: options)
      end

      # DELETE /suppressions/{id_or_email}: allow sending to the address again.
      def remove(id_or_email, options = {})
        delete("/suppressions/#{id!(id_or_email)}", options: options)
      end
    end
  end
end
