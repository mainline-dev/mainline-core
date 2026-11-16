# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/create_personal_token'
require_relative '../../lib/delete_person'

describe DeletePerson do
  it "deletes the person's personal tokens with them" do
    team = Team.create(name: 'Left')
    alice = Person.create(name: 'Alice', email: 'alice@deleted.co')
    TeamMembership.create(team_id: team.id, person_id: alice.id, working: true)
    token = CreatePersonalToken.call(person: alice, name: 'laptop', team_ids: [team.id], expires_on: Date.today + 30)
    TeamMembership.where(person_id: alice.id).update(left_at: Time.now)

    DeletePerson.call(person: alice)

    counts = BypassRLS.call {
      [OauthGrant.where(person_id: alice.id).count, OauthGrantTeam.where(team_id: team.id).count,
       OauthAccessToken.where(token_hash: PersonalToken.digest(token.token)).count]
    }

    assert_equal [0, 0, 0], counts
  end
end
