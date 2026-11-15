# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/first_run'

describe FirstRun do
  cover 'FirstRun*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    # Far from the real date, so the steps go by the time they are given.
    @now = Time.utc(2030, 6, 1, 12)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    @task = Task.create(activity_id: activity.id, map_id: @map.id, team_id: @team.id, name: 'Pay', position: 1000)
  end

  def story(status: 'planned', **attrs)
    Story.create(task_id: @task.id, map_id: @map.id, team_id: @team.id, title: 'Pay by card',
      position: (Story.max(:position) || 0) + 1000, created_by_id: @person.id, status: status, **attrs)
  end

  def exhibit(days_ago: 1, source: 'jira', **state)
    MuseumItem.create(team_id: @team.id, source_key: "SHOP-#{MuseumItem.count + 1}", issue_type: 'Story',
      summary: 'Pay by card', source: source, created_at: @now - (days_ago * 86_400), **state)
  end

  def done
    FirstRun.for(@team, now: @now).select { |_, ticked| ticked }.keys
  end

  it 'has every step undone for a new team, in order' do
    assert_equal %i[import promote slice start agent figure], FirstRun.for(@team, now: @now).keys
    assert_empty done
  end

  it 'ticks bringing in the backlog once a ticket is in the museum' do
    exhibit

    assert_equal [:import], done
  end

  it 'leaves bringing in the backlog undone for stories proposed from a specification' do
    exhibit(source: 'mainline')

    assert_empty done
  end

  it 'ticks pulling what is real once a ticket is promoted' do
    exhibit(promoted_at: @now, story_id: story.id)

    assert_equal %i[import promote], done
  end

  it 'ticks shaping the map once there is a release slice' do
    ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'First release', position: 1000)

    assert_equal [:slice], done
  end

  it 'ticks one story each once a story has started' do
    story(status: 'active')

    assert_equal [:start], done
  end

  it 'leaves one story each undone while every story is planned' do
    story

    assert_empty done
  end

  it 'ticks the coding agent once the team has an MCP token' do
    @team.update(mcp_token: 'digest')

    assert_equal [:agent], done
  end

  it 'ticks checking back once the museum can say how much was never pulled' do
    exhibit(days_ago: 90)

    assert_equal %i[import figure], done
  end

  it 'has no first steps once a story has been released' do
    story(status: 'released', released_at: @now)

    assert_nil FirstRun.for(@team, now: @now)
  end
end
