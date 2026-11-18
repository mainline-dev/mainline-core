# frozen_string_literal: true

require 'securerandom'
require_relative '../model_spec_helper'
require_relative '../../lib/report_deploys'

describe ReportDeploys do
  cover 'ReportDeploys*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    @task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @checkout = story('Guest checkout', 1000, 'active')
    @card = story('Pay by card', 2000, 'active')
    @refund = story('Refund an order', 3000, 'planned')
    @now = Time.utc(2030, 1, 7, 9)
  end

  def story(title, position, status)
    Story.create(task_id: @task.id, map_id: @task.map_id, team_id: @team.id, title: title, position: position,
      created_by_id: @person.id).tap { |story| story.update(status: status) }
  end

  # An active story of another team's, made where that team's rows can be written.
  def other_teams_story
    team = Team.create(name: 'Other')
    map = Map.create(team_id: team.id, name: 'Theirs', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: team.id, name: 'Theirs', position: 1000)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: team.id, name: 'Theirs', position: 1000)
    story = Story.create(task_id: task.id, map_id: map.id, team_id: team.id, title: 'Theirs', position: 1000,
      created_by_id: @person.id)
    story.update(status: 'active')
    story
  end

  def report(*story_ids)
    ReportDeploys.call(team: @team, actor: @person.actor, story_ids: story_ids, now: @now)
  end

  def deploys
    [@checkout, @card, @refund].map { |story| story.refresh.deploy_count }
  end

  it 'marks each active story named as deployed, at the time and by the actor given, and says how many' do
    result = report(@checkout.id, @card.id)
    by = Event.where(action: 'deployed').select_map(:actor_id).uniq
    at = [@checkout, @card].map { |story| story.refresh.last_deployed_at }

    assert_equal [true, 2], [result.success?, result.deployed]
    assert_equal [1, 1, 0], deploys
    assert_equal [@now, @now], at
    assert_equal [@person.actor.id], by
  end

  it 'deploys a story once, however many times and ways one report names it' do
    result = report(@checkout.id, @checkout.id, @checkout.id[0, 8].upcase)

    assert_equal 1, result.deployed
    assert_equal [1, 0, 0], deploys
  end

  it 'passes over a story that is not active and an ID that names nothing' do
    result = report(@refund.id, 'zzzz', SecureRandom.uuid, nil, @card.id)

    assert_equal 1, result.deployed
    assert_equal [0, 1, 0], deploys
  end

  it "leaves another team's story alone, even where every team's rows can be seen" do
    theirs = BypassRLS.call { other_teams_story }
    result = BypassRLS.call { report(theirs.id, @checkout.id) }
    left = BypassRLS.call { theirs.refresh.deploy_count }

    assert_equal 1, result.deployed
    assert_equal 0, left
  end

  it 'refuses a report naming more than 100 stories, deploying none, and takes one naming 100' do
    padding = Array.new(99) { SecureRandom.uuid }
    refused = report(@checkout.id, @card.id, *padding)
    after_refusal = deploys
    taken = report(@checkout.id, *padding)

    assert_equal [false, ReportDeploys::TOO_MANY, nil], [refused.success?, refused.error, refused.deployed]
    assert_equal [0, 0, 0], after_refusal
    assert_equal [true, 1], [taken.success?, taken.deployed]
  end
end
