# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require 'timecop'

describe 'Email verification - signup sends verification email' do
  include MainlineDSL

  it 'sets email_verified_at to nil on email signup' do
    driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
    )

    person = Person.find_by_email('alice@acme.co')

    refute_nil person
    assert_nil person.email_verified_at
  end

  it 'sets email_verified_at after OAuth email confirmation' do
    driver.oauth_callback(
      provider: 'github', uid: 'gh-verify-1',
      email: 'oauth@acme.co', name: 'OAuth User'
    )
    resp = driver.get '/confirm-email'
    token = resp.body[%r{/verify-email/([^"<]+)}, 1]
    driver.post "/verify-email/#{token}"

    person = Person.find_by_email('oauth@acme.co')

    refute_nil person
    refute_nil person.email_verified_at
  end
end

describe 'Email verification - create team gate' do
  include MainlineDSL

  it 'blocks unverified email user from creating a team' do
    driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
    )

    resp = driver.submit_create_team(team_name: 'My Team')
    resp = driver.follow_redirect if resp.redirect?

    assert_shown('flash-error', resp.body)
    assert_equal 0, Team.where(name: 'My Team').count
  end

  it 'allows verified email user to create a team' do
    driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
    )
    person = Person.find_by_email('alice@acme.co')
    person.update(email_verified_at: Time.now)

    resp = driver.submit_create_team(team_name: 'My Team')

    assert_equal 302, resp.status
    assert_equal 1, Team.where(name: 'My Team').count
  end

  it 'allows OAuth user to create a team after email confirmation' do
    driver.oauth_callback(
      provider: 'github', uid: 'gh-verify-2',
      email: 'oauth@acme.co', name: 'OAuth User'
    )
    resp = driver.get '/confirm-email'
    token = resp.body[%r{/verify-email/([^"<]+)}, 1]
    driver.post "/verify-email/#{token}"

    resp = driver.submit_create_team(team_name: 'OAuth Team')

    assert_equal 302, resp.status
    assert_equal 1, Team.where(name: 'OAuth Team').count
  end
end

describe 'Email verification - resend' do
  include MainlineDSL

  before do
    AUTH_RATE_LIMITER.reset
  end

  it 'shows the verification link on screen where no mail is sent' do
    driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
    )

    driver.follow_redirect!

    assert driver.response_includes?('/verify-email/')
  end

  it 'shows the verification link again when asked to resend it' do
    driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
    )
    driver.follow_redirect!

    driver.post '/resend-verification'
    driver.follow_redirect!

    assert driver.response_includes?('/verify-email/')
  end

  it 'resends verification email for unverified user' do
    driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
    )

    sent = verification_emails_sent { driver.post '/resend-verification' }

    assert_equal ['alice@acme.co'], sent
  end

  it 'shows an error when the resent verification email fails to send' do
    driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
    )

    resp = SendVerificationEmail.stub(:call, :failed) {
      driver.post '/resend-verification'
    }
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'shows an error when the OAuth signup verification email fails to send' do
    resp = SendVerificationEmail.stub(:call, :failed) {
      inner = driver.oauth_callback(
        provider: 'google_oauth2', uid: 'new-uid', email: 'new@acme.co', name: 'New'
      )
      inner = driver.follow_redirect while inner.redirect?
      inner
    }

    assert_error_shown(resp.body)
  end

  it 'does nothing for already verified user' do
    driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
    )
    Person.find_by_email('alice@acme.co').update(email_verified_at: Time.now)

    sent = verification_emails_sent { driver.post '/resend-verification' }

    assert_empty sent
  end

  it 'redirects to teams even when rate limited' do
    driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
    )

    12.times { driver.post '/resend-verification' }
    resp = driver.post '/resend-verification'

    assert_equal 302, resp.status
    assert_equal '/teams', URI.parse(resp['Location']).path
  end
end

describe 'Email verification - verify link' do
  include MainlineDSL

  before do
    driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
    )
    @person = Person.find_by_email('alice@acme.co')
  end

  it 'GET shows confirmation page' do
    token = SignedState.generate("verify:#{@person.id}")

    resp = driver.get "/verify-email/#{token}"

    assert_equal 200, resp.status
    assert_includes resp.body, 'data-test-id="verify-email-confirm"'
  end

  it 'POST verifies the email' do
    token = SignedState.generate("verify:#{@person.id}")

    resp = driver.post "/verify-email/#{token}"

    assert_equal 302, resp.status
    @person.refresh

    refute_nil @person.email_verified_at
  end

  it 'rejects invalid token' do
    resp = driver.post '/verify-email/garbage'
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'rejects expired token' do
    token = SignedState.generate("verify:#{@person.id}")
    Timecop.travel(Time.now + 901) do
      resp = driver.post "/verify-email/#{token}"
      resp = driver.follow_redirect if resp.redirect?

      assert_error_shown(resp.body)
    end
  end
end

describe 'Email verification - the reminder that stays' do
  include MainlineDSL

  before do
    AUTH_RATE_LIMITER.reset
    driver.submit_email_signup(name: 'Alice', email: 'alice@acme.co', password: 'longpassword12')
    driver.follow_redirect!
  end

  def banner_link
    driver.attributes_of('verify-banner-link', 'href').first
  end

  it 'is still there on a later page, after the sign-up notice has gone' do
    resp = driver.visit_teams

    assert_shown('verify-email-banner', resp.body)
    assert_shown('verify-banner-resend', resp.body)
    refute_shown('flash-notice', resp.body)
  end

  it 'carries a link that verifies the email, where no mail is sent' do
    driver.visit_teams

    driver.post URI.parse(banner_link).path

    refute_nil Person.find_by_email('alice@acme.co').email_verified_at
  end

  it 'has no link where the mail is sent' do
    SendVerificationEmail.stub(:screen_link, nil) do
      resp = driver.visit_teams

      assert_shown('verify-email-banner', resp.body)
      refute_shown('verify-banner-link', resp.body)
    end
  end

  it 'goes once the email is verified' do
    Person.find_by_email('alice@acme.co').update(email_verified_at: Time.now)

    refute_shown('verify-email-banner', driver.visit_teams.body)
  end

  it 'is not shown to someone who signed in through a provider' do
    setup_team
    add_person(name: 'Bob')
    Person.where(name: 'Bob').update(email_verified_at: nil)

    refute_shown('verify-email-banner', driver.visit_teams.body)
  end
end

describe 'Email verification - a local development install' do
  include MainlineDSL

  before { AUTH_RATE_LIMITER.reset }

  def sign_up_locally
    EmailVerification.stub(:required?, false) do
      driver.submit_email_signup(name: 'Alice', email: 'alice@acme.co', password: 'longpassword12')
    end
  end

  it 'counts an email sign-up as verified, since no mail can be sent' do
    sent = verification_emails_sent { sign_up_locally }

    refute_nil Person.find_by_email('alice@acme.co').email_verified_at
    assert_empty sent
  end

  it 'lets that person create a team straight away, with no reminder' do
    sign_up_locally

    refute_shown('verify-email-banner', driver.follow_redirect.body)
    assert_equal 302, driver.submit_create_team(team_name: 'My Team').status
    assert_equal 1, Team.where(name: 'My Team').count
  end

  it 'is the only place verification is not required' do
    assert_predicate EmailVerification, :required?
    refute(ENV.stub(:fetch, 'development') { EmailVerification.required? })
    assert(ENV.stub(:fetch, 'production') { EmailVerification.required? })
  end
end
