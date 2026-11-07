# frozen_string_literal: true

require_relative '../model_spec_helper'

describe StoryNote do
  before do
    @team = Team.create(name: 'Test Team')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@acme.co')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(name: 'Map', team_id: @team.id, position: 1000)
    @persona = Persona.create(name: 'User', team_id: @team.id, map_id: @map.id, position: 1000)
    @activity = Activity.create(name: 'Act', map_id: @map.id, team_id: @team.id, position: 1000)
    ActivityPersona.create(activity_id: @activity.id, persona_id: @persona.id, team_id: @team.id)
    @task = Task.create(name: 'Task', activity_id: @activity.id, map_id: @map.id, team_id: @team.id, position: 1000)
    @story = Story.create(
      title: 'Test', task_id: @task.id, map_id: @map.id, team_id: @team.id,
      position: 1000, created_by_id: @person.id
    )
  end

  it 'creates a story note' do
    note = StoryNote.create(
      story_id: @story.id, team_id: @team.id,
      note_type: 'split_candidate'
    )

    refute_nil note.id
    refute_nil note.created_at
    assert_equal 'split_candidate', note.note_type
    assert_nil note.dismissed_at
    assert_nil note.dismissed_by
  end

  it 'enforces valid note_type' do
    assert_raises(Sequel::CheckConstraintViolation) do
      StoryNote.create(
        story_id: @story.id, team_id: @team.id,
        note_type: 'invalid'
      )
    end
  end

  it 'enforces dismiss fields are both set or both null' do
    assert_raises(Sequel::CheckConstraintViolation) do
      StoryNote.create(
        story_id: @story.id, team_id: @team.id,
        note_type: 'split_candidate',
        dismissed_at: Time.now, dismissed_by: nil
      )
    end
  end

  it 'allows dismissal with both fields set' do
    note = StoryNote.create(
      story_id: @story.id, team_id: @team.id,
      note_type: 'split_candidate'
    )

    note.update(dismissed_at: Time.now, dismissed_by: @person.id)

    refute_nil note.dismissed_at
    assert_equal @person.id, note.dismissed_by
  end

  it 'enforces one active note per type per story' do
    StoryNote.create(
      story_id: @story.id, team_id: @team.id,
      note_type: 'split_candidate'
    )

    assert_raises(Sequel::UniqueConstraintViolation) do
      StoryNote.create(
        story_id: @story.id, team_id: @team.id,
        note_type: 'split_candidate'
      )
    end
  end

  it 'allows new note after previous is dismissed' do
    first = StoryNote.create(
      story_id: @story.id, team_id: @team.id,
      note_type: 'split_candidate'
    )
    first.update(dismissed_at: Time.now, dismissed_by: @person.id)

    second = StoryNote.create(
      story_id: @story.id, team_id: @team.id,
      note_type: 'split_candidate'
    )

    refute_equal first.id, second.id
    assert_nil second.dismissed_at
  end

  it 'allows different note types on same story' do
    StoryNote.create(
      story_id: @story.id, team_id: @team.id,
      note_type: 'split_candidate'
    )

    note2 = StoryNote.create(
      story_id: @story.id, team_id: @team.id,
      note_type: 'stale_story'
    )

    refute_nil note2.id
  end
end
