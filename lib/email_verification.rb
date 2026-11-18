# frozen_string_literal: true

require_relative 'send_verification_email'
require_relative 'signed_state'

# Proving an email address belongs to the person who signed up with it: a
# link sent to the address, which counts it as verified once confirmed. A
# development install sends no mail, so there the link would only be one to
# click on the same screen, and the address counts as verified straight away;
# everywhere else the link is required.
module EmailVerification
  LINK = 'verify:'

  def self.required?
    ENV.fetch('RACK_ENV', nil) != 'development'
  end

  # Asks a new person to prove their address, or counts it as verified where
  # that is not required. What sending the link gave back, if it was sent.
  def self.ask(person, now:)
    return SendVerificationEmail.call(person: person, token: SignedState.generate("#{LINK}#{person.id}")) if required?

    person.update(email_verified_at: now)
    nil
  end

  # The person a verification link is for, or nil when it is not one Mainline
  # signed for this, or has run out.
  def self.person_for(token)
    value = SignedState.verify(token)
    Person[value.delete_prefix(LINK)] if value&.start_with?(LINK)
  end

  # Counts the person's address as verified, keeping when it first was.
  def self.confirm(person, now:)
    person.update(email_verified_at: now) unless person.email_verified_at
  end
end
