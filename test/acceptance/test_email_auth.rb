# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Email auth rate limiting' do
  include MainlineDSL

  before do
    AUTH_RATE_LIMITER.reset
    LOGIN_GLOBAL_LIMITER.reset
    LOGIN_EMAIL_LIMITER.reset
  end

  it 'rate limits login per IP after too many attempts' do
    12.times do
      driver.submit_email_login(email: 'alice@acme.co', password: 'wrongpassword1')
    end
    resp = driver.submit_email_login(email: 'alice@acme.co', password: 'wrongpassword1')

    assert_equal 302, resp.status
    assert_equal '/login', URI.parse(resp['Location']).path
  end

  it 'turns away a signup that fills in the field people never see' do
    sent = []
    record = lambda { |**args|
      sent << args
      :sent
    }
    resp = SendVerificationEmail.stub(:call, record) {
      driver.submit_email_signup(name: 'Test', email: 'someone@acme.co', password: 'longpassword12',
        website: 'https://spam.example')
    }

    assert_equal '/signup', URI.parse(resp['Location']).path
    assert_nil Person.find_by_email('someone@acme.co')
    assert_empty sent
  end

  it 'turns away a signup sent back within seconds of loading the form' do
    started = driver.signup_form_started

    resp = driver.submit_email_signup(name: 'Test', email: 'quick@acme.co', password: 'longpassword12', form_started: started)

    assert_equal '/signup', URI.parse(resp['Location']).path
    assert_nil Person.find_by_email('quick@acme.co')
  end

  it 'signs up someone who took their time over the form' do
    started = driver.signup_form_started

    resp = Timecop.travel(Time.now + 5) {
      driver.submit_email_signup(name: 'Alice', email: 'alice@acme.co', password: 'longpassword12', form_started: started)
    }

    assert_equal '/teams/new', URI.parse(resp['Location']).path
  end

  it 'asks again when the signup form was left open for over a day' do
    started = driver.signup_form_started

    resp = Timecop.travel(Time.now + (24 * 60 * 60) + 1) {
      driver.submit_email_signup(name: 'Alice', email: 'alice@acme.co', password: 'longpassword12', form_started: started)
    }

    assert_equal '/signup', URI.parse(resp['Location']).path
    assert_nil Person.find_by_email('alice@acme.co')
    assert_error_shown(driver.follow_redirect.body)
  end

  it 'puts a field on the signup form that only bots fill in' do
    resp = driver.get '/signup'

    assert_shown('signup-website', resp.body)
  end

  it 'rate limits signup per visitor behind Cloudflare, whichever Cloudflare server they come through' do
    alice = '203.0.113.7'
    10.times do |i|
      driver.submit_email_signup(name: 'Alice', email: "alice#{i}@acme.co", password: 'longpassword12',
        via_cloudflare: { visitor: alice, edge: '162.158.95.101' })
    end

    alice_again = driver.submit_email_signup(name: 'Alice', email: 'alice99@acme.co', password: 'longpassword12',
      via_cloudflare: { visitor: alice, edge: '172.71.95.21' })
    bob = driver.submit_email_signup(name: 'Bob', email: 'bob@acme.co', password: 'longpassword12',
      via_cloudflare: { visitor: '198.51.100.20', edge: '162.158.95.101' })

    assert_equal '/signup', URI.parse(alice_again['Location']).path
    assert_equal '/teams/new', URI.parse(bob['Location']).path
  end

  it 'rate limits signup per IP after too many attempts' do
    12.times do |i|
      driver.submit_email_signup(
        name: 'Alice', email: "alice#{i}@acme.co", password: 'short'
      )
    end
    resp = driver.submit_email_signup(
      name: 'Alice', email: 'alice99@acme.co', password: 'short'
    )

    assert_equal 302, resp.status
    assert_equal '/signup', URI.parse(resp['Location']).path
  end

  it 'locks out an email after 5 failed attempts' do
    setup_team
    alice = add_person(name: 'Alice', email: 'alice@acme.co')
    email_bidx = BlindIndex.generate_bidx('alice@acme.co', key: Lockbox.master_key)
    PersonIdentity.create(
      person_id: alice.id, provider: 'email',
      provider_subject: email_bidx,
      email: 'alice@acme.co',
      password_digest: BCrypt::Password.create('longpassword12')
    )

    5.times do
      driver.submit_email_login(email: 'alice@acme.co', password: 'wrongpassword1')
    end
    resp = driver.submit_email_login(email: 'alice@acme.co', password: 'longpassword12')
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'returns same message for locked nonexistent email' do
    5.times do
      driver.submit_email_login(email: 'nobody@acme.co', password: 'wrongpassword1')
    end
    resp = driver.submit_email_login(email: 'nobody@acme.co', password: 'wrongpassword1')
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end
end

