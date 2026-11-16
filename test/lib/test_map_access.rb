# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/map_access'

describe MapAccess do
  cover 'MapAccess*'

  before do
    @team = Team.create(name: 'Maps Team')
    @other = Team.create(name: 'Other Team')
    SetTeamContext.call(@team.id)
    @alice = Person.create(name: 'Alice', email: 'alice@access.co')
  end

  def join(team, working: true, left_at: nil)
    TeamMembership.create(team_id: team.id, person_id: @alice.id, working: working, left_at: left_at)
  end

  it "opens a team's maps to someone working on it" do
    assert MapAccess.open_to?(join(@team))
  end

  it 'keeps them from someone who observes the team' do
    refute MapAccess.open_to?(join(@team, working: false))
  end

  it 'keeps them from someone who has left the team, and from someone who never joined' do
    refute MapAccess.open_to?(join(@team, left_at: Time.now))
    refute MapAccess.open_to?(nil)
  end

  it 'lists the teams whose maps are open to a person, and no others' do
    join(@team)
    join(@other, working: false)
    third = Team.create(name: 'Third Team')
    join(third, left_at: Time.now)

    assert_equal [@team.id], MapAccess.team_ids_for(@alice.id)
  end

  it 'leaves out teams other people work on' do
    bob = Person.create(name: 'Bob', email: 'bob@access.co')
    TeamMembership.create(team_id: @other.id, person_id: bob.id, working: true)

    assert_empty MapAccess.team_ids_for(@alice.id)
  end
end
