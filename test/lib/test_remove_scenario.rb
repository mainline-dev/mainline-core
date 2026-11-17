# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/add_scenario'
require_relative '../../lib/remove_scenario'

describe RemoveScenario do
  cover 'RemoveScenario*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @story = Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: 'Guest checkout', position: 1000,
      created_by_id: @person.id)
    @scenario = scenario('Guest pays by email')
    @other = scenario('Guest gets a receipt')
  end

  def scenario(name)
    AddScenario.call(story: @story, actor: @person.actor, name: name, given_text: 'a basket', when_text: 'they pay',
      then_text: 'it is paid').scenario
  end

  def recorded(action)
    Event.where(entity_id: @story.id, action: action).count
  end

  def release_the_story
    @story.update(status: 'released', released_at: Time.now)
  end

  it 'removes the scenario from its story and records it, leaving the others' do
    result = RemoveScenario.call(story: @story, scenario: @scenario, actor: @person.actor)

    assert_predicate result, :success?
    assert_equal [@other.id], Scenario.where(story_id: @story.id).select_map(:id)
    assert_equal 1, recorded('scenario_removed')
  end

  it "leaves a released story's scenarios as they are, recording nothing" do
    release_the_story

    result = RemoveScenario.call(story: @story, scenario: @scenario, actor: @person.actor)

    assert_equal [false, 2], [result.success?, Scenario.where(story_id: @story.id).count]
    assert_equal 0, recorded('scenario_removed')
  end
end
