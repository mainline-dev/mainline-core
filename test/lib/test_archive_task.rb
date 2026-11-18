# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/archive_task'

describe ArchiveTask do
  cover 'ArchiveTask*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    @activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    @pay = step('Pay', 1000)
    # Another step with a story of its own, which must not hold this one back.
    @ship = step('Ship', 2000)
    story('Track a parcel', @ship)
    @now = Time.utc(2030, 1, 7, 9)
  end

  def step(name, position)
    Task.create(activity_id: @activity.id, map_id: @map.id, team_id: @team.id, name: name, position: position)
  end

  def story(title, task)
    Story.create(task_id: task.id, map_id: @map.id, team_id: @team.id, title: title, position: 1000, created_by_id: @person.id)
  end

  def archive
    ArchiveTask.call(task: @pay.refresh, actor: @person.actor, now: @now)
  end

  def recorded
    Event.where(entity_id: @pay.id, action: 'archived').all
  end

  it 'archives a step with no stories, and records it by name' do
    result = archive
    by = recorded.map { |event| [event.actor_id, event.after_state] }

    assert_equal [true, nil], [result.success?, result.error]
    assert_equal [@now, nil], [@pay.refresh.archived_at, @ship.refresh.archived_at]
    assert_equal [[@person.actor.id, { 'name' => 'Pay' }]], by
  end

  it 'refuses a step that still has a story, saying why, and archives it once the story is archived' do
    guest = story('Guest checkout', @pay)
    refused = archive
    held = [refused.success?, @pay.refresh.archived_at, recorded.size]
    guest.update(archived_at: Time.now)

    assert_equal [false, nil, 0], held
    refute_empty refused.error.to_s
    assert_predicate archive, :success?
  end
end
