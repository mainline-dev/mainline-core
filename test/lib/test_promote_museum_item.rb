# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/promote_museum_item'
require_relative '../../lib/unpromote_museum_item'
require_relative '../../lib/add_to_story'

describe PromoteMuseumItem do
  cover 'PromoteMuseumItem*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    @task = Task.create(activity_id: activity.id, map_id: @map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @item = museum_item('SHOP-10')
  end

  def museum_item(key, type: 'Story')
    MuseumItem.create(team_id: @team.id, source_key: key, issue_type: type, summary: 'Guest checkout',
      description: 'As a shopper, a long Jira essay')
  end

  def promote(item: @item, title: 'Buy without an account', task_id: @task.id, scenarios: [])
    PromoteMuseumItem.call(item: item, team: @team, actor: @person.actor, person: @person, title: title, task_id: task_id,
      scenarios: scenarios)
  end

  def scenario(given, whn, thn)
    { given: given, when: whn, then: thn }
  end

  it 'turns the item into a planned story under the task, with the new title and no description' do
    result = promote

    assert_predicate result, :success?
    story = result.story

    assert_equal ['Buy without an account', '', 'planned', @task.id, @map.id],
      [story.title, story.description, story.status, story.task_id, story.map_id]
  end

  it 'gives the story the scenarios written while promoting, leaving out empty ones' do
    story = promote(scenarios: [scenario('a basket and no account', 'I continue as a guest', 'I can pay with my email'),
                                scenario('', ' ', ''), scenario('a guest order', 'I sign up', 'the order is mine')]).story

    parts = story.scenarios.map { |s| [s.given_text, s.when_text, s.then_text] }

    assert_equal [['a basket and no account', 'I continue as a guest', 'I can pay with my email'],
                  ['a guest order', 'I sign up', 'the order is mine']], parts
  end

  it 'promotes nothing when a scenario cannot be kept' do
    result = promote(scenarios: [scenario('a basket', 'I continue', 'x' * 101)])

    refute_predicate result, :success?
    assert_equal 0, Story.where(map_id: @map.id).count
    assert_nil @item.refresh.promoted_at
  end

  it 'links the item to its story' do
    story = promote.story
    @item.refresh

    assert_equal story.id, @item.story_id
    assert @item.promoted_at
  end

  it 'promotes an item only once' do
    promote

    second = promote(item: MuseumItem[@item.id])

    refute_predicate second, :success?
    assert_equal 1, second.errors.size
    assert_equal 1, Story.where(map_id: @map.id).count
  end

  it 'refuses an exhibit in storage' do
    @item.update(discarded_at: Time.now)

    result = promote(item: MuseumItem[@item.id])

    refute_predicate result, :success?
    assert_equal 0, Story.where(map_id: @map.id).count
  end

  it 'refuses epics and sub-tasks' do
    epic = museum_item('SHOP-1', type: 'Epic')
    sub_task = museum_item('SHOP-11', type: 'Sub-task')

    refute_predicate promote(item: epic), :success?
    refute_predicate promote(item: sub_task), :success?
    assert_equal 0, Story.where(map_id: @map.id).count
  end

  it 'leaves the item in the museum when the story cannot be made' do
    result = promote(title: nil)

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
    assert_nil @item.refresh.promoted_at
  end

  describe 'promoting together' do
    def together(items, title: 'Buy without an account', scenarios: [])
      PromoteMuseumItem.together(items: items, team: @team, actor: @person.actor, person: @person, title: title,
        task_id: @task.id, scenarios: scenarios)
    end

    it 'makes one story and links every exhibit to it' do
      other = museum_item('SHOP-14')

      result = together([@item, other])

      assert_predicate result, :success?
      assert_equal 1, Story.where(team_id: @team.id).count
      assert_equal [result.story.id] * 2, [@item.refresh.story_id, other.refresh.story_id]
      assert other.promoted_at
    end

    it 'gives the story the scenarios written' do
      result = together([@item, museum_item('SHOP-14')], scenarios: [scenario('a basket', 'I pay', 'it works')])

      assert_equal 1, result.story.scenarios.size
    end

    it 'promotes none of them when one cannot go' do
      other = museum_item('SHOP-14')
      promote(item: other)

      result = together([@item, other])

      refute_predicate result, :success?
      assert_nil @item.refresh.story_id
      assert_equal 1, Story.where(team_id: @team.id).count
    end

    it 'refuses an empty set' do
      refute_predicate together([]), :success?
    end

    it 'sends back what went together, and not what joined the story later' do
      other = museum_item('SHOP-14')
      result = together([@item, other])
      later = museum_item('SHOP-15')
      AddToStory.call(items: [later], story_id: result.story.id, team: @team, actor: @person.actor)

      assert_equal 2, PromoteMuseumItem.undo(team_id: @team.id, actor: @person.actor, batch: result.batch).back
      assert_nil @item.refresh.story_id
      assert_nil other.refresh.story_id
      assert_equal result.story.id, later.refresh.story_id
      assert_nil result.story.refresh.archived_at
    end

    it 'says whether the story went with the batch' do
      untouched = together([@item, museum_item('SHOP-14')])
      kept = together([museum_item('SHOP-15')])
      AddToStory.call(items: [museum_item('SHOP-16')], story_id: kept.story.id, team: @team, actor: @person.actor)

      assert PromoteMuseumItem.undo(team_id: @team.id, actor: @person.actor, batch: untouched.batch).story_archived
      refute PromoteMuseumItem.undo(team_id: @team.id, actor: @person.actor, batch: kept.batch).story_archived
    end

    it 'sends back nothing a second time, for no batch, or for another team' do
      result = together([@item])

      assert_equal 0, PromoteMuseumItem.undo(team_id: Team.create(name: 'Other').id, actor: @person.actor, batch: result.batch).back
      assert_equal 1, PromoteMuseumItem.undo(team_id: @team.id, actor: @person.actor, batch: result.batch).back
      assert_equal 0, PromoteMuseumItem.undo(team_id: @team.id, actor: @person.actor, batch: result.batch).back
      assert_equal 0, PromoteMuseumItem.undo(team_id: @team.id, actor: @person.actor, batch: nil).back
    end

    it 'archives the story once all of them are sent back and nothing else has happened' do
      other = museum_item('SHOP-14')
      story = together([@item, other]).story

      UnpromoteMuseumItem.call(item: @item.refresh, actor: @person.actor)

      assert_nil story.refresh.archived_at

      UnpromoteMuseumItem.call(item: other.refresh, actor: @person.actor)

      assert story.refresh.archived_at
    end
  end

  it 'refuses a task that is not on one of the team maps' do
    other_team = Team.create(name: 'Other')
    SetTeamContext.call(other_team.id)
    other_map = Map.create(team_id: other_team.id, name: 'Theirs', position: 1000)
    other_activity = Activity.create(map_id: other_map.id, team_id: other_team.id, name: 'Elsewhere', position: 1000)
    other_task = Task.create(activity_id: other_activity.id, map_id: other_map.id, team_id: other_team.id, name: 'There', position: 1000)
    SetTeamContext.call(@team.id)

    refute_predicate promote(task_id: other_task.id), :success?
    refute_predicate promote(task_id: nil), :success?
    assert_nil @item.refresh.promoted_at
  end
end
