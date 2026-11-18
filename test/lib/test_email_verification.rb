# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/email_verification'

describe EmailVerification do
  cover 'EmailVerification*'

  before do
    @alice = Person.create(name: 'Alice', email: 'alice@verify.co')
    @now = Time.utc(2030, 1, 7, 9)
  end

  # What the block gives on an install of this kind.
  def on_install(kind)
    was = ENV.fetch('RACK_ENV')
    ENV['RACK_ENV'] = kind
    yield
  ensure
    ENV['RACK_ENV'] = was
  end

  it 'is required everywhere but a development install' do
    in_production = on_install('production') { EmailVerification.required? }
    in_development = on_install('development') { EmailVerification.required? }

    assert_equal [true, true, false], [EmailVerification.required?, in_production, in_development]
  end

  it 'sends a new person a link that is theirs, and leaves the address unverified until they confirm' do
    link = EmailVerification.ask(@alice, now: @now)

    assert_equal @alice.id, EmailVerification.person_for(link.split('/').last).id
    assert_nil @alice.refresh.email_verified_at
  end

  it 'counts the address as verified straight away where no link is required, sending nothing' do
    sent = on_install('development') { EmailVerification.ask(@alice, now: @now) }

    assert_nil sent
    assert_equal @now, @alice.refresh.email_verified_at
  end

  it 'knows nobody for a link of another kind, a link for nobody, or anything that is no link' do
    others = [SignedState.generate("magic:#{@alice.id}"), SignedState.generate('verify:00000000-0000-4000-8000-000000000000'),
              'not-a-link', '']

    assert_equal [nil], others.map { |token| EmailVerification.person_for(token) }.uniq
  end

  it 'counts the address as verified once confirmed, keeping when it first was' do
    EmailVerification.confirm(@alice, now: @now)
    EmailVerification.confirm(@alice.refresh, now: @now + 60)

    assert_equal @now, @alice.refresh.email_verified_at
  end
end
