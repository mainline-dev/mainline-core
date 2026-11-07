# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/send_verification_email'

describe SendVerificationEmail do
  def call_module
    SendVerificationEmail.call(
      person: Struct.new(:email).new('alice@corp.co'),
      token:  'verify-token'
    )
  end

  def deliver_in_production(outcome)
    sent = nil
    result = nil
    stub_env('RACK_ENV' => 'production') do
      capture = lambda do |**mail|
        sent = mail
        outcome
      end
      Mailer.stub(:deliver, capture) do
        result = call_module
      end
    end
    [result, sent]
  end

  it 'returns the dev link when not in production' do
    assert_equal 'http://localhost:3000/verify-email/verify-token', call_module
  end

  it 'sends the verify link to the person' do
    _, sent = deliver_in_production(nil)

    assert_equal 'alice@corp.co', sent[:to]
    refute_empty sent[:subject]
    assert_includes sent[:text], 'https://localhost:3000/verify-email/verify-token'
  end

  it 'returns nil when the email is sent' do
    result, = deliver_in_production(nil)

    assert_nil result
  end

  it 'returns :failed when the email cannot be sent' do
    result, = deliver_in_production(:failed)

    assert_equal :failed, result
  end

  private

  def stub_env(overrides)
    originals = overrides.to_h { |k, _| [k, ENV.fetch(k, nil)] }
    overrides.each { |k, v| ENV[k] = v }
    yield
  ensure
    originals.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
