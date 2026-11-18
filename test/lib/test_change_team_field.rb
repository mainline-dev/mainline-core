# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/change_team_field'

describe ChangeTeamField do
  cover 'ChangeTeamField*'

  before do
    @team = Team.create(name: 'Payments')
    @other = Team.create(name: 'Mobile')
    SetTeamContext.call(@team.id)
    @alice = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @timezone = @team.refresh.timezone
  end

  def change(field, value)
    ChangeTeamField.call(team: @team, actor: @alice.actor, field: field, value: value)
  end

  def events
    Event.where(team_id: @team.id, entity_type: 'team', action: 'updated').order(:event_no).all
  end

  it "changes the team's timezone, and records what it was and became, on the team, by whoever changed it" do
    change(:timezone, 'Australia/Sydney')
    recorded_on = events.map { |event| [event.entity_id, event.actor_id] }

    assert_equal ['Australia/Sydney', @timezone], [@team.refresh.timezone, @other.refresh.timezone]
    assert_equal [[@team.id, @alice.actor.id]], recorded_on
    assert_equal [{ 'timezone' => @timezone }, { 'timezone' => 'Australia/Sydney' }],
      [events.first.before_state, events.first.after_state]
  end

  it "sets the team's holiday region, and clears it again, recording each" do
    change(:holiday_region, 'au_nsw')
    set = @team.refresh.holiday_region
    change(:holiday_region, nil)
    recorded = events.map { |event| [event.before_state['holiday_region'], event.after_state['holiday_region']] }

    assert_equal ['au_nsw', nil], [set, @team.refresh.holiday_region]
    assert_equal [[nil, 'au_nsw'], ['au_nsw', nil]], recorded
  end

  it 'records nothing for a setting saved as it already was' do
    change(:timezone, @timezone)
    change(:holiday_region, nil)

    assert_empty events
  end

  it 'changes nothing else about a team, such as its name or who holds its account' do
    refused = %i[name creator_id suspended_at].map { |field|
      assert_raises(ArgumentError) { change(field, 'anything') }
    }

    assert_equal 3, refused.size
    assert_equal 'Payments', @team.refresh.name
    assert_empty events
  end
end
