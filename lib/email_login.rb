# frozen_string_literal: true

require 'bcrypt'
require 'digest'
require_relative 'signed_state'

# Signing in with an email address: by its password, or by a login link sent
# to it. A link signs its person in once; used again, it signs in nobody.
module EmailLogin
  LINK = 'magic:'

  # The person this address and password sign in, or nil.
  def self.person(email:, password:)
    email = email.to_s.strip.downcase
    return if email.empty?

    person = Person.find_by_email(email)
    return unless person

    identity = PersonIdentity.where(person_id: person.id, provider: 'email').exclude(password_digest: nil).first
    person if identity && BCrypt::Password.new(identity.password_digest) == password.to_s
  end

  # The person a login link is for, or nil when it is not one Mainline signed
  # or has run out.
  def self.person_for_link(token)
    value = SignedState.verify(token)
    Person[value.delete_prefix(LINK)] if value&.start_with?(LINK)
  end

  # Uses a login link: the person it signs in, or nil when it is not a good
  # one or was the last one they used.
  def self.use_link(token)
    person = person_for_link(token)
    claim(person, token) if person
  end

  # Marks the link as the last one its person used: the person, or nil when
  # it already was. Checking and marking are one statement, so two requests
  # with the same link at the same moment cannot both sign in.
  def self.claim(person, token)
    used = Digest::SHA256.hexdigest(token)
    unused = Person.where(id: person.id).where(Sequel.lit('last_magic_token_hash IS DISTINCT FROM ?', used))
    person if unused.update(last_magic_token_hash: used) == 1
  end
end
