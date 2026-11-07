# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/let_go_review'
require_relative '../../lib/unpromote_museum_item'

describe LetGoReview do
  cover 'LetGoReview*'

  before do
    Timecop.freeze(Time.utc(2026, 6, 15, 12, 0, 0))
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
  end

  after do
    Timecop.return
  end

  def add(key, type: 'Story', created: Time.utc(2026, 5, 1), **attrs)
    fields = { summary: "Shoppers can do the thing numbered #{key}", description: 'Some detail' }
    fields = { comments: [], links: [], labels: [], **fields, **attrs }
    %i[comments links labels].each { |field| fields[field] = Sequel.pg_jsonb(fields[field]) }
    MuseumItem.create(team_id: @team.id, source_key: key, issue_type: type, source_created_at: created, **fields)
  end

  def stale(key, **attrs)
    add(key, created: Time.utc(2024, 8, 1), **attrs)
  end

  def promoted(key, title:)
    item = add(key)
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Browse', position: 1000)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Search', position: 1000)
    story = Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: title, position: 1000, created_by_id: @person.id)
    item.update(story_id: story.id, promoted_at: Time.now)
  end

  def groups
    LetGo.detect(team_id: @team.id)
    LetGoReview.groups(team_id: @team.id)
  end

  def keys(suggestions)
    suggestions.map { |suggestion| suggestion.item.source_key }
  end

  def evidence
    groups.flat_map(&:suggestions).map(&:evidence)
  end

  def let_go(items, rest: [], seen: [], keep: [])
    LetGoReview.let_go(team_id: @team.id, actor: @person.actor, ids: items.map(&:id), seen: seen.map(&:id), rest: rest, keep: keep).gone
  end

  it 'gives each group its suggestions in key order, leaving out empty groups' do
    stale('SHOP-10')
    stale('SHOP-9')
    add('SHOP-1', summary: 'Fix login', description: '')
    add('SHOP-2')

    seen = groups.map { |group| [group.id, *keys(group.suggestions)] }

    assert_equal [%w[stale SHOP-9 SHOP-10], %w[vague SHOP-1]], seen
  end

  it 'gives a group its title for the storage note' do
    stale('SHOP-1')

    assert_equal LetGoReview.title('stale'), groups.first.title
  end

  it 'shows five suggestions in a group and holds the rest back' do
    (1..7).each { |number| stale("SHOP-#{number}") }

    group = groups.first

    assert_equal %w[SHOP-1 SHOP-2 SHOP-3 SHOP-4 SHOP-5], keys(group.shown)
    assert_equal %w[SHOP-6 SHOP-7], keys(group.rest)
  end

  it 'leaves out what has been kept or promoted since the curator looked' do
    stale('SHOP-1')
    kept = stale('SHOP-2')
    LetGo.detect(team_id: @team.id)
    kept.update(kept_at: Time.now)

    assert_equal ['SHOP-1'], keys(LetGoReview.groups(team_id: @team.id).flat_map(&:suggestions))
  end

  it 'says when a stale exhibit was made and last commented on' do
    stale('SHOP-1', comments: [{ 'at' => '2024-09-03T09:00:00Z', 'text' => 'Later' }])

    assert_equal ['Created Aug 2024 · last comment Sep 2024'], evidence
  end

  it 'says when a stale exhibit was never commented on' do
    stale('SHOP-1')

    assert_equal ['Created Aug 2024 · never commented'], evidence
  end

  it 'quotes the comment that says a bug could not be reproduced' do
    add('SHOP-1', type: 'Bug', comments: [{ 'at' => '2026-02-03T09:00:00Z', 'text' => "Can't reproduce locally." }])

    assert_equal ['"Can\'t reproduce locally." Feb 2026'], evidence
  end

  it 'cuts a long comment short' do
    add('SHOP-1', type: 'Bug', comments: [{ 'at' => '2026-02-03T09:00:00Z', 'text' => "Can't reproduce #{'x' * 100}" }])

    assert_operator evidence.first.length, :<, 80
  end

  it 'counts what a vague exhibit has to go on' do
    add('SHOP-1', summary: 'Fix login', description: '')
    add('SHOP-2', summary: 'Improve search', description: '', labels: ['search'])
    add('SHOP-3', summary: 'Performance', description: '', labels: %w[slow web])

    assert_equal ['No description · no labels', 'No description · 1 label', 'No description · 2 labels'], evidence
  end

  it 'names the story that covers a task, through its parent or a link' do
    promoted('SHOP-10', title: 'Guests can check out')
    add('SHOP-11', type: 'Task', parent_key: 'SHOP-10', summary: 'Store the guest email on the order')
    add('SHOP-12', type: 'Task', summary: 'Banner copy for guests', links: [{ 'type' => 'Relates', 'key' => 'SHOP-10' }])
    add('SHOP-13', type: 'Task', summary: 'Add a token column to orders', links: [{ 'type' => 'Blocks', 'key' => 'SHOP-10' }])

    assert_equal ['Parent SHOP-10 → "Guests can check out"', 'Relates to SHOP-10 → "Guests can check out"',
                  'Blocks SHOP-10 → "Guests can check out"'], evidence
  end

  it 'drops a covered task from the review once the story that covered it is gone' do
    parent = promoted('SHOP-10', title: 'Guests can check out')
    add('SHOP-11', type: 'Task', parent_key: 'SHOP-10', summary: 'Store the guest email on the order')
    LetGo.detect(team_id: @team.id)

    UnpromoteMuseumItem.call(item: parent.refresh, actor: @person.actor)

    assert_empty LetGoReview.groups(team_id: @team.id)
  end

  it 'drops a bug from the review once its comments have gone' do
    bug = add('SHOP-1', type: 'Bug', comments: [{ 'at' => '2026-02-03T09:00:00Z', 'text' => "Can't reproduce locally." }])
    LetGo.detect(team_id: @team.id)

    bug.update(comments: Sequel.pg_jsonb([]))

    assert_empty LetGoReview.groups(team_id: @team.id)
  end

  it 'sends what was ticked to storage, noting the group, and says how many went' do
    gone = stale('SHOP-1')
    left = stale('SHOP-2')
    LetGo.detect(team_id: @team.id)

    assert_equal 1, let_go([gone])
    assert_equal 'stale', gone.refresh.storage_note
    assert gone.discarded_at
    assert_nil left.refresh.discarded_at
  end

  it 'lets the rest of a group go only when asked' do
    items = (1..6).map { |number| stale("SHOP-#{number}") }
    LetGo.detect(team_id: @team.id)

    assert_equal 0, let_go([], seen: items.first(5))
    assert_equal 1, let_go([], seen: items.first(5), rest: ['stale'])
    assert items.last.refresh.discarded_at
    assert_nil items.first.refresh.discarded_at
  end

  it 'takes the rest of a group to be whatever was not shown, even after a row was kept' do
    items = (1..7).map { |number| stale("SHOP-#{number}") }
    LetGo.detect(team_id: @team.id)
    LetGoReview.keep(item: items.first, actor: @person.actor)

    assert_equal 2, let_go([], seen: items.first(5), rest: ['stale'])
    gone = items.reject { |item| item.refresh.discarded_at.nil? }

    assert_equal items.last(2), gone
  end

  it 'takes a ticked row to have been seen' do
    items = (1..2).map { |number| stale("SHOP-#{number}") }
    LetGo.detect(team_id: @team.id)

    assert_equal 2, let_go([items.first], rest: ['stale'])
  end

  it 'stops suggesting an exhibit once it is kept, recording that' do
    item = stale('SHOP-1')
    LetGo.detect(team_id: @team.id)

    LetGoReview.keep(item: item, actor: @person.actor)

    assert_empty groups
    assert_equal ['kept'], Event.where(entity_id: item.id).select_map(:action)
  end

  it 'suggests an exhibit again once it is no longer kept' do
    item = stale('SHOP-1')
    LetGo.detect(team_id: @team.id)
    LetGoReview.keep(item: item, actor: @person.actor)

    LetGoReview.unkeep(item: item, actor: @person.actor)

    assert_equal ['stale'], groups.map(&:id)
  end

  it 'gives one exhibit its evidence, kept or not' do
    item = stale('SHOP-1')
    LetGo.detect(team_id: @team.id)
    LetGoReview.keep(item: item, actor: @person.actor)

    assert_equal 'Created Aug 2024 · never commented', LetGoReview.suggestion(item.refresh).evidence
  end

  it 'lets nothing go that the curator did not suggest' do
    suggested = stale('SHOP-1')
    wanted = add('SHOP-2')
    LetGo.detect(team_id: @team.id)

    assert_equal 1, let_go([suggested, wanted])
    assert_nil wanted.refresh.discarded_at
  end

  describe 'undoing a batch' do
    def batch_of(items)
      LetGoReview.let_go(team_id: @team.id, actor: @person.actor, ids: items.map(&:id)).batch
    end

    def undo(batch)
      LetGoReview.undo(team_id: @team.id, actor: @person.actor, batch: batch)
    end

    it 'brings back the whole batch, and nothing else in storage' do
      batch = stale('SHOP-1')
      other = stale('SHOP-2')
      elsewhere = stale('SHOP-3')
      LetGo.detect(team_id: @team.id)
      DiscardMuseumItem.call(item: elsewhere, actor: @person.actor)
      batch_of([other])
      id = batch_of([batch])

      assert_equal 1, undo(id)
      assert_nil batch.refresh.discarded_at
      assert_nil batch.storage_note
      assert other.refresh.discarded_at
      assert elsewhere.refresh.discarded_at
    end

    it 'leaves out what has been brought back since' do
      items = [stale('SHOP-1'), stale('SHOP-2')]
      LetGo.detect(team_id: @team.id)
      id = batch_of(items)
      DiscardMuseumItem.restore(item: items.first, actor: @person.actor)

      assert_equal 1, undo(id)
    end

    it 'has nothing to undo without a batch, or a second time' do
      item = stale('SHOP-1')
      LetGo.detect(team_id: @team.id)
      id = batch_of([item])
      undo(id)

      assert_equal 0, undo(id)
      assert_equal 0, undo(nil)
    end

    it "leaves another team's batch alone" do
      item = stale('SHOP-1')
      LetGo.detect(team_id: @team.id)
      id = batch_of([item])
      other = Team.create(name: 'Other')

      assert_equal 0, LetGoReview.undo(team_id: other.id, actor: @person.actor, batch: id)
      assert item.refresh.discarded_at
    end
  end

  it 'clears the note when the exhibit comes back out of storage' do
    item = stale('SHOP-1')
    LetGo.detect(team_id: @team.id)
    let_go([item])

    DiscardMuseumItem.restore(item: item, actor: @person.actor)

    assert_nil item.refresh.storage_note
  end

  describe 'duplicate pairs' do
    def twins(first, second, summary: 'Guests can check out without an account', **sides)
      [add(first, summary: summary, **sides.fetch(:first, {})), add(second, summary: summary, **sides.fetch(:second, {}))]
    end

    def pair_keys(pair)
      [pair.keeper.item.source_key, pair.other.item.source_key]
    end

    it 'keeps the side with more detail by default and counts the pair as one' do
      twins('SHOP-1', 'SHOP-2', first: { description: 'Short' }, second: { description: 'Steps to reproduce it, at length' })

      group = groups.first

      assert_equal 'dupes', group.id
      assert_equal 1, group.suggestions.size
      assert_equal %w[SHOP-2 SHOP-1], pair_keys(group.suggestions.first)
    end

    it 'keeps the first when neither side has more detail' do
      twins('SHOP-1', 'SHOP-2')

      assert_equal %w[SHOP-1 SHOP-2], pair_keys(groups.first.suggestions.first)
    end

    it 'says what each side has to go on' do
      twins('SHOP-1', 'SHOP-2', first: { description: 'Three whole words', comments: [{ 'text' => 'One' }, { 'text' => 'Two' }] },
        second: { description: '' })

      pair = groups.first.suggestions.first

      assert_equal '3 words · 2 comments', pair.keeper.evidence
      assert_equal 'No description · no comments', pair.other.evidence
    end

    it 'shows two pairs in a group and holds the rest back' do
      twins('SHOP-1', 'SHOP-2')
      twins('SHOP-3', 'SHOP-4', summary: 'Shoppers filter the results by price')
      twins('SHOP-5', 'SHOP-6', summary: 'Wishlist sharing between old friends')

      group = groups.first

      assert_equal 2, group.shown.size
      assert_equal 1, group.rest.size
    end

    it 'leaves out a pair once one side has gone' do
      first, = twins('SHOP-1', 'SHOP-2')
      LetGo.detect(team_id: @team.id)
      first.update(discarded_at: Time.now)

      assert_empty LetGoReview.groups(team_id: @team.id)
    end

    it 'lets go of the side chosen, whichever it is' do
      first, second = twins('SHOP-1', 'SHOP-2')
      LetGo.detect(team_id: @team.id)

      assert_equal 1, let_go([first])
      assert first.refresh.discarded_at
      assert_nil second.refresh.discarded_at
      assert_equal 'dupes', first.storage_note
    end

    it 'leaves a pair alone when neither side is chosen' do
      first, second = twins('SHOP-1', 'SHOP-2')
      LetGo.detect(team_id: @team.id)

      assert_equal 0, let_go([], seen: [first])
      assert_nil second.refresh.kept_at
    end

    it 'keeps both sides for good when asked' do
      first, second = twins('SHOP-1', 'SHOP-2')
      LetGo.detect(team_id: @team.id)

      assert_equal 0, let_go([], seen: [first], keep: ['SHOP-1'], rest: ['dupes'])
      assert first.refresh.kept_at
      assert second.refresh.kept_at
      assert_empty groups
    end

    it 'names a pair after its first key' do
      twins('SHOP-10', 'SHOP-2', first: { description: 'Longer description' })

      assert_equal 'SHOP-10', groups.first.suggestions.first.name
    end

    it 'never lets go of both sides' do
      sides = twins('SHOP-1', 'SHOP-2')
      LetGo.detect(team_id: @team.id)

      assert_equal 1, let_go(sides)
    end

    it 'lets go of the other side of each pair held back when asked' do
      shown, = twins('SHOP-1', 'SHOP-2')
      also, = twins('SHOP-3', 'SHOP-4', summary: 'Shoppers filter the results by price')
      kept, gone = twins('SHOP-5', 'SHOP-6', summary: 'Wishlist sharing between old friends')
      LetGo.detect(team_id: @team.id)

      assert_equal 1, let_go([], seen: [shown, also], rest: ['dupes'])
      assert_nil kept.refresh.discarded_at
      assert gone.refresh.discarded_at
    end
  end
end
