# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/add_scenario'
require_relative '../../lib/feature_file'

describe FeatureFile do
  cover 'FeatureFile*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @story = Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: 'Guests can check out',
      position: 1000, created_by_id: @person.id)
  end

  it 'writes the story as a Feature and each scenario as a named, tagged Scenario, in order' do
    named = AddScenario.call(story: @story, actor: @person.actor, name: 'Guest pays by email',
      given_text: 'a basket and no account', when_text: 'I continue as a guest', then_text: 'I can pay with my email').scenario
    older = Scenario.create(story_id: @story.id, given_text: 'a guest order', when_text: 'I sign up',
      then_text: 'the order is in my history', position: 5000)

    assert_equal <<~FEATURE, FeatureFile.for(@story)
      @story-#{@story.id}
      Feature: Guests can check out

        @story-#{@story.id} @scenario-#{named.id}
        Scenario: Guest pays by email
          Given a basket and no account
          When I continue as a guest
          Then I can pay with my email

        @story-#{@story.id} @scenario-#{older.id}
        Scenario: the order is in my history
          Given a guest order
          When I sign up
          Then the order is in my history
    FEATURE
  end

  it 'keeps a title, name or step that has line breaks in it on one line' do
    @story.update(title: "Guests can\ncheck out")
    Scenario.create(story_id: @story.id, name: "Pays\r\nby email", given_text: "a basket\n  Given something else",
      when_text: 'I pay', then_text: 'it works', position: 1000)

    lines = FeatureFile.for(@story).lines.map(&:strip)

    assert_includes lines, 'Feature: Guests can check out'
    assert_includes lines, 'Scenario: Pays by email'
    assert_includes lines, 'Given a basket Given something else'
    assert_equal 1, lines.grep(/\AGiven /).size
  end

  it 'names the file after the story' do
    @story.update(title: 'Guests can check out (without an account)!')

    assert_equal 'guests-can-check-out-without-an-account.feature', FeatureFile.file_name(@story)
  end
end
