# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require 'timecop'

describe 'Magic login - request' do
  include MainlineDSL

  before do
    AUTH_RATE_LIMITER.reset
  end

  it 'shows the forgot password form' do
    resp = driver.get '/forgot-password'

    assert_equal 200, resp.status
    assert_includes resp.body, 'data-test-id="forgot-password-form"'
  end

  it 'shows same confirmation message whether email exists or not' do
    resp = driver.post '/forgot-password', { 'email' => 'nobody@acme.co' }
    resp = driver.follow_redirect if resp.redirect?

    assert_shown('flash-notice', resp.body)
  end

  it 'shows confirmation for existing email' do
    setup_team
    alice = add_person(name: 'Alice', email: 'alice@acme.co')
    email_bidx = BlindIndex.generate_bidx('alice@acme.co', key: Lockbox.master_key)
    PersonIdentity.create(
      person_id: alice.id, provider: 'email',
      provider_subject: email_bidx, email: 'alice@acme.co',
      password_digest: BCrypt::Password.create('longpassword12')
    )

    resp = driver.post '/forgot-password', { 'email' => 'alice@acme.co' }
    resp = driver.follow_redirect if resp.redirect?

    assert_shown('flash-notice', resp.body)
  end

  it 'shows an error when the login email fails to send' do
    setup_team
    alice = add_person(name: 'Alice', email: 'alice@acme.co')
    email_bidx = BlindIndex.generate_bidx('alice@acme.co', key: Lockbox.master_key)
    PersonIdentity.create(
      person_id: alice.id, provider: 'email',
      provider_subject: email_bidx, email: 'alice@acme.co',
      password_digest: BCrypt::Password.create('longpassword12')
    )

    resp = SendMagicLoginEmail.stub(:call, :failed) {
      driver.post '/forgot-password', { 'email' => 'alice@acme.co' }
    }
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'rate limits reset requests' do
    12.times do
      driver.post '/forgot-password', { 'email' => 'alice@acme.co' }
    end
    resp = driver.post '/forgot-password', { 'email' => 'alice@acme.co' }

    assert_equal 302, resp.status
    assert_equal '/forgot-password', URI.parse(resp['Location']).path
  end
end

describe 'Magic login - token' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    email_bidx = BlindIndex.generate_bidx('alice@acme.co', key: Lockbox.master_key)
    PersonIdentity.create(
      person_id: @alice.id, provider: 'email',
      provider_subject: email_bidx, email: 'alice@acme.co',
      password_digest: BCrypt::Password.create('longpassword12')
    )
  end

  it 'GET shows confirmation page without logging in' do
    token = SignedState.generate("magic:#{@alice.id}")

    resp = driver.get "/magic-login/#{token}"

    assert_equal 200, resp.status
    assert_includes resp.body, 'data-test-id="magic-login-confirm"'
    refute_shown('flash-notice', resp.body)
  end

  it 'POST logs in with a valid token' do
    token = SignedState.generate("magic:#{@alice.id}")

    resp = driver.post "/magic-login/#{token}"

    assert_equal 302, resp.status
    assert_equal '/profile/providers', URI.parse(resp['Location']).path
  end

  it 'POST rejects a token that was already used' do
    token = SignedState.generate("magic:#{@alice.id}")
    driver.post "/magic-login/#{token}"

    resp = driver.post "/magic-login/#{token}"
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'GET shows confirmation even after token is consumed' do
    token = SignedState.generate("magic:#{@alice.id}")
    driver.post "/magic-login/#{token}"

    resp = driver.get "/magic-login/#{token}"

    assert_equal 200, resp.status
    assert_includes resp.body, 'data-test-id="magic-login-confirm"'
  end

  it 'rejects an invalid token on GET' do
    resp = driver.get '/magic-login/garbage-token'
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'rejects an invalid token on POST' do
    resp = driver.post '/magic-login/garbage-token'
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'rejects an expired token' do
    token = SignedState.generate("magic:#{@alice.id}")
    Timecop.travel(Time.now + 901) do
      resp = driver.post "/magic-login/#{token}"
      resp = driver.follow_redirect if resp.redirect?

      assert_error_shown(resp.body)
    end
  end

  it 'rejects a token for a nonexistent person' do
    token = SignedState.generate('magic:00000000-0000-0000-0000-000000000099')

    resp = driver.post "/magic-login/#{token}"
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end
end

describe 'Magic login - one link per address at a time' do
  include MainlineDSL

  before do
    AUTH_RATE_LIMITER.reset
    setup_team
    add_person(name: 'Alice', email: 'alice@acme.co')
    add_person(name: 'Bob', email: 'bob@acme.co')
  end

  after do
    Timecop.return
  end

  it 'sends one login link when the same address asks twice in a row' do
    sent = login_links_sent {
      request_login_link('alice@acme.co')
      request_login_link('alice@acme.co')
    }

    assert_equal ['alice@acme.co'], sent
  end

  it 'still sends a link to a different address' do
    sent = login_links_sent {
      request_login_link('alice@acme.co')
      request_login_link('bob@acme.co')
    }

    assert_equal ['alice@acme.co', 'bob@acme.co'], sent
  end

  it 'sends another link once a minute has passed' do
    sent = login_links_sent {
      request_login_link('alice@acme.co')
      Timecop.travel(Time.now + 61)
      request_login_link('alice@acme.co')
    }

    assert_equal ['alice@acme.co', 'alice@acme.co'], sent
  end

  it 'shows the same confirmation when a link was already sent' do
    request_login_link('alice@acme.co')
    request_login_link('alice@acme.co')
    driver.follow_redirect

    assert_notice_shown
    refute_error_shown
  end
end
