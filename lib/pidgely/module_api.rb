# frozen_string_literal: true

module Pidgely
  # Builds the Resend-style module API (Pidgely::Emails.send ...), which forwards to the
  # resources of Pidgely.client.
  #
  # @api private
  module ModuleAPI
    def self.define(mod, path, *methods)
      methods.each do |name|
        mod.define_singleton_method(name) do |*args, **kwargs, &block|
          target = path.split(".").reduce(Pidgely.client) { |obj, part| obj.public_send(part) }
          target.public_send(name, *args, **kwargs, &block)
        end
      end
    end
  end

  # Send and manage emails: Pidgely::Emails.send({ from:, to:, subject:, html: }).
  module Emails
    ModuleAPI.define(self, "emails", :send, :create, :get, :list, :update, :cancel)

    # Stored attachments of sent emails.
    module Attachments
      ModuleAPI.define(self, "emails.attachments", :list, :get)
    end
  end

  # Send up to 100 emails in one request.
  module Batch
    ModuleAPI.define(self, "batch", :send, :create)
  end

  # Sending domains and their DNS records.
  module Domains
    ModuleAPI.define(self, "domains", :create, :get, :list, :update, :remove, :verify)
  end

  # API keys.
  module ApiKeys
    ModuleAPI.define(self, "api_keys", :create, :list, :update, :remove)
  end

  # Contacts, addressed by id or email.
  module Contacts
    ModuleAPI.define(self, "contacts", :create, :list, :get, :update, :remove)

    # Segment memberships of a contact.
    module Segments
      ModuleAPI.define(self, "contacts.segments", :list, :add, :remove)
    end
  end

  # Segments of contacts.
  module Segments
    ModuleAPI.define(self, "segments", :create, :list, :get, :update, :remove, :list_contacts)
  end

  # Deprecated alias of Segments, kept for Resend compatibility.
  module Audiences
    ModuleAPI.define(self, "segments", :create, :list, :get, :update, :remove, :list_contacts)
  end

  # Marketing broadcasts.
  module Broadcasts
    ModuleAPI.define(self, "broadcasts", :create, :list, :get, :update, :remove, :send, :cancel, :duplicate)
  end

  # Templates, addressed by id or alias.
  module Templates
    ModuleAPI.define(self, "templates", :create, :list, :get, :update, :remove, :publish, :duplicate)
  end

  # Webhook endpoints. Webhooks.verify needs no API key.
  module Webhooks
    ModuleAPI.define(self, "webhooks", :create, :list, :get, :update, :remove, :rotate_signing_secret)

    def self.verify(**kwargs)
      Webhook.verify(**kwargs)
    end
  end

  # The suppression list.
  module Suppressions
    ModuleAPI.define(self, "suppressions", :add, :create, :list, :get, :remove)

    # Bulk changes (up to 100 addresses).
    module Batch
      ModuleAPI.define(self, "suppressions.batch", :add, :remove)
    end
  end
end
