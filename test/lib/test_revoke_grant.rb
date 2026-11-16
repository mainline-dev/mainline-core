# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/create_personal_token'
require_relative '../../lib/revoke_grant'

describe RevokeGrant do
  cover 'RevokeGrant*'

  before do
    @team = Team.create(name: 'Payments')
    @alice = Person.create(name: 'Alice', email: 'alice@revoke.co')
    @bob = Person.create(name: 'Bob', email: 'bob@revoke.co')
    [@alice, @bob].each { |person| TeamMembership.create(team_id: @team.id, person_id: person.id, working: true) }
  end

  def grant_of(person)
    token = CreatePersonalToken.call(person: person, name: 'laptop', team_ids: [@team.id], expires_on: Date.today + 30)
    OauthGrant[OauthAccessToken.first(token_hash: PersonalToken.digest(token.token)).grant_id]
  end

  it 'revokes a grant of the person, once' do
    grant = grant_of(@alice)

    assert RevokeGrant.call(person: @alice, grant_id: grant.id, now: Time.utc(2030, 1, 1))
    refute RevokeGrant.call(person: @alice, grant_id: grant.id)
    assert_equal Time.utc(2030, 1, 1), grant.refresh.revoked_at
  end

  it "revokes only the grant named, not the person's others" do
    revoked = grant_of(@alice)
    kept = grant_of(@alice)

    RevokeGrant.call(person: @alice, grant_id: revoked.id)

    assert_nil kept.refresh.revoked_at
  end

  it "leaves someone else's grant alone" do
    grant = grant_of(@bob)

    refute RevokeGrant.call(person: @alice, grant_id: grant.id)
    assert_nil grant.refresh.revoked_at
  end

  it 'turns away anything that is not a grant ID without asking the database' do
    refute RevokeGrant.call(person: @alice, grant_id: 'not-an-id')
    refute RevokeGrant.call(person: @alice, grant_id: nil)
  end

  it 'revokes now by default' do
    grant = grant_of(@alice)

    RevokeGrant.call(person: @alice, grant_id: grant.id)

    assert_in_delta Time.now, grant.refresh.revoked_at, 5
  end
end
