# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/signed_state'

describe SignedState do
  cover 'SignedState*'

  before do
    @team_id = SecureRandom.uuid
  end

  it 'round-trips a team_id through generate and verify' do
    token = SignedState.generate(@team_id)

    assert_equal @team_id, SignedState.verify(token)
  end

  it 'rejects a tampered team_id' do
    token = SignedState.generate(@team_id)
    other_id = SecureRandom.uuid
    tampered = token.sub(@team_id, other_id)

    assert_nil SignedState.verify(tampered)
  end

  it 'rejects a token with no separator' do
    assert_nil SignedState.verify(@team_id)
  end

  it 'rejects a token with empty signature' do
    assert_nil SignedState.verify("#{@team_id}.")
  end

  it 'rejects nil' do
    assert_nil SignedState.verify(nil)
  end

  it 'rejects empty string' do
    assert_nil SignedState.verify('')
  end

  it 'round-trips a value containing colons' do
    value = 'prefix:middle:suffix'
    token = SignedState.generate(value)

    assert_equal value, SignedState.verify(token)
  end

  it 'rejects a token signed directly with the session secret' do
    payload = "#{@team_id}:#{Time.now.to_i}"
    forged_sig = OpenSSL::HMAC.hexdigest(
      'SHA256', ENV.fetch('MAINLINE_SESSION_SECRET'), payload
    )

    assert_nil SignedState.verify("#{payload}.#{forged_sig}")
  end

  it 'rejects an expired token' do
    token = nil
    Time.stub(:now, Time.at(1_000_000)) do
      token = SignedState.generate(@team_id)
    end

    Time.stub(:now, Time.at(1_000_000 + SignedState::TTL + 1)) do
      assert_nil SignedState.verify(token)
    end
  end

  it 'accepts a token within TTL' do
    token = nil
    Time.stub(:now, Time.at(1_000_000)) do
      token = SignedState.generate(@team_id)
    end

    Time.stub(:now, Time.at(1_000_000 + SignedState::TTL - 1)) do
      assert_equal @team_id, SignedState.verify(token)
    end
  end
end
