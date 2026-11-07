# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/museum_list'

describe MuseumList do
  cover 'MuseumList*'

  before do
    Timecop.freeze(Time.utc(2026, 6, 15, 12, 0, 0))
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
  end

  after do
    Timecop.return
  end

  def add(key, type: 'Story', created: Time.utc(2026, 6, 1), summary: key, **attrs)
    labels = Sequel.pg_jsonb(attrs.delete(:labels) || [])
    MuseumItem.create(team_id: @team.id, source_key: key, issue_type: type, summary: summary,
      source_created_at: created, labels: labels, **attrs)
  end

  def list(**filters)
    MuseumList.call(team_id: @team.id, **filters)
  end

  def keys(page)
    page.items.map(&:source_key)
  end

  it 'lists in-progress items first, then the newest' do
    add('SHOP-1', created: Time.utc(2026, 3, 1))
    add('SHOP-2', created: Time.utc(2026, 1, 1), in_progress: true)
    add('SHOP-3', created: Time.utc(2026, 5, 1))
    add('SHOP-4', created: nil)

    assert_equal %w[SHOP-2 SHOP-3 SHOP-1 SHOP-4], keys(list)
  end

  it 'keeps epics out of the list and offers them as filters' do
    add('SHOP-1', type: 'Epic')
    add('SHOP-2', parent_key: 'SHOP-1')
    add('SHOP-3')

    page = list

    assert_equal %w[SHOP-2 SHOP-3], keys(page).sort
    assert_equal ['SHOP-1'], page.epics.map(&:source_key)
    assert_equal ['SHOP-2'], keys(list(epic: 'SHOP-1'))
  end

  it 'shows sub-tasks under their parent instead of in the list' do
    add('SHOP-1')
    add('SHOP-2', type: 'Sub-task', parent_key: 'SHOP-1')
    add('SHOP-3', type: 'Subtask', parent_key: 'SHOP-1')
    add('SHOP-4', type: 'Sub-task', parent_key: 'SHOP-9')

    page = list

    assert_equal %w[SHOP-1 SHOP-4], keys(page).sort
    assert_equal %w[SHOP-2 SHOP-3], page.sub_tasks.fetch('SHOP-1').map(&:source_key).sort
    refute page.sub_tasks.key?('SHOP-4')
  end

  it 'filters by issue type, offering the types in the list' do
    add('SHOP-1', type: 'Story')
    add('SHOP-2', type: 'Bug')
    add('SHOP-3', type: 'Epic')
    add('SHOP-4', type: 'Sub-task', parent_key: 'SHOP-1')

    assert_equal %w[Bug Story], list.types
    assert_equal ['SHOP-2'], keys(list(type: 'Bug'))
  end

  it 'filters by label, offering every label' do
    add('SHOP-1', labels: %w[checkout mobile])
    add('SHOP-2', labels: ['mobile'])
    add('SHOP-3')

    assert_equal %w[checkout mobile], list.labels
    assert_equal %w[SHOP-1 SHOP-2], keys(list(label: 'mobile')).sort
    assert_equal ['SHOP-1'], keys(list(label: 'checkout'))
  end

  it 'filters by age' do
    add('NEW', created: Time.utc(2026, 3, 16))
    add('EDGE', created: Time.utc(2026, 3, 15, 12))
    add('MONTHS', created: Time.utc(2025, 6, 16))
    add('YEAR', created: Time.utc(2025, 6, 15, 12))
    add('OLD', created: Time.utc(2020, 1, 1))
    add('UNKNOWN', created: nil)

    assert_equal ['NEW'], keys(list(age: 'under-3-months'))
    assert_equal %w[EDGE MONTHS], keys(list(age: '3-to-12-months'))
    assert_equal %w[YEAR OLD], keys(list(age: 'over-a-year'))
    assert_equal 6, list(age: 'whenever').total
  end

  it 'searches the key, summary and description, ignoring case' do
    add('SHOP-1', summary: 'Guest checkout')
    add('SHOP-2', description: 'As a shopper I want to CHECKOUT quickly')
    add('PAY-3', summary: 'Refunds')
    add('SHOP-4', summary: 'Wishlist')

    assert_equal %w[SHOP-1 SHOP-2], keys(list(search: 'checkout')).sort
    assert_equal ['PAY-3'], keys(list(search: 'pay-'))
  end

  it 'finds only items with every word searched for' do
    add('SHOP-1', summary: 'Guest checkout', description: 'on mobile')
    add('SHOP-2', summary: 'Guest wishlist', description: 'on mobile')
    add('SHOP-3', summary: 'Checkout totals')

    assert_equal ['SHOP-1'], keys(list(search: ' checkout   MOBILE '))
  end

  it 'searches for percent signs and underscores as they are typed' do
    add('SHOP-1', summary: '100% off')
    add('SHOP-2', summary: '1000 items')
    add('SHOP-3', summary: 'snake_case')
    add('SHOP-4', summary: 'snakeXcase')

    assert_equal ['SHOP-1'], keys(list(search: '100%'))
    assert_equal ['SHOP-3'], keys(list(search: 'snake_case'))
  end

  it 'lists everything for a blank search' do
    add('SHOP-1')
    add('SHOP-2')

    assert_equal 2, list(search: '   ').total
  end

  it 'searches for the first ten words only' do
    add('SHOP-1', summary: 'a b c d e f g h i j')

    assert_equal ['SHOP-1'], keys(list(search: 'a b c d e f g h i j unmatched'))
  end

  it 'combines filters' do
    add('SHOP-1', type: 'Bug', labels: ['mobile'])
    add('SHOP-2', type: 'Bug')
    add('SHOP-3', labels: ['mobile'])

    assert_equal ['SHOP-1'], keys(list(type: 'Bug', label: 'mobile'))
    assert_equal ['SHOP-2'], keys(list(type: 'Bug', search: 'shop-2'))
  end

  it 'pages through 100 at a time' do
    105.times { |n| add(format('SHOP-%03d', n), created: Time.utc(2026, 1, 1)) }

    first = list
    last = list(page: 2)

    assert_equal [100, 105, 1, 2], [first.items.size, first.total, first.page, first.pages]
    assert_equal %w[SHOP-100 SHOP-101 SHOP-102 SHOP-103 SHOP-104], keys(last)
    assert_equal 2, list(page: 9).page
    assert_equal 1, list(page: 0).page
  end

  def promote(item)
    @story_task ||= begin
      map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
      activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Browse', position: 1000)
      Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Search', position: 1000)
    end
    @person ||= Person.create(name: 'Alice', email: 'alice@test.mainline')
    story = Story.create(task_id: @story_task.id, map_id: @story_task.map_id, team_id: @team.id, title: 'Story',
      position: 1000 * (Story.where(task_id: @story_task.id).count + 1), created_by_id: @person.id)
    item.update(story_id: story.id, promoted_at: Time.now)
  end

  it 'lists the exhibits on display, or those promoted, in storage, or everything' do
    add('SHOP-1')
    promote(add('SHOP-2'))
    add('SHOP-3', discarded_at: Time.now)

    assert_equal ['SHOP-1'], keys(list)
    assert_equal ['SHOP-2'], keys(list(status: 'promoted'))
    assert_equal ['SHOP-3'], keys(list(status: 'in-storage'))
    assert_equal %w[SHOP-1 SHOP-2 SHOP-3], keys(list(status: 'everything')).sort
    assert_equal ['SHOP-1'], keys(list(status: 'whatever'))
  end

  it 'counts the matches among promoted and stored exhibits' do
    add('SHOP-1', summary: 'Refund a card')
    promote(add('SHOP-2', summary: 'Refund in full'))
    promote(add('SHOP-3', summary: 'Partial refund'))
    add('SHOP-4', summary: 'Refund twice', discarded_at: Time.now)
    add('SHOP-5', summary: 'Wishlist', discarded_at: Time.now)

    page = list(search: 'refund', type: 'Story')

    assert_equal [1, 2, 1], [page.total, page.promoted_matches, page.stored_matches]
  end

  it 'lists the kept exhibits on display under Kept' do
    add('SHOP-1', kept_at: Time.now, let_go_group: 'stale')
    add('SHOP-2')
    add('SHOP-3', kept_at: Time.now, let_go_group: 'stale', discarded_at: Time.now)

    assert_equal ['SHOP-1'], keys(list(status: 'kept'))
    assert_equal %w[SHOP-1 SHOP-2], keys(list).sort
  end

  it 'counts the whole museum by status, whatever the filters' do
    add('SHOP-1')
    add('SHOP-2', type: 'Bug')
    add('SHOP-3', type: 'Epic')
    add('SHOP-4', type: 'Sub-task', parent_key: 'SHOP-1')
    promote(add('SHOP-5'))
    add('SHOP-6', discarded_at: Time.now)
    add('SHOP-7', discarded_at: Time.now)

    catalogue = list(type: 'Bug').catalogue

    assert_equal [2, 1, 2, 5], [catalogue.on_display, catalogue.promoted, catalogue.stored, catalogue.total]
  end

  it 'lists the reasons exhibits are in storage, once each, in order' do
    add('SHOP-1', discarded_at: Time.now, storage_note: 'vague')
    add('SHOP-2', discarded_at: Time.now, storage_note: 'vague')
    add('SHOP-3', discarded_at: Time.now, storage_note: 'repro')
    add('SHOP-4', discarded_at: Time.now)

    assert_equal %w[repro vague], list(status: 'in-storage').whys
  end

  it 'narrows storage to one reason' do
    add('SHOP-1', discarded_at: Time.now, storage_note: 'vague')
    add('SHOP-2', discarded_at: Time.now, storage_note: 'repro')
    add('SHOP-3', discarded_at: Time.now)

    assert_equal ['SHOP-1'], keys(list(status: 'in-storage', why: 'vague'))
  end

  it 'has one empty page when nothing matches' do
    page = list

    assert_equal [0, 1, 1], [page.total, page.page, page.pages]
    assert_empty page.items
  end
end
