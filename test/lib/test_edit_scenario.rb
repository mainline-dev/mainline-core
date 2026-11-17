# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/add_scenario'
require_relative '../../lib/edit_scenario'

describe EditScenario do
  cover 'EditScenario*'

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

  def edit(name: 'Guest pays by email', given: 'a basket', when_text: 'they pay', then_text: 'it is paid')
    EditScenario.call(story: @story, scenario: @scenario, actor: @person.actor, name: name, given_text: given,
      when_text: when_text, then_text: then_text)
  end

  def parts(scenario)
    scenario.refresh.values.values_at(:name, :given_text, :when_text, :then_text)
  end

  it 'saves a changed scenario and records it' do
    result = edit(name: 'Guest pays by card', given: 'a full basket', when_text: 'they pay by card', then_text: 'it is charged')

    assert_equal [true, []], [result.success?, result.errors]
    assert_equal ['Guest pays by card', 'a full basket', 'they pay by card', 'it is charged'], parts(@scenario)
    assert_equal ['Guest gets a receipt', 'a basket', 'they pay', 'it is paid'], parts(@other)
    assert_equal 1, recorded('scenario_edited')
  end

  it 'records nothing when the edit changes nothing' do
    result = edit

    assert_equal [true, []], [result.success?, result.errors]
    assert_equal 0, recorded('scenario_edited')
  end

  it 'refuses a part missing or too long, saying what, and changes nothing' do
    result = edit(given: '', then_text: 'x' * (AddScenario::MAX_LENGTH + 1))

    assert_equal [false, AddScenario.errors('Guest pays by email', '', 'they pay', 'x' * (AddScenario::MAX_LENGTH + 1))],
      [result.success?, result.errors]
    assert_equal ['Guest pays by email', 'a basket', 'they pay', 'it is paid'], parts(@scenario)
    assert_equal 0, recorded('scenario_edited')
  end

  it "leaves a released story's scenario as it is" do
    release_the_story

    result = edit(name: 'Guest pays by card')

    assert_equal [false, []], [result.success?, result.errors]
    assert_equal 'Guest pays by email', @scenario.refresh.name
    assert_equal 0, recorded('scenario_edited')
  end
end
