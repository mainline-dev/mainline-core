# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require_relative '../../lib/event_presenter'

describe EventPresenter do
  cover 'EventPresenter*'
  def build_event(action:, before_state: {}, after_state: {})
    Struct.new(:action, :before_state, :after_state).new(action, before_state, after_state)
  end

  def lookup(people: {}, slices: {}, tasks: {}, personas: {}, activities: {})
    { people: people, slices: slices, tasks: tasks, personas: personas, activities: activities }
  end

  it 'describes created with title' do
    event = build_event(action: 'created', after_state: { 'title' => 'Search for items' })

    assert_equal 'created "Search for items"', EventPresenter.describe(event, lookup)
  end

  it 'describes created without title' do
    event = build_event(action: 'created')

    assert_equal 'created', EventPresenter.describe(event, lookup)
  end

  it 'describes split_out with scenario count' do
    event = build_event(action: 'split_out', after_state: { 'scenario_count' => 1 })

    assert_equal 'split 1 scenario out to a new story', EventPresenter.describe(event, lookup)
  end

  it 'describes agent_read with user agent' do
    event = build_event(action: 'agent_read', after_state: { 'user_agent' => 'claude-code/2.0' })

    assert_equal 'read by AI agent (claude-code/2.0)', EventPresenter.describe(event, lookup)
  end

  it 'describes agent_read without user agent' do
    event = build_event(action: 'agent_read')

    assert_equal 'read by AI agent', EventPresenter.describe(event, lookup)
  end

  it 'describes person_assigned with name' do
    event = build_event(action: 'person_assigned', after_state: { 'person_id' => 'p1' })
    people = { 'p1' => Struct.new(:name).new('Alice') }

    assert_equal 'assigned Alice', EventPresenter.describe(event, lookup(people: people))
  end

  it 'describes person_assigned without name' do
    event = build_event(action: 'person_assigned', after_state: { 'person_id' => 'p1' })

    assert_equal 'assigned someone', EventPresenter.describe(event, lookup)
  end

  it 'describes person_unassigned with reason' do
    event = build_event(action: 'person_unassigned', before_state: { 'person_id' => 'p1', 'reason' => 'released' })
    people = { 'p1' => Struct.new(:name).new('Bob') }

    assert_equal 'unassigned Bob (released)', EventPresenter.describe(event, lookup(people: people))
  end

  it 'describes person_unassigned without reason' do
    event = build_event(action: 'person_unassigned', before_state: { 'person_id' => 'p1' })
    people = { 'p1' => Struct.new(:name).new('Bob') }

    assert_equal 'unassigned Bob', EventPresenter.describe(event, lookup(people: people))
  end

  it 'describes activated' do
    event = build_event(action: 'activated', after_state: { 'reason' => 'assigned', 'assignment_count' => 2 })

    assert_equal 'activated (assigned, 2 assignees)', EventPresenter.describe(event, lookup)
  end

  it 'describes deactivated' do
    event = build_event(action: 'deactivated', after_state: { 'reason' => 'unassigned' })

    assert_equal 'deactivated (unassigned)', EventPresenter.describe(event, lookup)
  end

  it 'describes released' do
    event = build_event(action: 'released')

    assert_equal 'marked as released', EventPresenter.describe(event, lookup)
  end

  it 'describes archived' do
    event = build_event(action: 'archived')

    assert_equal 'archived', EventPresenter.describe(event, lookup)
  end

  it 'describes deleted with name' do
    event = build_event(action: 'deleted', before_state: { 'name' => 'Sprint 1' })

    assert_equal 'deleted "Sprint 1"', EventPresenter.describe(event, lookup)
  end

  it 'describes deleted without name' do
    event = build_event(action: 'deleted')

    assert_equal 'deleted', EventPresenter.describe(event, lookup)
  end

  it 'describes slice_changed to a slice' do
    event = build_event(action: 'slice_changed', after_state: { 'release_slice_id' => 's1' })
    slices = { 's1' => Struct.new(:name).new('Sprint 1') }

    assert_equal 'moved to slice: Sprint 1', EventPresenter.describe(event, lookup(slices: slices))
  end

  it 'describes slice_changed removed from slice' do
    event = build_event(action: 'slice_changed', after_state: { 'release_slice_id' => nil })

    assert_equal 'removed from slice', EventPresenter.describe(event, lookup)
  end

  it 'describes edited with task change' do
    event = build_event(
      action:       'edited',
      before_state: { 'task_id' => 't1', 'title' => 'X' },
      after_state:  { 'task_id' => 't2', 'title' => 'X' }
    )
    tasks = { 't1' => Struct.new(:name).new('Register'), 't2' => Struct.new(:name).new('Login') }

    assert_equal 'moved from task: Register to task: Login', EventPresenter.describe(event, lookup(tasks: tasks))
  end

  it 'describes edited with title rename' do
    event = build_event(
      action:       'edited',
      before_state: { 'task_id' => 't1', 'title' => 'Old' },
      after_state:  { 'task_id' => 't1', 'title' => 'New' }
    )

    assert_equal 'renamed to "New"', EventPresenter.describe(event, lookup)
  end

  it 'describes edited with decoupling tag added' do
    event = build_event(
      action:       'edited',
      before_state: { 'task_id' => 't1', 'title' => 'X', 'decoupling_strategy' => nil },
      after_state:  { 'task_id' => 't1', 'title' => 'X', 'decoupling_strategy' => 'flag' }
    )

    assert_equal 'tagged Feature flag', EventPresenter.describe(event, lookup)
  end

  it 'describes edited with decoupling tag and label' do
    event = build_event(
      action:       'edited',
      before_state: { 'task_id' => 't1', 'title' => 'X', 'decoupling_strategy' => nil },
      after_state:  { 'task_id' => 't1', 'title' => 'X', 'decoupling_strategy' => 'bba',
                      'decoupling_label' => 'PaymentV2' }
    )

    assert_equal 'tagged BBA (PaymentV2)', EventPresenter.describe(event, lookup)
  end

  it 'describes edited with decoupling tag removed' do
    event = build_event(
      action:       'edited',
      before_state: { 'task_id' => 't1', 'title' => 'X', 'decoupling_strategy' => 'flag' },
      after_state:  { 'task_id' => 't1', 'title' => 'X', 'decoupling_strategy' => nil }
    )

    assert_equal 'decoupling tag removed', EventPresenter.describe(event, lookup)
  end

  it 'describes label changed' do
    event = build_event(
      action:       'edited',
      before_state: { 'task_id' => 't1', 'title' => 'X', 'decoupling_strategy' => 'flag', 'decoupling_label' => 'OLD_FF' },
      after_state:  { 'task_id' => 't1', 'title' => 'X', 'decoupling_strategy' => 'flag', 'decoupling_label' => 'NEW_FF' }
    )

    assert_equal 'label changed from "OLD_FF" to "NEW_FF"', EventPresenter.describe(event, lookup)
  end

  it 'describes label set' do
    event = build_event(
      action:       'edited',
      before_state: { 'task_id' => 't1', 'title' => 'X', 'decoupling_strategy' => 'flag', 'decoupling_label' => nil },
      after_state:  { 'task_id' => 't1', 'title' => 'X', 'decoupling_strategy' => 'flag', 'decoupling_label' => 'MY_FLAG' }
    )

    assert_equal 'label set to "MY_FLAG"', EventPresenter.describe(event, lookup)
  end

  it 'describes label removed' do
    event = build_event(
      action:       'edited',
      before_state: { 'task_id' => 't1', 'title' => 'X', 'decoupling_strategy' => 'flag', 'decoupling_label' => 'OLD_FF' },
      after_state:  { 'task_id' => 't1', 'title' => 'X', 'decoupling_strategy' => 'flag', 'decoupling_label' => nil }
    )

    assert_equal 'label "OLD_FF" removed', EventPresenter.describe(event, lookup)
  end

  it 'describes edited with multiple changes' do
    event = build_event(
      action:       'edited',
      before_state: { 'task_id' => 't1', 'title' => 'Old' },
      after_state:  { 'task_id' => 't2', 'title' => 'New' }
    )
    tasks = { 't1' => Struct.new(:name).new('Register'), 't2' => Struct.new(:name).new('Login') }

    assert_equal 'moved from task: Register to task: Login, renamed to "New"',
      EventPresenter.describe(event, lookup(tasks: tasks))
  end

  it 'describes edited with no detectable changes as edited' do
    event = build_event(
      action:       'edited',
      before_state: { 'task_id' => 't1', 'title' => 'X' },
      after_state:  { 'task_id' => 't1', 'title' => 'X' }
    )

    assert_equal 'edited', EventPresenter.describe(event, lookup)
  end

  it 'describes task_changed with from and to' do
    event = build_event(
      action:       'task_changed',
      before_state: { 'task_id' => 't1' },
      after_state:  { 'task_id' => 't2' }
    )
    tasks = { 't1' => Struct.new(:name).new('Register'), 't2' => Struct.new(:name).new('Login') }

    assert_equal 'moved from task: Register to task: Login', EventPresenter.describe(event, lookup(tasks: tasks))
  end

  it 'describes collaboration_changed from solo to paired' do
    event = build_event(
      action:       'collaboration_changed',
      before_state: { 'mode' => 'solo', 'assignment_count' => 1 },
      after_state:  { 'mode' => 'paired', 'assignment_count' => 2 }
    )

    assert_equal 'solo to paired', EventPresenter.describe(event, lookup)
  end

  it 'describes collaboration_changed from paired to solo' do
    event = build_event(
      action:       'collaboration_changed',
      before_state: { 'mode' => 'paired', 'assignment_count' => 2 },
      after_state:  { 'mode' => 'solo', 'assignment_count' => 1 }
    )

    assert_equal 'paired to solo', EventPresenter.describe(event, lookup)
  end

  it 'describes deployed' do
    event = build_event(action: 'deployed', after_state: { 'deploy_count' => 1 })

    assert_equal 'marked as deployed', EventPresenter.describe(event, lookup)
  end

  it 'describes reordered' do
    event = build_event(action: 'reordered')

    assert_equal 'reordered', EventPresenter.describe(event, lookup)
  end

  it 'falls back to humanized action for unknown events' do
    event = build_event(action: 'something_new')

    assert_equal 'something new', EventPresenter.describe(event, lookup)
  end

  it 'describes edited with persona added' do
    event = build_event(
      action:       'edited',
      before_state: { 'name' => 'Browse', 'persona_ids' => ['p1'] },
      after_state:  { 'name' => 'Browse', 'persona_ids' => %w[p1 p2] }
    )
    personas = { 'p2' => Struct.new(:name).new('Admin') }

    assert_equal 'added persona Admin',
      EventPresenter.describe(event, lookup(personas: personas))
  end

  it 'describes edited with persona removed' do
    event = build_event(
      action:       'edited',
      before_state: { 'name' => 'Browse', 'persona_ids' => %w[p1 p2] },
      after_state:  { 'name' => 'Browse', 'persona_ids' => ['p1'] }
    )
    personas = { 'p2' => Struct.new(:name).new('Admin') }

    assert_equal 'removed persona Admin',
      EventPresenter.describe(event, lookup(personas: personas))
  end

  it 'describes edited with persona added and removed' do
    event = build_event(
      action:       'edited',
      before_state: { 'name' => 'Browse', 'persona_ids' => %w[p1 p2] },
      after_state:  { 'name' => 'Browse', 'persona_ids' => %w[p1 p3] }
    )
    personas = {
      'p2' => Struct.new(:name).new('Admin'),
      'p3' => Struct.new(:name).new('Guest')
    }

    assert_equal 'added persona Guest, removed persona Admin',
      EventPresenter.describe(event, lookup(personas: personas))
  end

  it 'describes edited with name and persona change' do
    event = build_event(
      action:       'edited',
      before_state: { 'name' => 'Browse', 'persona_ids' => ['p1'] },
      after_state:  { 'name' => 'Search', 'persona_ids' => %w[p1 p2] }
    )
    personas = { 'p2' => Struct.new(:name).new('Admin') }

    assert_equal 'renamed "Browse" to "Search", added persona Admin',
      EventPresenter.describe(event, lookup(personas: personas))
  end

  it 'describes edited with activity added' do
    event = build_event(
      action:       'edited',
      before_state: { 'name' => 'Customer', 'activity_ids' => ['a1'] },
      after_state:  { 'name' => 'Customer', 'activity_ids' => %w[a1 a2] }
    )
    activities = { 'a2' => Struct.new(:name).new('Checkout') }

    assert_equal 'added activity Checkout',
      EventPresenter.describe(event, lookup(activities: activities))
  end

  it 'describes edited with activity removed' do
    event = build_event(
      action:       'edited',
      before_state: { 'name' => 'Customer', 'activity_ids' => %w[a1 a2] },
      after_state:  { 'name' => 'Customer', 'activity_ids' => ['a1'] }
    )
    activities = { 'a2' => Struct.new(:name).new('Checkout') }

    assert_equal 'removed activity Checkout',
      EventPresenter.describe(event, lookup(activities: activities))
  end

  it 'describes edited with description changed' do
    event = build_event(
      action:       'edited',
      before_state: { 'name' => 'Customer', 'description' => 'Old desc' },
      after_state:  { 'name' => 'Customer', 'description' => 'New desc' }
    )

    assert_equal 'updated "Customer" description', EventPresenter.describe(event, lookup)
  end

  it 'describes edited with description added' do
    event = build_event(
      action:       'edited',
      before_state: { 'name' => 'Customer', 'description' => '' },
      after_state:  { 'name' => 'Customer', 'description' => 'Some text' }
    )

    assert_equal 'updated "Customer" description', EventPresenter.describe(event, lookup)
  end

  it 'omits name from created when include_name is false' do
    event = build_event(action: 'created', after_state: { 'title' => 'Search for items' })

    assert_equal 'created', EventPresenter.describe(event, lookup, include_name: false)
  end

  it 'omits name from deleted when include_name is false' do
    event = build_event(action: 'deleted', before_state: { 'name' => 'Sprint 1' })

    assert_equal 'deleted', EventPresenter.describe(event, lookup, include_name: false)
  end

  it 'omits name from edited rename when include_name is false' do
    event = build_event(
      action:       'edited',
      before_state: { 'task_id' => 't1', 'name' => 'Old' },
      after_state:  { 'task_id' => 't1', 'name' => 'New' }
    )

    assert_equal 'renamed', EventPresenter.describe(event, lookup, include_name: false)
  end

  it 'omits name from edited title rename when include_name is false' do
    event = build_event(
      action:       'edited',
      before_state: { 'task_id' => 't1', 'title' => 'Old' },
      after_state:  { 'task_id' => 't1', 'title' => 'New' }
    )

    assert_equal 'renamed', EventPresenter.describe(event, lookup, include_name: false)
  end

  it 'omits name from description update when include_name is false' do
    event = build_event(
      action:       'edited',
      before_state: { 'name' => 'Customer', 'description' => 'Old' },
      after_state:  { 'name' => 'Customer', 'description' => 'New' }
    )

    assert_equal 'description updated', EventPresenter.describe(event, lookup, include_name: false)
  end
end
