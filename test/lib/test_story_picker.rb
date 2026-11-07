# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/story_picker'

describe StoryPicker do
  cover 'StoryPicker*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @shop = task('Shop', 'Search', 'Narrow the results', position: 1000)
    @ops = task('Ops', 'Performance', 'Fast pages', position: 2000)
  end

  def task(map_name, activity_name, task_name, position:)
    map = Map.create(team_id: @team.id, name: map_name, position: position)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: activity_name, position: 1000)
    Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: task_name, position: 1000)
  end

  def story(title, task: @shop, position: (Story.where(team_id: @team.id).count + 1) * 1000, **attrs)
    Story.create(task_id: task.id, map_id: task.map_id, team_id: @team.id, title: title, position: position, created_by_id: @person.id,
**attrs)
  end

  def pick(query = '')
    StoryPicker.call(team_id: @team.id, query: query)
  end

  def titles(groups)
    groups.flat_map { |_map, hits| hits.map(&:title) }
  end

  it 'groups stories by map, in map order' do
    story('Search results load quickly', task: @ops)
    story('Shoppers filter by price')

    assert_equal %w[Shop Ops], pick.map(&:first)
  end

  it 'finds stories whose title has every word, across all the maps' do
    story('Shoppers filter by price')
    story('Search results load quickly', task: @ops)
    story('Filter results quickly', task: @ops)

    assert_equal ['Search results load quickly', 'Filter results quickly'].sort, titles(pick('results QUICKLY')).sort
  end

  it 'matches percent and underscore as typed' do
    story('Show 100% of orders')
    story('Show all orders')

    assert_equal ['Show 100% of orders'], titles(pick('100%'))
  end

  it 'says where a story is, what state it is in and how many relics it has' do
    found = story('Shoppers filter by price', status: 'active')
    2.times do |n|
      MuseumItem.create(team_id: @team.id, source_key: "SHOP-#{n}", issue_type: 'Story', summary: 'Old', story_id: found.id,
        promoted_at: Time.now)
    end
    story('Gift cards', position: 2000)

    hits = pick.first.last

    assert_equal 'Search / Narrow the results · in progress · 2 relics', hits.first.meta
    assert_equal 'Search / Narrow the results · planned', hits.last.meta
  end

  it 'says one relic in the singular' do
    found = story('Shoppers filter by price')
    MuseumItem.create(team_id: @team.id, source_key: 'SHOP-1', issue_type: 'Story', summary: 'Old', story_id: found.id,
      promoted_at: Time.now)

    assert_equal 'Search / Narrow the results · planned · 1 relic', pick.first.last.first.meta
  end

  it 'leaves out what is archived, and maps with nothing to show' do
    story('Old idea', archived_at: Time.now)
    Map.where(id: @ops.map_id).update(archived_at: Time.now)
    story('Gone with its map', task: @ops)

    assert_empty pick
  end

  describe 'suggesting a story from a Jira link' do
    def promoted(key, story)
      MuseumItem.create(team_id: @team.id, source_key: key, issue_type: 'Story', summary: 'Old', story_id: story.id, promoted_at: Time.now)
    end

    def linked(key, to:)
      MuseumItem.create(team_id: @team.id, source_key: key, issue_type: 'Task', summary: 'New',
        links: Sequel.pg_jsonb([{ 'type' => 'Relates', 'key' => to }]))
    end

    it 'suggests the story an exhibit is linked to through a promoted exhibit' do
      found = story('Shoppers filter by price')
      promoted('SHOP-22', found)

      suggestion = StoryPicker.suggestion(items: [linked('SHOP-27', to: 'SHOP-22')])

      assert_equal [found.id, 'SHOP-22', 'Shoppers filter by price'], [suggestion.story_id, suggestion.key, suggestion.title]
    end

    it 'looks through every exhibit in the set' do
      found = story('Shoppers filter by price')
      promoted('SHOP-22', found)
      plain = MuseumItem.create(team_id: @team.id, source_key: 'SHOP-1', issue_type: 'Task', summary: 'Plain')

      assert_equal found.id, StoryPicker.suggestion(items: [plain, linked('SHOP-27', to: 'SHOP-22')]).story_id
    end

    it 'suggests nothing without a link to a promoted exhibit, or for an archived story' do
      gone = story('Old idea', archived_at: Time.now)
      promoted('SHOP-22', gone)

      assert_nil StoryPicker.suggestion(items: [linked('SHOP-27', to: 'SHOP-22')])
      assert_nil StoryPicker.suggestion(items: [linked('SHOP-28', to: 'SHOP-99')])
    end

    it 'puts the suggested story first, whichever map it is on' do
      story('Shoppers filter by price')
      fast = story('Search results load quickly', task: @ops)

      found = StoryPicker.call(team_id: @team.id, query: '', suggested: fast.id)

      assert_equal 'Ops', found.first.first
      assert_equal 'Search results load quickly', titles(found).first
    end

    it 'keeps the suggested story among the results of an empty search' do
      (StoryPicker::LIMIT + 1).times { |n| story("Story number #{n}", position: n + 1) }
      last = Story.where(team_id: @team.id).order(Sequel.desc(:position)).first

      found = StoryPicker.call(team_id: @team.id, query: '', suggested: last.id)

      assert_includes(found.flat_map { |_map, hits| hits.map(&:id) }, last.id)
    end
  end

  it 'shows no more than the limit' do
    (StoryPicker::LIMIT + 1).times { |n| story("Story number #{n}", position: n) }

    assert_equal StoryPicker::LIMIT, titles(pick).size
  end
end
