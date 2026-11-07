# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/discard_museum_item'

describe DiscardMuseumItem do
  cover 'DiscardMuseumItem*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @item = MuseumItem.create(team_id: @team.id, source_key: 'SHOP-31', issue_type: 'Story', summary: 'Points balance')
  end

  def event(action)
    Event.where(entity_id: @item.id, action: action).first
  end

  it 'discards an item and records who did it' do
    result = DiscardMuseumItem.call(item: @item, actor: @person.actor)

    assert_predicate result, :success?
    assert @item.refresh.discarded_at
    assert_equal [@person.actor_id, 'museum_item', 'SHOP-31'],
      [event('discarded').actor_id, event('discarded').entity_type, event('discarded').after_state['source_key']]
  end

  it 'sends several items to storage together, skipping any already there' do
    other = MuseumItem.create(team_id: @team.id, source_key: 'SHOP-32', issue_type: 'Story', summary: 'Gift cards')
    stored = MuseumItem.create(team_id: @team.id, source_key: 'SHOP-33', issue_type: 'Story', summary: 'Wishlist',
      discarded_at: Time.now)

    stored_now = DiscardMuseumItem.many(items: [@item, other, stored], actor: @person.actor).stored

    assert_equal 2, stored_now
    assert(@item.refresh.discarded_at && other.refresh.discarded_at)
    assert_equal 2, Event.where(action: 'discarded').count
  end

  describe 'bringing a batch back' do
    def add(key)
      MuseumItem.create(team_id: @team.id, source_key: key, issue_type: 'Story', summary: key)
    end

    def bring_back(batch, team: @team)
      DiscardMuseumItem.restore_batch(team_id: team.id, actor: @person.actor, batch: batch)
    end

    it 'brings back what went together, and nothing else in storage' do
      other = add('SHOP-32')
      alone = add('SHOP-33')
      DiscardMuseumItem.call(item: alone, actor: @person.actor)
      batch = DiscardMuseumItem.many(items: [@item, other], actor: @person.actor).batch

      assert_equal 2, bring_back(batch)
      assert_nil @item.refresh.discarded_at
      assert_nil other.refresh.discarded_at
      assert alone.refresh.discarded_at
    end

    it 'leaves out what has come back already, and does nothing a second time' do
      batch = DiscardMuseumItem.many(items: [@item, add('SHOP-32')], actor: @person.actor).batch
      DiscardMuseumItem.restore(item: @item, actor: @person.actor)

      assert_equal 1, bring_back(batch)
      assert_equal 0, bring_back(batch)
    end

    it "leaves another team's batch alone, and nothing for no batch" do
      batch = DiscardMuseumItem.many(items: [@item], actor: @person.actor).batch

      assert_equal 0, bring_back(batch, team: Team.create(name: 'Other'))
      assert_equal 0, bring_back(nil)
      assert @item.refresh.discarded_at
    end
  end

  it 'discards an item once' do
    DiscardMuseumItem.call(item: @item, actor: @person.actor)

    refute_predicate DiscardMuseumItem.call(item: @item, actor: @person.actor), :success?
    assert_equal 1, Event.where(entity_id: @item.id, action: 'discarded').count
  end

  it 'refuses a promoted item' do
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Browse', position: 1000)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Search', position: 1000)
    story = Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: 'Story', position: 1000, created_by_id: @person.id)
    @item.update(story_id: story.id, promoted_at: Time.now)

    result = DiscardMuseumItem.call(item: @item, actor: @person.actor)

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
    assert_nil @item.refresh.discarded_at
  end

  it 'restores a discarded item and records who did it' do
    DiscardMuseumItem.call(item: @item, actor: @person.actor)

    result = DiscardMuseumItem.restore(item: @item, actor: @person.actor)

    assert_predicate result, :success?
    assert_nil @item.refresh.discarded_at
    assert_equal @person.actor_id, event('restored').actor_id
  end

  it 'restores only a discarded item' do
    result = DiscardMuseumItem.restore(item: @item, actor: @person.actor)

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
    assert_nil event('restored')
  end
end
