# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/signup_timer'

describe SignupTimer do
  cover 'SignupTimer*'

  after do
    Timecop.return
  end

  def submitted_after(seconds)
    token = SignupTimer.token
    Timecop.travel(Time.now + seconds)
    SignupTimer.check(token)
  end

  it 'accepts a form someone took a few seconds over' do
    assert_equal :ok, submitted_after(4)
  end

  it 'takes a form sent back within three seconds of loading for a bot' do
    assert_equal :bot, submitted_after(1)
  end

  it 'takes a missing or tampered start for a bot' do
    token = SignupTimer.token
    Timecop.travel(Time.now + 10)

    assert_equal :bot, SignupTimer.check(nil)
    assert_equal :bot, SignupTimer.check('')
    assert_equal :bot, SignupTimer.check("#{token}0")
    assert_equal :bot, SignupTimer.check(SignedState.generate('something-else'))
  end

  it 'says a form left open for over a day has expired' do
    assert_equal :expired, submitted_after((24 * 60 * 60) + 1)
  end
end
