# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Account holder separation' do
  include MainlineDSL

  before do
    setup_team
    create_map
  end

  describe 'routing' do
    it 'routes account holder to workspace in read mode' do
      holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
      TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
      login_as(holder)

      resp = driver.visit_team_dashboard(@team)

      assert_equal 200, resp.status
      assert_shown('team-maps', resp.body)
      refute_includes resp.body, 'href="/maps/new"'
    end

    it 'routes working member to full team dashboard' do
      alice = add_person(name: 'Alice')
      login_as(alice)

      resp = driver.visit_team_dashboard(@team)

      assert_equal 200, resp.status
      assert_shown('team-maps', resp.body)
    end

    it 'account holder cannot see maps or charts' do
      holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
      TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
      login_as(holder)

      resp = driver.visit_map(@map)

      assert_equal 302, resp.status
      assert_includes resp['Location'], '/account'
    end
  end

  describe 'invitations' do
    it 'invitee joins team when invite token and OAuth email both match' do
      holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
      TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
      token = SecureRandom.urlsafe_base64(32)
      invite = Invitation.create(
        team_id: @team.id, email: 'dev@corp.co',
        token: InviteToken.digest(token),
        invited_by: holder.id,
        expires_at: Time.now + (86_400 * 7)
      )

      driver.visit_invite(token)
      driver.oauth_callback(
        provider: 'google_oauth2', uid: '999',
        email: 'dev@corp.co', name: 'Dev'
      )
      resp = driver.get '/confirm-email'
      verify_token = resp.body[%r{/verify-email/([^"<]+)}, 1]
      driver.post "/verify-email/#{verify_token}"

      person = Person.find_by_email('dev@corp.co')

      refute_nil person
      membership = TeamMembership.where(team_id: @team.id, person_id: person.id).first

      refute_nil membership, 'Membership was not created'
      assert membership.working, 'Invitee should be a working member'
      SetTeamContext.call(@team.id)
      invite.refresh

      refute_nil invite.accepted_at
    end

    it 'rejects OAuth when email does not match invite token' do
      holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
      TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
      token = SecureRandom.urlsafe_base64(32)
      invite = Invitation.create(
        team_id: @team.id, email: 'dev@corp.co',
        token: InviteToken.digest(token),
        invited_by: holder.id,
        expires_at: Time.now + (86_400 * 7)
      )

      driver.visit_invite(token)
      driver.oauth_callback(
        provider: 'google_oauth2', uid: '888',
        email: 'impostor@evil.co', name: 'Impostor'
      )
      resp = driver.get '/confirm-email'
      verify_token = resp.body[%r{/verify-email/([^"<]+)}, 1]
      driver.post "/verify-email/#{verify_token}"

      person = Person.find_by_email('impostor@evil.co')
      membership = TeamMembership.where(team_id: @team.id, person_id: person.id).first

      assert_nil membership, 'Wrong email must not join the team'
      SetTeamContext.call(@team.id)
      invite.refresh

      assert_nil invite.accepted_at
    end

    it 'rejects OAuth when no invite token in session' do
      holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
      TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
      Invitation.create(
        team_id: @team.id, email: 'dev@corp.co',
        token: SecureRandom.urlsafe_base64(32),
        invited_by: holder.id,
        expires_at: Time.now + (86_400 * 7)
      )

      driver.oauth_callback(
        provider: 'google_oauth2', uid: '999',
        email: 'dev@corp.co', name: 'Dev'
      )
      resp = driver.get '/confirm-email'
      verify_token = resp.body[%r{/verify-email/([^"<]+)}, 1]
      driver.post "/verify-email/#{verify_token}"

      person = Person.find_by_email('dev@corp.co')
      membership = TeamMembership.where(team_id: @team.id, person_id: person.id).first

      assert_nil membership, 'Must not join without clicking invite link'
    end
  end

  describe 'opt-in' do
    it 'account holder can join team as working member' do
      holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
      TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
      login_as(holder)

      resp = driver.submit_join_team(@team)

      assert_predicate resp, :redirect?
      membership = TeamMembership.where(team_id: @team.id, person_id: holder.id).first

      assert membership.working, 'Should now be a working member'
    end

    it 'creator can access account panel even after joining as working member' do
      holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
      TeamMembership.create(team_id: @team.id, person_id: holder.id, working: true)
      @team.update(creator_id: holder.id)
      login_as(holder)

      resp = driver.visit_account(@team)

      assert_equal 200, resp.status
      assert_shown('account-page', resp.body)
    end
  end
end
