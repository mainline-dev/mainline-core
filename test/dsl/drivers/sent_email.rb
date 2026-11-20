# frozen_string_literal: true

# What a driver catches of the email the system would send: who a login link
# or a request to verify went to while a block ran. Nothing is sent.
module SentEmail
  def login_links_sent(&)
    addresses_sent_by(SendMagicLoginEmail, &)
  end

  def verification_emails_sent(&)
    addresses_sent_by(SendVerificationEmail, &)
  end

  def addresses_sent_by(sender, &)
    sent = []
    capture = lambda do |person:, **|
      sent << person.email
      nil
    end
    sender.stub(:call, capture, &)
    sent
  end
end
