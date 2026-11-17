# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/deploy_story'

describe DeployStory do
  cover 'DeployStory*'

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
    @other = Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: 'Pay by card', position: 2000,
      created_by_id: @person.id)
    @story.update(status: 'active')
    @first = Time.utc(2030, 1, 7, 9)
  end

  def deploy(at)
    DeployStory.call(story: @story.refresh, actor: @person.actor, now: at)
  end

  def deploy_counts_recorded
    Event.where(entity_id: @story.id, action: 'deployed').order(:event_no).all.map { |event| event.after_state['deploy_count'] }
  end

  it 'counts each deploy of the story, keeps when it was first and last deployed, and records each with its count' do
    deploy(@first)
    result = deploy(@first + 3600)

    assert_predicate result, :success?
    assert_equal [2, @first, @first + 3600], @story.refresh.values.values_at(:deploy_count, :first_deployed_at, :last_deployed_at)
    assert_equal [1, 2], deploy_counts_recorded
    assert_equal 0, @other.refresh.deploy_count
  end

  it 'refuses a story that is not active, and changes and records nothing' do
    results = %w[planned released].map { |status|
      @story.update(status: status, released_at: (@first if status == 'released'))
      deploy(@first)
    }

    assert_equal [false], results.map(&:success?).uniq
    assert(results.all?(&:error))
    assert_equal [0, nil], @story.refresh.values.values_at(:deploy_count, :first_deployed_at)
    assert_empty deploy_counts_recorded
  end
end
