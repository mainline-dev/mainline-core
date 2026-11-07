# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Closed sign-ups' do
  include MainlineDSL

  before do
    AUTH_RATE_LIMITER.reset
    @was = ENV.fetch('SIGNUPS')
    ENV['SIGNUPS'] = 'closed'
  end

  after do
    ENV['SIGNUPS'] = @was
  end

  def sign_up(email)
    driver.submit_email_signup(name: 'Newcomer', email: email, password: 'longpassword12')
  end

  def invite(email)
    team = Team.create(name: 'Invite Team')
    SetTeamContext.call(team.id)
    inviter = driver.add_person(team, name: 'Boss', email: 'boss@acme.co')
    Invitation.create(
      team_id: team.id, email: email, invited_by: inviter.id,
      token: InviteToken.digest('closed-invite'), expires_at: Time.now + 86_400
    )
  end

  it 'lets the first person sign up on an empty install' do
    sign_up('first@acme.co')

    refute_nil Person.find_by_email('first@acme.co')
  end

  describe 'once someone has an account' do
    before do
      @team = setup_team
      @alice = driver.add_person(@team, name: 'Alice', email: 'alice@acme.co')
    end

    it 'refuses an email sign-up' do
      sign_up('stranger@acme.co')

      assert_nil Person.find_by_email('stranger@acme.co')
    end

    it 'treats anything other than open as closed' do
      ENV['SIGNUPS'] = 'opne'

      sign_up('stranger@acme.co')

      assert_nil Person.find_by_email('stranger@acme.co')
    end

    it 'refuses a sign-up through a sign-in provider' do
      driver.oauth_signup(provider: 'github', uid: 'gh-stranger', email: 'stranger@acme.co', name: 'Stranger')

      assert_nil Person.find_by_email('stranger@acme.co')
    end

    it 'still lets people with an account sign in through a provider' do
      PersonIdentity.create(person_id: @alice.id, provider: 'github', provider_subject: 'gh-alice', email: 'alice@acme.co')

      resp = driver.oauth_callback(provider: 'github', uid: 'gh-alice', email: 'alice@acme.co', name: 'Alice')

      assert_equal 302, resp.status
      refute_equal '/confirm-email', URI.parse(resp['Location']).path
    end

    it 'shows that sign-ups are closed instead of the form' do
      body = driver.get('/signup').body

      assert_shown('signups-closed', body)
      refute_shown('email-signup-form', body)
    end

    it 'does not offer sign-up from the login page' do
      refute_shown('login-signup', driver.visit_login.body)
    end

    it 'lets an invited person sign up with the invited address' do
      invite('invitee@acme.co')
      driver.get '/invite/closed-invite'

      sign_up('invitee@acme.co')

      refute_nil Person.find_by_email('invitee@acme.co')
    end

    it 'lets an invited person sign up through a provider' do
      invite('invitee@acme.co')
      driver.get '/invite/closed-invite'

      driver.oauth_signup(provider: 'github', uid: 'gh-invitee', email: 'invitee@acme.co', name: 'Invitee')

      refute_nil Person.find_by_email('invitee@acme.co')
    end

    it 'shows the form to someone holding an invite' do
      invite('invitee@acme.co')
      driver.get '/invite/closed-invite'

      assert_shown('email-signup-form', driver.get('/signup').body)
    end

    it 'refuses a different address on an invite' do
      invite('invitee@acme.co')
      driver.get '/invite/closed-invite'

      sign_up('stranger@acme.co')

      assert_nil Person.find_by_email('stranger@acme.co')
    end

    it 'refuses an expired invite' do
      invite('invitee@acme.co').update(expires_at: Time.now - 60)

      sign_up('invitee@acme.co')

      assert_nil Person.find_by_email('invitee@acme.co')
    end
  end
end
