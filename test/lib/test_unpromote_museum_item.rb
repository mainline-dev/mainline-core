# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/promote_museum_item'
require_relative '../../lib/unpromote_museum_item'

describe UnpromoteMuseumItem do
  cover 'UnpromoteMuseumItem*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    @task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @item = MuseumItem.create(team_id: @team.id, source_key: 'SHOP-10', issue_type: 'Story', summary: 'Guest checkout')
    @story = PromoteMuseumItem.call(item: @item, team: @team, actor: @person.actor, person: @person,
      title: 'Buy without an account', task_id: @task.id,
      scenarios: [{ given: 'a basket', when: 'I continue as a guest', then: 'I can pay' }]).story
  end

  def unpromote(item = @item)
    UnpromoteMuseumItem.call(item: item.refresh, actor: @person.actor)
  end

  it 'sends an exhibit back to the museum, archiving a story nothing has happened to' do
    result = unpromote

    assert_predicate result, :success?
    assert_predicate result, :story_archived
    assert_equal [nil, nil], [@item.refresh.story_id, @item.promoted_at]
    assert @story.refresh.archived_at
    assert_equal 1, Event.where(entity_id: @item.id, action: 'unpromoted').count
  end

  it 'keeps the story when something has happened to it since' do
    AddScenario.call(story: @story, actor: @person.actor, given_text: 'a', when_text: 'b', then_text: 'c')

    result = unpromote

    refute_predicate result, :story_archived
    assert_nil @item.refresh.story_id
    assert_nil @story.refresh.archived_at
  end

  it 'keeps a story someone is working on' do
    StoryAssignment.create(story_id: @story.id, person_id: @person.id, team_id: @team.id)

    refute_predicate unpromote, :story_archived
    assert_nil @story.refresh.archived_at
  end

  it 'keeps a story another exhibit also went into' do
    MuseumItem.create(team_id: @team.id, source_key: 'SHOP-14', issue_type: 'Task', summary: 'Token', story_id: @story.id,
      promoted_at: Time.now)

    refute_predicate unpromote, :story_archived
    assert_nil @story.refresh.archived_at
  end

  it 'refuses an exhibit that is not promoted' do
    unpromote

    refute_predicate unpromote, :success?
  end
end
