# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/archive_story'

describe ArchiveStory do
  cover 'ArchiveStory*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @story = Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: 'Guest checkout', position: 1000,
      created_by_id: @person.id)
  end

  it 'archives a story and records it' do
    assert_predicate ArchiveStory.call(story: @story, actor: @person.actor), :success?
    assert @story.refresh.archived_at
    assert_equal 1, Event.where(entity_id: @story.id, action: 'archived').count
  end

  it 'refuses a released story or one someone is working on' do
    assigned = @story
    StoryAssignment.create(story_id: assigned.id, person_id: @person.id, team_id: @team.id)

    refute_predicate ArchiveStory.call(story: assigned, actor: @person.actor), :success?
    StoryAssignment.where(story_id: assigned.id).delete
    assigned.update(status: 'released', released_at: Time.now)

    refute_predicate ArchiveStory.call(story: assigned, actor: @person.actor), :success?
    assert_nil assigned.refresh.archived_at
  end
end
