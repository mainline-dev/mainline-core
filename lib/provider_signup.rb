# frozen_string_literal: true

require 'base64'
require 'json'
require_relative 'signed_state'

# Signing up through a sign-in provider such as Google, GitHub or GitLab.
# Until the address is confirmed the sign-up is only pending: it travels in
# the link sent to that address, signed, with the name, the address and how
# the provider knows the person, and never the provider's own token. Once
# confirmed, the person is made with their address already verified.
module ProviderSignup
  LINK = 'oauth-verify:'
  CARRIED = %w[name email provider uid].freeze

  # The token for the link that confirms a pending sign-up's address.
  def self.link_token(pending)
    data = CARRIED.to_h { |key| [key, pending[key]] }
    SignedState.generate("#{LINK}#{Base64.urlsafe_encode64(JSON.generate(data), padding: false)}")
  end

  # Whether a token is such a link, signed by Mainline and still in date.
  def self.link?(token)
    SignedState.verify(token).to_s.start_with?(LINK)
  end

  # The pending sign-up a link carries, or nil when it is not such a link or
  # cannot be read.
  def self.pending_from(token)
    return unless link?(token)

    JSON.parse(Base64.urlsafe_decode64(SignedState.verify(token).delete_prefix(LINK)))
  rescue JSON::ParserError, ArgumentError
    nil
  end

  # The person a confirmed sign-up makes, with the identity their provider
  # knows them by.
  def self.create(pending, email:, now:)
    DB.transaction do
      person = Person.create(name: pending['name'], email: email, email_verified_at: now)
      PersonIdentity.create(person_id: person.id, provider: pending['provider'], provider_subject: pending['uid'], email: email)
      person
    end
  end
end
