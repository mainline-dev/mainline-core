# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/let_go'

describe LetGo do
  cover 'LetGo*'

  before do
    Timecop.freeze(Time.utc(2026, 6, 15, 12, 0, 0))
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
  end

  after do
    Timecop.return
  end

  # A different summary for each exhibit, so none of them look like duplicates.
  def next_summary
    [
      'Guests can check out without an account', 'Shoppers filter results by price', 'Gift cards at the till',
      'Wishlist sharing between friends', 'Dark mode for the storefront', 'Saved addresses for returning shoppers',
      'Refunds go back to the original card', 'Search suggests products while typing', 'Order history shows tracking links',
      'Stock alerts by email'
    ].fetch(MuseumItem.where(team_id: @team.id).count)
  end

  def add(key, type: 'Story', summary: nil, description: 'Some detail',
          created: Time.utc(2026, 5, 1), comments: [], links: [], **attrs)
    summary ||= next_summary
    MuseumItem.create(team_id: @team.id, source_key: key, issue_type: type, summary: summary, description: description,
      source_created_at: created, comments: Sequel.pg_jsonb(comments), links: Sequel.pg_jsonb(links), **attrs)
  end

  def comment(text, at: '2026-05-01T09:00:00Z')
    { 'at' => at, 'text' => text }
  end

  def promote(item)
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Browse', position: 1000)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Search', position: 1000)
    person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    story = Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: 'Story', position: 1000, created_by_id: person.id)
    item.update(story_id: story.id, promoted_at: Time.now)
  end

  def detect
    LetGo.detect(team_id: @team.id)
  end

  def group(key)
    MuseumItem.where(source_key: key).get(:let_go_group)
  end

  def groups(*keys)
    keys.map { |key| group(key) }
  end

  it 'suggests exhibits nobody has touched for over a year' do
    add('OLD', created: Time.utc(2025, 6, 1))
    add('COMMENTED', created: Time.utc(2025, 1, 1), comments: [comment('Still wanted', at: '2025-12-01T09:00:00Z')])
    add('UPDATED', created: Time.utc(2025, 1, 1), source_updated_at: Time.utc(2026, 1, 1))
    add('NEW', created: Time.utc(2026, 5, 1))
    add('UNDATED', created: nil)

    detect

    assert_equal ['stale', nil, nil, nil, nil], groups('OLD', 'COMMENTED', 'UPDATED', 'NEW', 'UNDATED')
  end

  it 'pairs exhibits of the same type whose summaries are almost the same' do
    add('A-1', summary: 'Order confirmation email sometimes sent twice')
    add('A-2', summary: 'Order confirmation email sometimes sent twice!')
    add('A-3', summary: 'Order confirmation email sometimes sent twice', type: 'Bug')
    add('A-4', summary: 'Wishlist sharing between friends')

    detect

    assert_equal ['dupes', 'dupes', nil, nil], groups('A-1', 'A-2', 'A-3', 'A-4')
    pair_keys = %w[A-1 A-2].map { |key| MuseumItem.where(source_key: key).get(:let_go_pair_key) }

    assert_equal %w[A-2 A-1], pair_keys
  end

  it 'puts an exhibit in one pair at most' do
    %w[A-1 A-2 A-3].each { |key| add(key, summary: 'Saved addresses at checkout for returning shoppers') }

    detect

    assert_equal 2, MuseumItem.where(let_go_group: 'dupes').count
  end

  it 'suggests bugs nobody could reproduce' do
    add('B-1', type: 'Bug', comments: [comment('Seen on staging'), comment("Can't reproduce this any more")])
    add('B-2', type: 'Bug', comments: [comment('Cannot reproduce'), comment('Happened again today')])
    add('B-3', comments: [comment('Works for me')])

    detect

    assert_equal ['repro', nil, nil], groups('B-1', 'B-2', 'B-3')
  end

  describe 'entries proposed from a specification' do
    def propose(key, summary)
      add(key, type: 'Proposal', summary: summary, description: '', created: nil, source: 'mainline',
        origin: 'Research report, section 3')
    end

    it 'are never called too vague: a short title with no more detail is how they arrive' do
      propose('RB-1', 'Racing saves')

      assert_empty LetGo.detect(team_id: @team.id)
      assert_nil MuseumItem.where(source_key: 'RB-1').get(:let_go_group)
    end

    it 'are paired when two say almost the same thing' do
      propose('RB-1', 'Two people change the same item at once')
      propose('RB-2', 'Two people change the same item at once!')

      assert_equal({ 'dupes' => 1 }, LetGo.detect(team_id: @team.id))
    end
  end

  it 'suggests exhibits too vague to act on' do
    add('V-1', summary: 'Fix search', description: '')
    add('V-2', summary: 'Speed up search', description: 'Typing a space at the end returns nothing')
    add('V-3', summary: 'Make the search faster please', description: '')

    detect

    assert_equal ['vague', nil, nil], groups('V-1', 'V-2', 'V-3')
  end

  it 'suggests tasks already covered by a promoted story' do
    promote(add('P-1'))
    add('T-1', type: 'Task', parent_key: 'P-1')
    add('T-2', type: 'Sub-task', links: [{ 'type' => 'Blocks', 'direction' => 'outward', 'key' => 'P-1' }])
    add('T-3', parent_key: 'P-1')
    add('T-4', type: 'Task', links: [{ 'type' => 'Relates', 'direction' => 'outward', 'key' => 'X-9' }])

    detect

    assert_equal ['covered', 'covered', nil, nil], groups('T-1', 'T-2', 'T-3', 'T-4')
  end

  it 'puts an exhibit in the first group that fits' do
    add('S-1', summary: 'Fix', description: '', created: Time.utc(2024, 1, 1))

    detect

    assert_equal 'stale', group('S-1')
  end

  it 'leaves out exhibits promoted, stored, kept or in progress' do
    old = Time.utc(2024, 1, 1)
    promote(add('P-1', created: old))
    add('S-1', created: old, discarded_at: Time.now)
    add('K-1', created: old, kept_at: Time.now)
    add('I-1', created: old, in_progress: true)

    detect

    assert_equal [nil, nil, nil, nil], groups('P-1', 'S-1', 'K-1', 'I-1')
  end

  it 'clears a suggestion that no longer fits' do
    item = add('OLD', created: Time.utc(2025, 1, 1))
    detect
    item.update(kept_at: Time.now)

    detect

    assert_nil group('OLD')
  end

  it 'counts the suggestions by group, a pair as one' do
    add('OLD', created: Time.utc(2025, 1, 1))
    add('A-1', summary: 'Order confirmation email sometimes sent twice')
    add('A-2', summary: 'Order confirmation email sometimes sent twice!')
    add('V-1', summary: 'Fix search', description: '')

    assert_equal({ 'stale' => 1, 'dupes' => 1, 'vague' => 1 }, detect)
  end

  it 'keeps each team to its own suggestions' do
    add('A-1', summary: 'Order confirmation email sometimes sent twice')
    other = Team.create(name: 'Other')
    SetTeamContext.call(other.id)
    MuseumItem.create(team_id: other.id, source_key: 'A-2', issue_type: 'Story', summary: 'Order confirmation email sometimes sent twice')
    SetTeamContext.call(@team.id)

    detect

    assert_nil group('A-1')
  end
end
