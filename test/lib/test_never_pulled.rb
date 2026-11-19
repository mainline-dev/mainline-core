# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/never_pulled'

describe NeverPulled do
  cover 'NeverPulled*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @now = Time.utc(2026, 11, 15, 12)
    @key = 0
    person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @story = Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: 'Pay by card',
      position: 1000, created_by_id: person.id)
  end

  # A promoted exhibit names the story it became.
  def exhibit(days_ago:, team: @team, type: 'Story', source: 'jira', **state)
    @key += 1
    state[:story_id] = @story.id if state[:promoted_at]
    MuseumItem.create(team_id: team.id, source_key: "SHOP-#{@key}", issue_type: type, summary: "Ticket #{@key}",
      source: source, created_at: @now - (days_ago * 86_400), **state)
  end

  def percent
    NeverPulled.percent(@team.id, now: @now)
  end

  it 'says nothing for a team with nothing in the museum' do
    assert_nil percent
  end

  it 'says nothing while the first import is younger than 90 days' do
    exhibit(days_ago: 89)

    assert_nil percent
  end

  it 'says nothing for a ticket a minute short of 90 days' do
    MuseumItem.create(team_id: @team.id, source_key: 'SHOP-99', issue_type: 'Story', summary: 'Ticket',
      created_at: @now - (90 * 86_400) + 60)

    assert_nil percent
  end

  it 'gives the share of tickets in for 90 days or more that were never promoted' do
    exhibit(days_ago: 90, promoted_at: @now)
    3.times { exhibit(days_ago: 100) }

    assert_equal 75, percent
  end

  it 'counts only the tickets in for 90 days or more' do
    exhibit(days_ago: 120, promoted_at: @now)
    exhibit(days_ago: 120)
    2.times { exhibit(days_ago: 10) }

    assert_equal 50, percent
  end

  it 'counts a ticket sent to storage as never pulled' do
    exhibit(days_ago: 120, promoted_at: @now)
    exhibit(days_ago: 120, discarded_at: @now)

    assert_equal 50, percent
  end

  it 'leaves out epics, sub-tasks and stories proposed from a specification' do
    exhibit(days_ago: 120, promoted_at: @now)
    exhibit(days_ago: 120)
    exhibit(days_ago: 120, type: 'Epic')
    exhibit(days_ago: 120, type: 'Sub-task')
    exhibit(days_ago: 120, type: 'Subtask')
    exhibit(days_ago: 120, source: 'mainline')

    assert_equal 50, percent
  end

  it 'rounds to a whole percentage' do
    exhibit(days_ago: 120, promoted_at: @now)
    2.times { exhibit(days_ago: 120) }

    assert_equal 67, percent
  end

  it "counts only this team's tickets" do
    other = Team.create(name: 'Other')
    exhibit(days_ago: 120, promoted_at: @now)
    exhibit(days_ago: 120)
    SetTeamContext.call(other.id)
    exhibit(days_ago: 120, team: other)
    SetTeamContext.call(@team.id)

    assert_equal 50, percent
  end

  describe 'when the figure is due' do
    def due
      NeverPulled.due(@team.id)
    end

    it 'is never for a team with nothing in the museum' do
      assert_nil due
    end

    it 'is 90 days after the oldest ticket came in' do
      exhibit(days_ago: 10)
      exhibit(days_ago: 30)
      exhibit(days_ago: 20)

      assert_equal @now + (60 * 86_400), due
    end

    it 'is the moment the percentage starts to be given, and not a second sooner' do
      exhibit(days_ago: 30)

      assert_nil NeverPulled.percent(@team.id, now: due - 1)
      assert_equal 100, NeverPulled.percent(@team.id, now: due)
    end

    it 'does not count from an epic, a sub-task or a story proposed from a specification' do
      exhibit(days_ago: 80, type: 'Epic')
      exhibit(days_ago: 75, type: 'Subtask')
      exhibit(days_ago: 70, type: 'Sub-task')
      exhibit(days_ago: 60, source: 'mainline')
      exhibit(days_ago: 5)

      assert_equal @now + (85 * 86_400), due
    end

    it 'is never for a team whose museum holds only stories proposed from a specification' do
      exhibit(days_ago: 60, source: 'mainline')

      assert_nil due
    end

    it "counts only the team asked about, even where every team's tickets are in reach" do
      other = Team.create(name: 'Other')
      exhibit(days_ago: 10)
      SetTeamContext.call(other.id)
      exhibit(days_ago: 60, team: other)

      assert_equal(@now + (80 * 86_400), BypassRLS.call { NeverPulled.due(@team.id) })
    end

    it "does not count another team's tickets" do
      other = Team.create(name: 'Other')
      SetTeamContext.call(other.id)
      exhibit(days_ago: 60, team: other)
      SetTeamContext.call(@team.id)

      assert_nil due
    end
  end
end
