# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/add_scenario'

describe AddScenario do
  cover 'AddScenario*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @story = Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: 'Guest checkout', position: 1000,
      created_by_id: @person.id)
  end

  def add(name: 'Guest pays by email', given: 'a basket and no account', when_text: 'I continue as a guest',
          then_text: 'I can pay with my email')
    AddScenario.call(story: @story, actor: @person.actor, name: name, given_text: given, when_text: when_text,
      then_text: then_text)
  end

  it 'adds a scenario after the others and records it' do
    first = add.scenario
    second = add(given: 'a saved basket').scenario

    assert_operator second.position, :>, first.position
    assert_equal ['a saved basket', 'I continue as a guest', 'I can pay with my email'],
      [second.given_text, second.when_text, second.then_text]
    assert_equal 2, Event.where(entity_id: @story.id, action: 'scenario_added').count
  end

  it 'refuses a scenario missing a part or with a part over 100 characters' do
    refute_predicate add(given: ''), :success?
    refute_predicate add(then_text: 'x' * 101), :success?
    assert_equal 0, Scenario.where(story_id: @story.id).count
  end

  it 'keeps the name and refuses a scenario without one, or with one over 80 characters' do
    assert_equal 'Guest pays by email', add.scenario.name
    refute_predicate add(name: ''), :success?
    refute_predicate add(name: 'x' * 81), :success?
    assert_equal 1, Scenario.where(story_id: @story.id).count
  end
end
