# frozen_string_literal: true

require 'net/smtp'
require 'securerandom'
require 'time'

module Mailer
  # A dead or blocked mail server must fail fast: mail is sent inside the
  # request, and Cloudflare gives up on the request after 100 seconds.
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  def self.deliver(to:, subject:, text:, from: nil)
    raise ArgumentError, 'recipient must be a single address' if to.to_s.empty? || to.to_s.match?(/\s/)

    from ||= ENV.fetch('MAIL_FROM')
    smtp = Net::SMTP.new(ENV.fetch('SMTP_HOST'), Integer(ENV.fetch('SMTP_PORT')), **tls_options)
    smtp.open_timeout = OPEN_TIMEOUT
    smtp.read_timeout = READ_TIMEOUT
    smtp.start(user: ENV.fetch('SMTP_USERNAME'), secret: ENV.fetch('SMTP_PASSWORD')) do |session|
      session.send_message(message(from, to, subject, text), address(from), to)
    end
    nil
  rescue StandardError => e
    # Rake tasks load the mailer without the web app, and so without Sentry.
    Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
    :failed
  end

  def self.tls_options
    case ENV.fetch('SMTP_TLS')
    when 'tls' then { tls: true, starttls: false }
    when 'starttls' then { tls: false, starttls: :always }
    else raise ArgumentError, 'SMTP_TLS must be tls or starttls'
    end
  end

  def self.address(from)
    from[/<([^>]+)>/, 1] || from
  end

  def self.message(from, to, subject, text)
    [
      "From: #{single_line(from)}",
      "To: #{single_line(to)}",
      "Subject: #{encode_header(subject)}",
      "Date: #{Time.now.rfc2822}",
      "Message-ID: <#{SecureRandom.uuid}@#{address(from).split('@').last}>",
      'MIME-Version: 1.0',
      'Content-Type: text/plain; charset=UTF-8',
      'Content-Transfer-Encoding: 8bit',
      '',
      text.gsub(/\r?\n/, "\r\n")
    ].join("\r\n")
  end

  def self.single_line(value)
    value.to_s.gsub(/[\r\n]+/, ' ')
  end

  def self.encode_header(value)
    line = single_line(value)
    return line if line.ascii_only?

    line.scan(/.{1,10}/m).map { |chunk| "=?UTF-8?B?#{[chunk].pack('m0')}?=" }.join(' ')
  end
end
