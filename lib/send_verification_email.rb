# frozen_string_literal: true

require_relative 'mailer'

module SendVerificationEmail
  def self.call(person:, token:)
    return dev_link(token) unless ENV['RACK_ENV'] == 'production'

    Mailer.deliver(
      to:      person.email,
      subject: 'Verify your Mainline email',
      text:    text_body(token)
    )
  end

  # Where no mail is sent, the link a person can follow from the page.
  def self.screen_link(person)
    dev_link(SignedState.generate("verify:#{person.id}")) unless ENV['RACK_ENV'] == 'production'
  end

  def self.dev_link(token)
    "http://#{ENV.fetch('MAINLINE_HOST')}/verify-email/#{token}"
  end

  def self.text_body(token)
    <<~TEXT
      Welcome to Mainline. Please verify your email to create a team.

      Verify: https://#{ENV.fetch('MAINLINE_HOST')}/verify-email/#{token}

      This link expires in 10 minutes.
    TEXT
  end
end
