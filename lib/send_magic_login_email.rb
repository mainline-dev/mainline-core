# frozen_string_literal: true

require_relative 'mailer'

module SendMagicLoginEmail
  def self.call(person:, token:)
    return dev_link(token) unless ENV['RACK_ENV'] == 'production'

    Mailer.deliver(
      to:      person.email,
      subject: 'Your Mainline login link',
      text:    text_body(token)
    )
  end

  def self.dev_link(token)
    "http://#{ENV.fetch('MAINLINE_HOST')}/magic-login/#{token}"
  end

  def self.text_body(token)
    <<~TEXT
      Someone requested a login link for your Mainline account.

      Sign in: https://#{ENV.fetch('MAINLINE_HOST')}/magic-login/#{token}

      This link expires in 10 minutes. If you did not request this, ignore this email.
    TEXT
  end
end
