# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/accept_invite'

describe AcceptInvite do
  cover 'AcceptInvite*'

  before do
    @team = Team.create(name: 'Payments')
    SetTeamContext.call(@team.id)
    @inviter = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @bob = Person.create(name: 'Bob', email: 'bob@test.mainline')
    # Someone else on this team, and Bob on another, so only his place here counts.
    TeamMembership.create(team_id: @team.id, person_id: @inviter.id, working: true)
    TeamMembership.create(team_id: Team.create(name: 'Mobile').id, person_id: @bob.id, working: true)
    @invitation = invite('bob@test.mainline', 'bobs-link')
    @now = Time.utc(2030, 1, 7, 9)
  end

  def invite(email, token, expires_at: Time.now + 86_400)
    BypassRLS.call do
      Invitation.create(team_id: @team.id, email: email, token: InviteToken.digest(token), invited_by: @inviter.id,
        expires_at: expires_at)
    end
  end

  # Bob's memberships of the team: whether each is working, and when it ended.
  def memberships
    TeamMembership.where(team_id: @team.id, person_id: @bob.id).all.map { |membership| [membership.working, membership.left_at] }
  end

  def taken_up_at
    BypassRLS.call { @invitation.refresh.accepted_at }
  end

  def join
    AcceptInvite.join(invitation: @invitation, person: @bob, now: @now)
  end

  it 'finds the pending invitation for a link, sent to this email address' do
    assert_equal @invitation.id, AcceptInvite.invitation_for(token: 'bobs-link', email: 'bob@test.mainline').id
  end

  it 'finds nothing for another address, no link, a link nobody sent, or an invitation expired or taken up' do
    invite('carol@test.mainline', 'expired', expires_at: Time.now - 60)
    BypassRLS.call { invite('dan@test.mainline', 'taken').update(accepted_at: Time.now) }

    found = [['bobs-link', 'carol@test.mainline'], [nil, 'bob@test.mainline'], ['nobody-sent-this', 'bob@test.mainline'],
             ['expired', 'carol@test.mainline'], ['taken', 'dan@test.mainline']].map { |token, email|
      AcceptInvite.invitation_for(token: token, email: email)
    }

    assert_equal [nil], found.uniq
  end

  it 'makes the person a working member of the team and marks the invitation taken up' do
    join

    assert_equal [[true, nil]], memberships
    assert_equal @now, taken_up_at
  end

  it 'brings back someone who left the team, without a second membership' do
    TeamMembership.create(team_id: @team.id, person_id: @bob.id, working: false, left_at: Time.now)

    join

    assert_equal [[true, nil]], memberships
  end

  it 'leaves someone still on the team as they are' do
    TeamMembership.create(team_id: @team.id, person_id: @bob.id, working: false)

    join

    assert_equal [[false, nil]], memberships
  end
end
