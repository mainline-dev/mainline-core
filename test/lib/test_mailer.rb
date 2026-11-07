# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../subprocess_helper'
require_relative '../../lib/mailer'

class FakeSMTP
  attr_reader :host, :port, :options, :user, :secret, :message, :from, :to
  attr_accessor :open_timeout, :read_timeout

  def initialize(host, port, **options)
    @host = host
    @port = port
    @options = options
  end

  def start(user:, secret:, **)
    @user = user
    @secret = secret
    yield self
  end

  def send_message(message, from, *to)
    @message = message
    @from = from
    @to = to
  end
end

describe Mailer do
  def smtp_env
    {
      'SMTP_HOST'     => 'smtp.example.com',
      'SMTP_PORT'     => '465',
      'SMTP_USERNAME' => 'user',
      'SMTP_PASSWORD' => 'secret',
      'SMTP_TLS'      => 'tls',
      'MAIL_FROM'     => 'Mainline <noreply@example.com>'
    }
  end

  def deliver(env: {}, to: 'alice@corp.co', **args)
    fake = nil
    result = nil
    stub_env(smtp_env.merge(env)) do
      Net::SMTP.stub(:new, ->(host, port, **opts) { fake = FakeSMTP.new(host, port, **opts) }) do
        result = Mailer.deliver(to: to, subject: 'Hello', text: "Line one\nLine two\n", **args)
      end
    end
    [result, fake]
  end

  def headers(message)
    message.split("\r\n\r\n", 2).first.split("\r\n")
  end

  it 'returns nil when the message is accepted' do
    result, = deliver

    assert_nil result
  end

  it 'sends from MAIL_FROM to the recipient' do
    _, smtp = deliver

    assert_equal 'noreply@example.com', smtp.from
    assert_equal ['alice@corp.co'], smtp.to
    assert_includes headers(smtp.message), 'From: Mainline <noreply@example.com>'
    assert_includes headers(smtp.message), 'To: alice@corp.co'
  end

  it 'sends from a given sender instead of MAIL_FROM' do
    _, smtp = deliver(from: 'Nat at Mainline <hello@example.com>')

    assert_equal 'hello@example.com', smtp.from
    assert_includes headers(smtp.message), 'From: Nat at Mainline <hello@example.com>'
  end

  it 'sends the subject and plain text body' do
    _, smtp = deliver

    assert_includes headers(smtp.message), 'Subject: Hello'
    assert_includes headers(smtp.message), 'Content-Type: text/plain; charset=UTF-8'
    assert_equal "Line one\r\nLine two\r\n", smtp.message.split("\r\n\r\n", 2).last
  end

  it 'connects to the configured server with the configured credentials' do
    _, smtp = deliver

    assert_equal 'smtp.example.com', smtp.host
    assert_equal 465, smtp.port
    assert_equal 'user', smtp.user
    assert_equal 'secret', smtp.secret
  end

  it 'gives up within seconds when the mail server does not answer' do
    _, smtp = deliver

    refute_nil smtp.open_timeout, 'no connect timeout set'
    refute_nil smtp.read_timeout, 'no read timeout set'
    assert_operator smtp.open_timeout, :<=, 5
    assert_operator smtp.read_timeout, :<=, 10
  end

  it 'uses implicit TLS when SMTP_TLS is tls' do
    _, smtp = deliver

    assert smtp.options[:tls]
  end

  it 'uses STARTTLS when SMTP_TLS is starttls' do
    _, smtp = deliver(env: { 'SMTP_TLS' => 'starttls', 'SMTP_PORT' => '587' })

    refute smtp.options[:tls]
    assert_equal :always, smtp.options[:starttls]
  end

  it 'encodes a subject that is not plain ASCII' do
    _, smtp = deliver(subject: 'Zoë invited you to Café')

    subject = headers(smtp.message).find { |h| h.start_with?('Subject: ') }

    assert_predicate subject, :ascii_only?
    assert_equal 'Zoë invited you to Café', decode(subject)
  end

  it 'does not let a newline in the subject add a header' do
    _, smtp = deliver(subject: "Hi\r\nBcc: eve@evil.co")

    refute(headers(smtp.message).any? { |h| h.start_with?('Bcc:') })
  end

  it 'returns :failed when the server rejects the message' do
    result = nil
    stub_env(smtp_env) do
      Net::SMTP.stub(:new, ->(*, **) { raise Net::SMTPAuthenticationError.new(nil, message: '535 bad credentials') }) do
        result = Mailer.deliver(to: 'alice@corp.co', subject: 'Hello', text: 'Hi')
      end
    end

    assert_equal :failed, result
  end

  it 'returns :failed when the connection fails' do
    result = nil
    stub_env(smtp_env) do
      Net::SMTP.stub(:new, ->(*, **) { raise Errno::ECONNREFUSED }) do
        result = Mailer.deliver(to: 'alice@corp.co', subject: 'Hello', text: 'Hi')
      end
    end

    assert_equal :failed, result
  end

  # Rake tasks such as announce_mcp load the mailer without the web app, so
  # without error reporting; a failed send must still just report :failed.
  it 'returns :failed when the connection fails and error reporting is not loaded' do
    script = <<~'RUBY'
      require './lib/mailer'
      Net::SMTP.define_singleton_method(:new) { |*, **| raise Errno::ECONNREFUSED }
      puts "RESULT:#{Mailer.deliver(to: 'alice@corp.co', subject: 'Hello', text: 'Hi').inspect}"
    RUBY
    out, status = Subprocess.run(smtp_env, 'ruby', '-e', script)

    assert_predicate status, :success?, out
    assert_equal ':failed', out[/^RESULT:(.*)$/, 1]
  end

  it 'refuses a recipient that is not a single address' do
    result, smtp = deliver(to: "alice@corp.co\r\nRCPT TO:<eve@evil.co>")

    assert_equal :failed, result
    assert_nil smtp, 'connected to the mail server anyway'
  end

  private

  def decode(header)
    words = header.delete_prefix('Subject: ').scan(/=\?UTF-8\?B\?([^?]*)\?=/).flatten
    words.map { |b| b.unpack1('m') }.join.force_encoding('UTF-8')
  end

  def stub_env(overrides)
    originals = overrides.to_h { |k, _| [k, ENV.fetch(k, nil)] }
    overrides.each { |k, v| ENV[k] = v }
    yield
  ensure
    originals.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
