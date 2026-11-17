# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/add_scenario'
require_relative '../../lib/mark_scenario'

describe MarkScenario do
  cover 'MarkScenario*'

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

  it 'marks a scenario done at the time given, once, recording it' do
    at = Time.utc(2030, 1, 7, 9)

    first = MarkScenario.done(story: @story, scenario: @scenario, actor: @person.actor, now: at)
    again = MarkScenario.done(story: @story, scenario: @scenario.refresh, actor: @person.actor, now: at + 60)

    assert_equal [true, false], [first.success?, again.success?]
    assert_equal [at, nil], [@scenario.refresh.done_at, @other.refresh.done_at]
    assert_equal 1, recorded('scenario_done')
  end

  it 'marks a done scenario not done, once, recording it' do
    MarkScenario.done(story: @story, scenario: @scenario, actor: @person.actor, now: Time.now)

    first = MarkScenario.undone(story: @story, scenario: @scenario.refresh, actor: @person.actor)
    again = MarkScenario.undone(story: @story, scenario: @scenario.refresh, actor: @person.actor)

    assert_equal [true, false], [first.success?, again.success?]
    assert_nil @scenario.refresh.done_at
    assert_equal 1, recorded('scenario_undone')
  end

  it "changes nothing on a released story's scenarios" do
    MarkScenario.done(story: @story, scenario: @other, actor: @person.actor, now: Time.now)
    release_the_story

    done = MarkScenario.done(story: @story, scenario: @scenario, actor: @person.actor, now: Time.now)
    undone = MarkScenario.undone(story: @story, scenario: @other.refresh, actor: @person.actor)

    assert_equal [false, false], [done.success?, undone.success?]
    assert_nil @scenario.refresh.done_at
    refute_nil @other.refresh.done_at
    assert_equal [1, 0], [recorded('scenario_done'), recorded('scenario_undone')]
  end
end
