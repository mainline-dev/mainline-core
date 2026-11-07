# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Invite email delivery' do
  include MainlineDSL

  before do
    setup_team
  end

  it 'invite link shows login page with team and inviter context' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    login_as(holder)
    resp = driver.submit_invite(@team, email: 'dev@corp.co')
    resp = driver.follow_invite_redirect if resp.redirect?
    link_token = resp.body[%r{/invite/([^"<\s]+)}, 1]

    invite = Invitation.where(team_id: @team.id).first

    refute_nil invite

    resp = driver.visit_invite(link_token)

    assert_equal 200, resp.status
    assert_includes resp.body, @team.name
    assert_includes resp.body, holder.name
    assert_includes resp.body, 'action="/auth/google_oauth2"'
  end

  it 'invite page shows email login form' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    login_as(holder)
    resp = driver.submit_invite(@team, email: 'dev@corp.co')
    resp = driver.follow_invite_redirect if resp.redirect?
    link_token = resp.body[%r{/invite/([^"<\s]+)}, 1]

    resp = driver.visit_invite(link_token)

    assert_includes resp.body, 'data-test-id="email-login-form"'
  end

  it 'expired invite shows error' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    token = SecureRandom.urlsafe_base64
    Invitation.create(
      team_id: @team.id, email: 'dev@corp.co',
      token: InviteToken.digest(token),
      invited_by: holder.id,
      expires_at: Time.now - 1
    )

    resp = driver.visit_invite(token)

    assert_equal 200, resp.status
    assert_shown('invite-invalid', resp.body)
  end

  it 'accepted invite shows error' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    token = SecureRandom.urlsafe_base64
    Invitation.create(
      team_id: @team.id, email: 'dev@corp.co',
      token: InviteToken.digest(token),
      invited_by: holder.id,
      expires_at: Time.now + (86_400 * 7),
      accepted_at: Time.now
    )

    resp = driver.visit_invite(token)

    assert_equal 200, resp.status
    assert_shown('invite-invalid', resp.body)
  end

  it 'reactivates archived member on re-invite acceptance' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    @team.update(creator_id: holder.id)

    worker = add_person(name: 'Dev', email: 'dev@corp.co')
    PersonIdentity.create(
      person_id: worker.id, provider: 'google_oauth2',
      provider_subject: 'dev-uid', email: 'dev@corp.co'
    )
    TeamMembership.where(team_id: @team.id, person_id: worker.id)
      .update(working: true)

    login_as(holder)
    driver.post "/teams/#{@team.id}/members/#{worker.id}/archive"

    membership = TeamMembership.where(team_id: @team.id, person_id: worker.id).first

    refute_nil membership.left_at

    resp = driver.submit_invite(@team, email: 'dev@corp.co')
    resp = driver.follow_invite_redirect if resp.redirect?
    link_token = resp.body[%r{/invite/([^"<\s]+)}, 1]

    driver.visit_invite(link_token)
    driver.oauth_callback(provider: 'google_oauth2', uid: 'dev-uid', email: 'dev@corp.co', name: 'Dev')

    membership.reload

    assert_nil membership.left_at
    assert_predicate membership, :working
  end

  it 'does not store the invite token in plaintext' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    login_as(holder)

    resp = driver.submit_invite(@team, email: 'dev@corp.co')
    resp = driver.follow_invite_redirect if resp.redirect?
    link_token = resp.body[%r{/invite/([^"<\s]+)}, 1]

    refute_nil link_token

    SetTeamContext.call(@team.id)
    invite = Invitation.where(team_id: @team.id).first

    refute_equal link_token, invite.token

    resp = driver.visit_invite(link_token)

    assert_equal 200, resp.status
    assert_includes resp.body, @team.name
  end

  it 'shows an error and keeps no invitation when the email fails to send' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    login_as(holder)

    resp = SendInviteEmail.stub(:call, :failed) {
      driver.submit_invite(@team, email: 'dev@corp.co')
    }
    resp = driver.follow_invite_redirect if resp.redirect?

    assert_error_shown(resp.body)
    assert_nil Invitation.where(team_id: @team.id).first
  end

  it 'rate limits invite creation per team' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    login_as(holder)

    10.times { |i| driver.submit_invite(@team, email: "dev#{i}@corp.co") }
    response = driver.submit_invite(@team, email: 'one-too-many@corp.co')

    assert_equal 302, response.status
    bidx = BlindIndex.generate_bidx('one-too-many@corp.co', key: Lockbox.master_key)

    assert_nil Invitation.where(team_id: @team.id, email_bidx: bidx).first
  end

  it 'dev mode returns invite link from SendInviteEmail' do
    invite = Invitation.create(
      team_id: @team.id, email: 'dev@corp.co',
      token: 'test-token-abc',
      invited_by: Person.create(name: 'Buyer', email: 'buyer@corp.co').id,
      expires_at: Time.now + (86_400 * 7)
    )

    link = SendInviteEmail.call(
      invitation: invite,
      inviter:    Person[invite.invited_by],
      team:       @team,
      token:      'test-token-abc'
    )

    assert_equal 'http://localhost:3000/invite/test-token-abc', link
  end
end
