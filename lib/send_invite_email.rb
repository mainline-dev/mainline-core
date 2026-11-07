# frozen_string_literal: true

require_relative 'mailer'

module SendInviteEmail
  def self.call(invitation:, inviter:, team:, token:)
    return dev_link(token) unless ENV['RACK_ENV'] == 'production'

    Mailer.deliver(
      to:      invitation.email,
      subject: "#{inviter.name} invited you to #{team.name} on Mainline",
      text:    text_body(token, inviter, team)
    )
  end

  def self.dev_link(token)
    "http://#{ENV.fetch('MAINLINE_HOST')}/invite/#{token}"
  end

  def self.text_body(token, inviter, team)
    <<~TEXT
      #{inviter.name} invited you to join #{team.name} on Mainline.

      Sign in to accept: https://#{ENV.fetch('MAINLINE_HOST')}/invite/#{token}

      This invitation expires in 7 days.
    TEXT
  end
end
