# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/urgent_story'
require_relative '../../lib/record_event'

describe UrgentStory do
  cover 'UrgentStory*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Run the shop', position: 1000)
    @task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Operate', position: 1000)
  end

  def story(title, **attrs)
    Story.create(task_id: @task.id, map_id: @task.map_id, team_id: @team.id, title: title,
      position: (Story.max(:position) || 0) + 1000, created_by_id: @person.id, status: 'active', **attrs)
  end

  def mark(story)
    RecordEvent.call(actor_id: @person.actor.id, entity: story, action: UrgentStory::ACTION, after_state: { reason: 'Leak' })
  end

  it 'has none for a new team' do
    story('Rotate the key')

    assert_nil UrgentStory.of(@team)
  end

  it 'is the story marked urgent, until it is released' do
    patch = story('Rotate the key')
    mark(patch)

    assert_equal patch.id, UrgentStory.of(@team).id
    assert UrgentStory.urgent?(patch)
  end

  it 'has none once the urgent story is released' do
    patch = story('Rotate the key')
    mark(patch)
    patch.update(status: 'released', released_at: Time.now)

    assert_nil UrgentStory.of(@team)
    refute UrgentStory.urgent?(patch)
  end

  it 'has none once the urgent story is archived' do
    patch = story('Rotate the key')
    mark(patch)
    patch.update(archived_at: Time.now)

    assert_nil UrgentStory.of(@team)
  end

  it 'counts only a story marked urgent' do
    story('Save a card')
    patch = story('Rotate the key')
    RecordEvent.call(actor_id: @person.actor.id, entity: patch, action: 'person_assigned', after_state: {})

    refute UrgentStory.urgent?(patch)
    assert_nil UrgentStory.of(@team)
  end

  it 'counts the story marked, and no other' do
    card = story('Save a card')
    mark(story('Rotate the key'))

    refute UrgentStory.urgent?(card)
  end
end
