# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require 'timecop'

describe 'Authentication' do
  include MainlineDSL

  before do
    setup_team
    create_map
  end

  it 'login page shows sign in with OAuth providers' do
    resp = driver.visit_login

    assert_equal 200, resp.status
    assert_includes resp.body, 'action="/auth/google_oauth2"'
    assert_includes resp.body, 'action="/auth/github"'
    assert_includes resp.body, 'action="/auth/gitlab"'
    assert_includes resp.body, 'href="/signup"'
  end

  it 'hides a sign-in provider whose client id is disabled' do
    was = ENV.fetch('GITLAB_CLIENT_ID')
    ENV['GITLAB_CLIENT_ID'] = 'disabled'
    login = driver.visit_login.body
    signup = driver.get('/signup').body

    refute_includes login, 'action="/auth/gitlab"'
    refute_includes signup, 'action="/auth/gitlab"'
    assert_includes login, 'action="/auth/google_oauth2"'
  ensure
    ENV['GITLAB_CLIENT_ID'] = was
  end

  it 'redirects unauthenticated request to /login' do
    resp = driver.visit_map(@map)

    assert_equal 302, resp.status
    assert_equal '/login', URI.parse(resp['Location']).path
  end

  it 'preserves csrf token when unauthenticated request hits a protected path' do
    resp = driver.get '/signup'
    token = resp.body[/name="authenticity_token" value="([^"]+)"/, 1]

    refute_nil token, 'signup page should contain an authenticity_token'

    driver.visit_map(@map)

    resp = driver.get '/signup'
    token_after = resp.body[/name="authenticity_token" value="([^"]+)"/, 1]

    assert_equal token, token_after, 'csrf token was destroyed by auth redirect'
  end

  it 'renders signup page' do
    resp = driver.get '/signup'

    assert_equal 200, resp.status
    assert_includes resp.body, 'data-test-id="email-signup-form"'
    assert_includes resp.body, 'href="/login"'
  end

  it 'new OAuth signup redirects to confirm-email instead of creating account' do
    resp = driver.oauth_callback(provider: 'google_oauth2',
      uid: '999', email: 'newuser@acme.co', name: 'New User')

    assert_equal 302, resp.status
    assert_equal '/confirm-email', URI.parse(resp['Location']).path

    assert_nil Person.find_by_email('newuser@acme.co'),
      'Person should not be created before email confirmation'
  end

  it 'confirm-email page shows the email from OAuth provider' do
    driver.oauth_callback(provider: 'google_oauth2',
      uid: '123', email: 'alice@acme.co', name: 'Alice')
    resp = driver.get '/confirm-email'

    assert_equal 200, resp.status
    assert_includes resp.body, 'alice@acme.co'
  end

  it 'reloading confirm-email does not resend verification email' do
    driver.oauth_callback(provider: 'google_oauth2',
      uid: '123', email: 'alice@acme.co', name: 'Alice')
    resp1 = driver.get '/confirm-email'
    link1 = resp1.body[%r{/verify-email/([^"<]+)}, 1]

    Timecop.travel(Time.now + 5) do
      resp2 = driver.get '/confirm-email'
      link2 = resp2.body[%r{/verify-email/([^"<]+)}, 1]

      assert_equal link1, link2, 'Should reuse the same verification link, not generate a new one'
    end
  end

  it 'confirm-email page shows email form when OAuth returned no email' do
    driver.oauth_callback(provider: 'google_oauth2',
      uid: '123', email: nil, name: 'Alice')
    resp = driver.get '/confirm-email'

    assert_equal 200, resp.status
    assert_includes resp.body, 'data-test-id="enter-email-form"'
  end

  it 'creates account after email verification link is clicked' do
    driver.oauth_callback(provider: 'google_oauth2',
      uid: '123456', email: 'alice@acme.co', name: 'Alice')
    resp = driver.get '/confirm-email'
    token = resp.body[%r{/verify-email/([^"]+)}, 1]

    refute_nil token, 'Verification link should be present in dev mode'

    resp = driver.get "/verify-email/#{token}"

    assert_equal 200, resp.status

    driver.post "/verify-email/#{token}"

    person = Person.find_by_email('alice@acme.co')

    refute_nil person, 'Person should be created after verification'
    assert_equal 'Alice', person.name
    refute_nil person.email_verified_at

    identity = PersonIdentity.where(person_id: person.id, provider: 'google_oauth2').first

    refute_nil identity, 'Identity should be created after verification'
    assert_equal '123456', identity.provider_subject
  end

  it 'redirects to teams after OAuth email verification' do
    driver.oauth_callback(provider: 'google_oauth2',
      uid: '123456', email: 'alice@acme.co', name: 'Alice')
    resp = driver.get '/confirm-email'
    token = resp.body[%r{/verify-email/([^"]+)}, 1]
    resp = driver.post "/verify-email/#{token}"

    assert_equal 302, resp.status
    assert_equal '/teams/new', URI.parse(resp['Location']).path
  end

  it 'creates account when verification link is opened in a different browser session' do
    driver.oauth_callback(provider: 'google_oauth2',
      uid: '123456', email: 'alice@acme.co', name: 'Alice')
    resp = driver.get '/confirm-email'
    token = resp.body[%r{/verify-email/([^"]+)}, 1]

    refute_nil token, 'Verification link should be present in dev mode'

    other_browser = HttpDriver.new
    resp = other_browser.get "/verify-email/#{token}"

    assert_equal 200, resp.status

    other_browser.post "/verify-email/#{token}"

    person = Person.find_by_email('alice@acme.co')

    refute_nil person, 'Person should be created from a different session'
    assert_equal 'Alice', person.name
    refute_nil person.email_verified_at

    identity = PersonIdentity.where(person_id: person.id, provider: 'google_oauth2').first

    refute_nil identity, 'Identity should be created from a different session'
    assert_equal '123456', identity.provider_subject
  end

  it 'existing OAuth user logs in without re-verification' do
    person = Person.create(name: 'Alice', email: 'alice@acme.co', email_verified_at: Time.now)
    PersonIdentity.create(
      person_id: person.id, provider: 'google_oauth2',
      provider_subject: '123456', email: 'alice@acme.co'
    )
    TeamMembership.create(team_id: @team.id, person_id: person.id)

    resp = driver.oauth_callback(provider: 'google_oauth2',
      uid: '123456', email: 'alice@acme.co', name: 'Alice')

    assert_equal 302, resp.status
    assert_equal '/teams', URI.parse(resp['Location']).path
  end

  it 'GitLab OAuth signup also requires email confirmation' do
    resp = driver.oauth_callback(provider: 'gitlab',
      uid: 'gl-99', email: 'bob@acme.co', name: 'Bob')

    assert_equal 302, resp.status
    assert_equal '/confirm-email', URI.parse(resp['Location']).path

    assert_nil Person.find_by_email('bob@acme.co'),
      'Person should not be created before email confirmation'
  end

  it 'blocks sign-in when email matches existing account but provider not linked' do
    existing = Person.create(name: 'Alice', email: 'alice@acme.co')
    TeamMembership.create(team_id: @team.id, person_id: existing.id)

    resp = driver.oauth_callback(provider: 'github',
      uid: '789', email: 'alice@acme.co', name: 'Alice')
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
    assert_nil PersonIdentity.where(person_id: existing.id, provider: 'github').first
    assert_equal 1, Person.where(email_bidx: BlindIndex.generate_bidx('alice@acme.co', key: Lockbox.master_key)).count
  end

  it 'blocks unlinked provider even when another provider exists with same email' do
    existing = Person.create(name: 'Alice', email: 'alice@acme.co')
    TeamMembership.create(team_id: @team.id, person_id: existing.id)
    PersonIdentity.create(
      person_id: existing.id, provider: 'github',
      provider_subject: 'gh-100', email: 'alice@acme.co'
    )

    resp = driver.oauth_callback(provider: 'gitlab',
      uid: 'gl-200', email: 'alice@acme.co', name: 'Alice')
    resp = driver.follow_redirect if resp.redirect?

    assert_error_shown(resp.body)
    assert_nil PersonIdentity.where(person_id: existing.id, provider: 'gitlab').first
    assert_equal 1, PersonIdentity.where(person_id: existing.id).count
  end

  it 'matches on provider subject when email changes at provider' do
    existing = Person.create(name: 'Alice', email: 'alice@old.co')
    TeamMembership.create(team_id: @team.id, person_id: existing.id)
    PersonIdentity.create(
      person_id: existing.id, provider: 'github',
      provider_subject: '789', email: 'alice@old.co'
    )

    driver.oauth_callback(provider: 'github',
      uid: '789', email: 'alice@new.co', name: 'Alice')

    assert_equal 1, PersonIdentity.where(provider: 'github', provider_subject: '789').count
    identity = PersonIdentity.where(provider: 'github', provider_subject: '789').first

    assert_equal existing.id, identity.person_id
  end

  it 'does not match a different account when provider email collides' do
    alice = Person.create(name: 'Alice', email: 'shared@acme.co')
    TeamMembership.create(team_id: @team.id, person_id: alice.id)
    PersonIdentity.create(
      person_id: alice.id, provider: 'google_oauth2',
      provider_subject: 'google-111', email: 'shared@acme.co'
    )

    bob = Person.create(name: 'Bob', email: 'bob@other.co')
    PersonIdentity.create(
      person_id: bob.id, provider: 'github',
      provider_subject: 'gh-222', email: 'bob@other.co'
    )

    driver.oauth_callback(provider: 'github',
      uid: 'gh-222', email: 'shared@acme.co', name: 'Bob')

    identity = PersonIdentity.where(provider: 'github', provider_subject: 'gh-222').first

    assert_equal bob.id, identity.person_id
  end

  it 'rejects GET requests to OAuth request phase' do
    err = assert_raises(RuntimeError) { driver.get '/auth/google_oauth2' }
    assert_includes err.message, '404'
  end

  it 'returns 403 for non-member accessing a team' do
    outsider = Person.create(name: 'Eve', email: 'eve@evil.co')
    login_as(outsider)

    resp = driver.visit_team_dashboard(@team)

    assert_equal 403, resp.status
  end

  it 'user dropdown includes tutorial link' do
    alice = add_person(name: 'Alice')
    login_as(alice)

    resp = driver.visit_team_dashboard(@team)

    assert_includes resp.body, 'href="https://mainline.dev/docs/tutorial"'
  end

  it 'shows team picker when person has one team' do
    alice = add_person(name: 'Alice')
    login_as(alice)

    resp = driver.visit_teams

    assert_equal 200, resp.status
    assert_includes resp.body, @team.name
  end

  it 'shows team picker when person has multiple teams' do
    alice = add_person(name: 'Alice')
    other_team = Team.create(name: 'Other Team')
    TeamMembership.create(team_id: other_team.id, person_id: alice.id)
    login_as(alice)

    resp = driver.visit_teams

    assert_equal 200, resp.status
    assert_includes resp.body, 'Test Team'
    assert_includes resp.body, 'Other Team'
    assert_includes resp.body, 'href="/teams/new"'
  end

  it 'shows map and member counts on team picker' do
    alice = add_person(name: 'Alice')
    other_team = Team.create(name: 'Other Team')
    TeamMembership.create(team_id: other_team.id, person_id: alice.id)
    login_as(alice)

    resp = driver.visit_teams

    assert_includes resp.body, 'data-test-id="team-map-count" data-count="1"'
    assert_includes resp.body, 'Alice'
  end

  it 'clears session on logout' do
    alice = add_person(name: 'Alice')
    login_as(alice)

    resp = driver.submit_logout

    assert_equal 302, resp.status
    assert_equal '/', URI.parse(resp['Location']).path

    resp = driver.visit_map(@map)

    assert_equal 302, resp.status
    assert_equal '/login', URI.parse(resp['Location']).path
  end

  it 'sets RLS context when accessing a team' do
    alice = add_person(name: 'Alice')
    login_as(alice)

    driver.visit_team_dashboard(@team)

    current = DB.get(Sequel.lit("current_setting('app.current_team_id', true)"))

    assert_equal @team.id, current
  end

  describe 'connected providers' do
    before do
      @alice = add_person(name: 'Alice', email: 'alice@acme.co')
      PersonIdentity.create(
        person_id: @alice.id, provider: 'github',
        provider_subject: 'gh-100', email: 'alice@acme.co'
      )
      login_as(@alice)
    end

    it 'shows connected providers page' do
      resp = driver.get '/profile/providers'

      assert_equal 200, resp.status
      assert_includes resp.body, 'GitHub'
      assert_includes resp.body, 'data-test-id="provider-github"'
    end

    it 'neither offers nor connects a provider whose client id is disabled' do
      was = ENV.fetch('GITLAB_CLIENT_ID')
      ENV['GITLAB_CLIENT_ID'] = 'disabled'

      refute_includes driver.get('/profile/providers').body, 'action="/profile/providers/connect/gitlab"'
      err = assert_raises(RuntimeError) { driver.post '/profile/providers/connect/gitlab' }
      assert_includes err.message, '404'
    ensure
      ENV['GITLAB_CLIENT_ID'] = was
    end

    it 'connect links new provider to logged-in user' do
      driver.post '/profile/providers/connect/gitlab'
      driver.oauth_callback(
        provider: 'gitlab', uid: 'gl-300',
        email: 'different@email.co', name: 'Alice'
      )

      assert_equal 2, PersonIdentity.where(person_id: @alice.id).count
      gl = PersonIdentity.where(person_id: @alice.id, provider: 'gitlab').first

      refute_nil gl
      assert_equal 'gl-300', gl.provider_subject
    end

    it 'returns 404 for a non-UUID identity id on disconnect' do
      err = assert_raises(RuntimeError) { driver.post '/profile/providers/b3404700/disconnect' }

      assert_match(/404/, err.message)
    end

    it 'disconnect removes a provider identity' do
      PersonIdentity.create(
        person_id: @alice.id, provider: 'gitlab',
        provider_subject: 'gl-300', email: 'alice@acme.co'
      )
      gitlab_id = PersonIdentity.where(
        person_id: @alice.id, provider: 'gitlab'
      ).first

      resp = driver.post "/profile/providers/#{gitlab_id.id}/disconnect"

      assert_equal 302, resp.status
      assert_nil PersonIdentity[gitlab_id.id]
      assert_equal 1, PersonIdentity.where(person_id: @alice.id).count
    end

    it 'refuses to disconnect last provider' do
      identity = PersonIdentity.where(person_id: @alice.id).first

      resp = driver.post "/profile/providers/#{identity.id}/disconnect"

      assert_equal 302, resp.status
      refute_nil PersonIdentity[identity.id]
    end

    it 'refuses to connect provider UID already linked to another person' do
      bob = add_person(name: 'Bob', email: 'bob@acme.co')
      PersonIdentity.create(
        person_id: bob.id, provider: 'gitlab',
        provider_subject: 'gl-999', email: 'bob@acme.co'
      )

      driver.post '/profile/providers/connect/gitlab'
      resp = driver.oauth_callback(
        provider: 'gitlab', uid: 'gl-999',
        email: 'bob@acme.co', name: 'Bob'
      )
      resp = driver.follow_redirect if resp.redirect?

      assert_error_shown(resp.body)
      assert_equal 1, PersonIdentity.where(person_id: @alice.id).count
    end

    it 'refuses to connect provider whose email belongs to another person' do
      bob = add_person(name: 'Bob', email: 'bob@acme.co')
      PersonIdentity.create(
        person_id: bob.id, provider: 'google_oauth2',
        provider_subject: 'g-888', email: 'bob@acme.co'
      )

      driver.post '/profile/providers/connect/gitlab'
      resp = driver.oauth_callback(
        provider: 'gitlab', uid: 'gl-new',
        email: 'bob@acme.co', name: 'Alice'
      )
      resp = driver.follow_redirect if resp.redirect?

      assert_error_shown(resp.body)
      assert_equal 1, PersonIdentity.where(person_id: @alice.id).count
      assert_nil PersonIdentity.where(provider: 'gitlab', provider_subject: 'gl-new').first
    end

    it 'cannot disconnect another users provider' do
      bob = add_person(name: 'Bob', email: 'bob@acme.co')
      bob_identity = PersonIdentity.create(
        person_id: bob.id, provider: 'google_oauth2',
        provider_subject: 'g-999', email: 'bob@acme.co'
      )

      resp = driver.post "/profile/providers/#{bob_identity.id}/disconnect"

      assert_equal 302, resp.status
      refute_nil PersonIdentity[bob_identity.id]
    end
  end
end

describe 'Delete account' do
  include MainlineDSL

  before do
    @person = Person.create(name: 'Loner', email: 'loner@acme.co', email_verified_at: Time.now)
    PersonIdentity.create(
      person_id: @person.id, provider: 'google_oauth2',
      provider_subject: 'g-loner', email: 'loner@acme.co'
    )
    login_as(@person)
  end

  it 'shows delete account option on profile when user has no teams' do
    resp = driver.get '/profile/edit'

    assert_equal 200, resp.status
    assert_includes resp.body, 'data-test-id="delete-account"'
  end

  it 'deletes account and redirects to login' do
    resp = driver.post '/profile/delete-account'

    assert_equal 302, resp.status
    assert_equal '/login', URI.parse(resp['Location']).path
    assert_nil Person[@person.id]
    assert_equal 0, PersonIdentity.where(person_id: @person.id).count
  end

  it 'deletes account even with old left memberships' do
    setup_team
    TeamMembership.create(team_id: @team.id, person_id: @person.id, left_at: Time.now)

    resp = driver.post '/profile/delete-account'

    assert_equal 302, resp.status
    assert_equal '/login', URI.parse(resp['Location']).path
    assert_nil Person[@person.id]
    assert_equal 0, TeamMembership.where(person_id: @person.id).count
  end

  it 'deletes account when person created stories' do
    setup_team
    create_map
    TeamMembership.create(team_id: @team.id, person_id: @person.id, left_at: Time.now)
    pid = SecureRandom.uuid
    aid = SecureRandom.uuid
    tid = SecureRandom.uuid
    sid = SecureRandom.uuid
    DB[:personas].insert(id: pid, map_id: @map.id, team_id: @team.id, name: 'P', position: 1000)
    DB[:activities].insert(id: aid, map_id: @map.id, team_id: @team.id, name: 'A', position: 1000)
    DB[:activity_personas].insert(activity_id: aid, persona_id: pid, team_id: @team.id)
    DB[:tasks].insert(id: tid, map_id: @map.id, activity_id: aid, team_id: @team.id, name: 'T', position: 1000)
    DB[:stories].insert(
      id: sid, map_id: @map.id, task_id: tid, team_id: @team.id,
      title: 'S', status: 'planned', created_by_id: @person.id, position: 1000
    )

    resp = driver.post '/profile/delete-account'

    assert_equal 302, resp.status
    assert_nil Person[@person.id]
    assert_nil DB[:stories].where(id: sid).get(:created_by_id)
  end

  it 'deletes account when person sent invitations' do
    setup_team
    TeamMembership.create(team_id: @team.id, person_id: @person.id, left_at: Time.now)
    invitation = Invitation.create(
      team_id: @team.id, invited_by: @person.id,
      email: 'someone@acme.co', token: SecureRandom.hex(16),
      expires_at: Time.now + 86_400
    )

    resp = driver.post '/profile/delete-account'

    assert_equal 302, resp.status
    assert_nil Person[@person.id]

    SetTeamContext.call(@team.id)
    invitation.reload

    assert_nil invitation.invited_by
  end

  it 'hides delete account option when user has a team' do
    setup_team
    TeamMembership.create(team_id: @team.id, person_id: @person.id)

    resp = driver.get '/profile/edit'

    assert_equal 200, resp.status
    refute_includes resp.body, 'data-test-id="delete-account"'
  end

  it 'refuses to delete account when user has a team' do
    setup_team
    TeamMembership.create(team_id: @team.id, person_id: @person.id)

    resp = driver.post '/profile/delete-account'

    assert_equal 302, resp.status
    refute_nil Person[@person.id]
  end
end
