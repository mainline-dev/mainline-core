# frozen_string_literal: true

require_relative '../model_spec_helper'

describe 'Model validations via auto_validations' do
  cover 'Team*'
  it 'Team requires name' do
    team = Team.new

    refute_predicate team, :valid?
    assert team.errors[:name]
  end

  it 'StoryAssignment requires story_id, person_id, and team_id' do
    sa = StoryAssignment.new

    refute_predicate sa, :valid?
    assert sa.errors[:story_id]
    assert sa.errors[:person_id]
    assert sa.errors[:team_id]
  end

  it 'TeamMembership requires team_id and person_id' do
    tm = TeamMembership.new

    refute_predicate tm, :valid?
    assert tm.errors[:team_id]
    assert tm.errors[:person_id]
  end

  it 'Actor requires name' do
    actor = Actor.new

    refute_predicate actor, :valid?
    assert actor.errors[:name]
  end

  it 'Actor rejects invalid kind' do
    actor = Actor.new(kind: 'robot', name: 'Bot')

    refute_predicate actor, :valid?
    assert actor.errors[:kind]
  end

  it 'Team rejects name over 100 characters' do
    team = Team.new(name: 'x' * 101)

    refute_predicate team, :valid?
    assert team.errors[:name]
  end

  it 'Map rejects name over 100 characters' do
    map = Map.new(name: 'x' * 101, team_id: SecureRandom.uuid, position: 1)

    refute_predicate map, :valid?
    assert map.errors[:name]
  end

  it 'Activity rejects name over 100 characters' do
    activity = Activity.new(name: 'x' * 101, map_id: SecureRandom.uuid, team_id: SecureRandom.uuid, position: 1)

    refute_predicate activity, :valid?
    assert activity.errors[:name]
  end

  it 'Task rejects name over 100 characters' do
    task = Task.new(name: 'x' * 101, activity_id: SecureRandom.uuid, map_id: SecureRandom.uuid, team_id: SecureRandom.uuid, position: 1)

    refute_predicate task, :valid?
    assert task.errors[:name]
  end

  it 'Persona rejects name over 100 characters' do
    persona = Persona.new(name: 'x' * 101, map_id: SecureRandom.uuid, team_id: SecureRandom.uuid, position: 1)

    refute_predicate persona, :valid?
    assert persona.errors[:name]
  end

  it 'Story requires title, task_id, map_id, team_id, and created_by_id' do
    story = Story.new

    refute_predicate story, :valid?
    assert story.errors[:title]
    assert story.errors[:task_id]
    assert story.errors[:map_id]
    assert story.errors[:team_id]
    assert story.errors[:created_by_id]
  end

  it 'ReleaseSlice rejects name over 100 characters' do
    slice = ReleaseSlice.new(name: 'x' * 101, map_id: SecureRandom.uuid, team_id: SecureRandom.uuid, position: 1)

    refute_predicate slice, :valid?
    assert slice.errors[:name]
  end
end