describe 'Email auth forms' do
  include MainlineDSL

  it 'login page has email and password fields with validation attributes' do
    resp = driver.visit_login

    assert_includes resp.body, 'data-test-id="email-login-form"'
    assert_includes resp.body, 'type="email"'
    assert_includes resp.body, 'type="password"'
    assert_includes resp.body, 'required'
  end

  it 'signup page has validated name, email, and password fields' do
    resp = driver.get '/signup'

    assert_includes resp.body, 'data-test-id="email-signup-form"'
    assert_includes resp.body, 'minlength="2"'
    assert_includes resp.body, 'maxlength="100"'
    assert_includes resp.body, 'maxlength="254"'
    assert_includes resp.body, 'minlength="12"'
    assert_includes resp.body, 'maxlength="70"'
  end
end

describe 'Email registration' do
  include MainlineDSL

  it 'registers with name, email, and password' do
    resp = driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
    )

    assert_equal 302, resp.status
    assert_equal '/teams/new', URI.parse(resp['Location']).path

    person = Person.find_by_email('alice@acme.co')

    refute_nil person, 'Person was not created'
    assert_equal 'Alice', person.name

    identity = PersonIdentity.where(person_id: person.id, provider: 'email').first

    refute_nil identity, 'Email identity was not created'
    refute_nil identity.provider_subject
    refute_nil identity.password_digest
  end

  it 'rejects password shorter than 12 characters' do
    resp = driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'short'
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
    assert_nil Person.find_by_email('alice@acme.co')
  end

  it 'rejects blank email' do
    resp = driver.submit_email_signup(
      name: 'Alice', email: '', password: 'longpassword12'
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'rejects invalid email format' do
    resp = driver.submit_email_signup(
      name: 'Alice', email: 'notanemail', password: 'longpassword12'
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
    assert_nil Person.find_by_email('notanemail')
  end

  it 'rejects name longer than 100 characters' do
    resp = driver.submit_email_signup(
      name: 'A' * 101, email: 'alice@acme.co', password: 'longpassword12'
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
    assert_nil Person.find_by_email('alice@acme.co')
  end

  it 'rejects email longer than 254 characters' do
    long_email = "#{'a' * 244}@example.co"
    resp = driver.submit_email_signup(
      name: 'Alice', email: long_email, password: 'longpassword12'
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'rejects password longer than 70 characters' do
    resp = driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'a' * 71
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
    assert_nil Person.find_by_email('alice@acme.co')
  end

  it 'rejects name shorter than 2 characters' do
    resp = driver.submit_email_signup(
      name: 'A', email: 'alice@acme.co', password: 'longpassword12'
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
    assert_nil Person.find_by_email('alice@acme.co')
  end

  it 'rejects blank name' do
    resp = driver.submit_email_signup(
      name: '', email: 'alice@acme.co', password: 'longpassword12'
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'rejects duplicate email' do
    Person.create(name: 'Existing', email: 'alice@acme.co')

    resp = driver.submit_email_signup(
      name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'shows an error when the signup verification email fails to send' do
    resp = SendVerificationEmail.stub(:call, :failed) {
      driver.submit_email_signup(
        name: 'Alice', email: 'alice@acme.co', password: 'longpassword12'
      )
    }
    resp = driver.follow_redirect while resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'handles invite token during registration' do
    inviter = Person.create(name: 'Boss', email: 'boss@acme.co')
    team = Team.create(name: 'Invite Team')
    SetTeamContext.call(team.id)
    TeamMembership.create(team_id: team.id, person_id: inviter.id)
    invitation = Invitation.create(
      team_id: team.id, email: 'invitee@acme.co',
      invited_by: inviter.id,
      token: InviteToken.digest('test-token-123'), expires_at: Time.now + 86_400
    )

    driver.get '/invite/test-token-123'
    resp = driver.submit_email_signup(
      name: 'Invitee', email: 'invitee@acme.co', password: 'longpassword12'
    )

    assert_equal 302, resp.status
    SetTeamContext.call(team.id)
    invitation.refresh

    refute_nil invitation.accepted_at
    assert_predicate TeamMembership.where(team_id: team.id), :any?
  end
end

describe 'Email login' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    email_bidx = BlindIndex.generate_bidx('alice@acme.co', key: Lockbox.master_key)
    PersonIdentity.create(
      person_id: @alice.id, provider: 'email',
      provider_subject: email_bidx,
      email: 'alice@acme.co',
      password_digest: BCrypt::Password.create('longpassword12')
    )
  end

  it 'logs in with correct email and password' do
    resp = driver.submit_email_login(
      email: 'alice@acme.co', password: 'longpassword12'
    )

    assert_equal 302, resp.status
    assert_equal '/teams', URI.parse(resp['Location']).path
  end

  it 'rejects wrong password' do
    resp = driver.submit_email_login(
      email: 'alice@acme.co', password: 'wrongpassword1'
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'rejects unknown email' do
    resp = driver.submit_email_login(
      email: 'nobody@acme.co', password: 'longpassword12'
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'accepts invite on email login' do
    team = Team.create(name: 'Invite Team')
    SetTeamContext.call(team.id)
    inviter = Person.create(name: 'Boss', email: 'boss@acme.co')
    TeamMembership.create(team_id: team.id, person_id: inviter.id)
    invitation = Invitation.create(
      team_id: team.id, email: 'alice@acme.co',
      invited_by: inviter.id,
      token: InviteToken.digest('email-invite-token'), expires_at: Time.now + 86_400
    )

    driver.get '/invite/email-invite-token'
    driver.submit_email_login(email: 'alice@acme.co', password: 'longpassword12')

    SetTeamContext.call(team.id)
    invitation.refresh

    refute_nil invitation.accepted_at
    assert_predicate TeamMembership.where(team_id: team.id, person_id: @alice.id), :any?
  end

  it 'rejects email that exists but has no password identity' do
    bob = add_person(name: 'Bob', email: 'bob@acme.co')
    PersonIdentity.create(
      person_id: bob.id, provider: 'github',
      provider_subject: 'gh-100', email: 'bob@acme.co'
    )

    resp = driver.submit_email_login(
      email: 'bob@acme.co', password: 'longpassword12'
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end
end

describe 'Email auth - profile password' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    PersonIdentity.create(
      person_id: @alice.id, provider: 'github',
      provider_subject: 'gh-100', email: 'alice@acme.co'
    )
    login_as(@alice)
  end

  it 'shows set password form for OAuth-only user' do
    resp = driver.get '/profile/providers'

    assert_includes resp.body, 'data-test-id="password-form"'
    assert_includes resp.body, 'data-has-password="false"'
    refute_includes resp.body, 'name="current_password"'
  end

  it 'shows change password form for user with existing password' do
    email_bidx = BlindIndex.generate_bidx('alice@acme.co', key: Lockbox.master_key)
    PersonIdentity.create(
      person_id: @alice.id, provider: 'email',
      provider_subject: email_bidx, email: 'alice@acme.co',
      password_digest: BCrypt::Password.create('oldpassword123')
    )

    resp = driver.get '/profile/providers'

    assert_includes resp.body, 'data-has-password="true"'
    assert_includes resp.body, 'name="current_password"'
  end

  it 'sets a password for an OAuth-only user' do
    resp = driver.submit_set_password(password: 'longpassword12')

    assert_equal 302, resp.status
    identity = PersonIdentity.where(person_id: @alice.id, provider: 'email').first

    refute_nil identity, 'Email identity was not created'
    refute_nil identity.password_digest, 'Password digest was not set'
  end

  it 'rejects short password on profile' do
    resp = driver.submit_set_password(password: 'short')
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
    assert_nil PersonIdentity.where(person_id: @alice.id, provider: 'email').first
  end

  it 'rejects long password on profile' do
    resp = driver.submit_set_password(password: 'a' * 71)
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
    assert_nil PersonIdentity.where(person_id: @alice.id, provider: 'email').first
  end

  it 'requires current password to change an existing password' do
    email_bidx = BlindIndex.generate_bidx('alice@acme.co', key: Lockbox.master_key)
    PersonIdentity.create(
      person_id: @alice.id, provider: 'email',
      provider_subject: email_bidx, email: 'alice@acme.co',
      password_digest: BCrypt::Password.create('oldpassword123')
    )

    resp = driver.submit_set_password(password: 'newpassword1234')
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
  end

  it 'changes password when current password is correct' do
    email_bidx = BlindIndex.generate_bidx('alice@acme.co', key: Lockbox.master_key)
    PersonIdentity.create(
      person_id: @alice.id, provider: 'email',
      provider_subject: email_bidx, email: 'alice@acme.co',
      password_digest: BCrypt::Password.create('oldpassword123')
    )

    resp = driver.submit_set_password(
      password: 'newpassword1234', current_password: 'oldpassword123'
    )

    assert_equal 302, resp.status
    identity = PersonIdentity.where(person_id: @alice.id, provider: 'email').first

    refute_nil identity
    assert BCrypt::Password.new(identity.password_digest).is_password?('newpassword1234')
  end

  it 'rejects wrong current password' do
    email_bidx = BlindIndex.generate_bidx('alice@acme.co', key: Lockbox.master_key)
    PersonIdentity.create(
      person_id: @alice.id, provider: 'email',
      provider_subject: email_bidx, email: 'alice@acme.co',
      password_digest: BCrypt::Password.create('oldpassword123')
    )

    resp = driver.submit_set_password(
      password: 'newpassword1234', current_password: 'wrongpassword1'
    )
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
    identity = PersonIdentity.where(person_id: @alice.id, provider: 'email').first

    assert BCrypt::Password.new(identity.password_digest).is_password?('oldpassword123')
  end

  it 'skips current password after magic link login' do
    email_bidx = BlindIndex.generate_bidx('alice@acme.co', key: Lockbox.master_key)
    PersonIdentity.create(
      person_id: @alice.id, provider: 'email',
      provider_subject: email_bidx, email: 'alice@acme.co',
      password_digest: BCrypt::Password.create('oldpassword123')
    )

    token = SignedState.generate("magic:#{@alice.id}")
    driver.post "/magic-login/#{token}"

    resp = driver.submit_set_password(password: 'newpassword1234')

    assert_equal 302, resp.status
    identity = PersonIdentity.where(person_id: @alice.id, provider: 'email').first

    assert BCrypt::Password.new(identity.password_digest).is_password?('newpassword1234')
  end

  it 'shows password form without current password field after magic link' do
    email_bidx = BlindIndex.generate_bidx('alice@acme.co', key: Lockbox.master_key)
    PersonIdentity.create(
      person_id: @alice.id, provider: 'email',
      provider_subject: email_bidx, email: 'alice@acme.co',
      password_digest: BCrypt::Password.create('oldpassword123')
    )

    token = SignedState.generate("magic:#{@alice.id}")
    driver.post "/magic-login/#{token}"

    resp = driver.get '/profile/providers'

    assert_includes resp.body, 'data-has-password="true"'
    refute_includes resp.body, 'name="current_password"'
  end

  it 'allows disconnecting OAuth after setting password' do
    driver.submit_set_password(password: 'longpassword12')
    github_id = PersonIdentity.where(person_id: @alice.id, provider: 'github').first

    resp = driver.post "/profile/providers/#{github_id.id}/disconnect"

    assert_equal 302, resp.status
    assert_nil PersonIdentity[github_id.id]
    assert_equal 1, PersonIdentity.where(person_id: @alice.id).count
  end
end
