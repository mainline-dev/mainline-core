# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/send_invite_email'

describe SendInviteEmail do
  def call_module
    SendInviteEmail.call(
      invitation: Struct.new(:email).new('dev@corp.co'),
      inviter:    Struct.new(:name).new('Buyer'),
      team:       Struct.new(:name).new('Acme'),
      token:      'invite-token'
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

  it 'returns the invite link when not in production' do
    assert_equal 'http://localhost:3000/invite/invite-token', call_module
  end

  it 'sends the invite link to the invited address' do
    _, sent = deliver_in_production(nil)

    assert_equal 'dev@corp.co', sent[:to]
    assert_includes sent[:text], 'https://localhost:3000/invite/invite-token'
  end

  it 'names the inviter and the team in the subject' do
    _, sent = deliver_in_production(nil)

    assert_includes sent[:subject], 'Buyer'
    assert_includes sent[:subject], 'Acme'
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
