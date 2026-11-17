# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/edit_story'

describe EditStory do
  cover 'EditStory*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    @pay = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @ship = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Ship', position: 2000)
    @gift = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Gift wrap', position: 3000)
    @slice = ReleaseSlice.create(map_id: map.id, team_id: @team.id, name: 'MVP', position: 1000)
    @story = story('Guest checkout', @pay, 1000)
    story('Refund an order', @pay, 9000)
    @already_shipping = story('Track a parcel', @ship, 5000)
    story('Print a label', @ship, 3000)
    story('Use the old courier', @ship, 8000).update(archived_at: Time.now)
  end

  def story(title, task, position)
    Story.create(task_id: task.id, map_id: task.map_id, team_id: @team.id, title: title, position: position,
      created_by_id: @person.id)
  end

  def edit(title: 'Guest checkout', task_id: @pay.id, release_slice_id: '', strategy: '', label: '')
    EditStory.call(story: @story, actor: @person.actor, title: title, task_id: task_id, release_slice_id: release_slice_id,
      decoupling_strategy: strategy, decoupling_label: label)
  end

  def edits
    Event.where(entity_id: @story.id, action: 'edited').order(:event_no).all
  end

  def stored(*columns)
    @story.refresh.values.values_at(*columns)
  end

  it 'saves the title, slice and decoupling, and records what they were and became' do
    result = edit(title: 'Pay as a guest', release_slice_id: @slice.id, strategy: 'flag', label: 'FF_GUEST')

    assert_equal [true, []], [result.success?, result.errors]
    assert_equal ['Pay as a guest', @pay.id, 1000, @slice.id, 'flag', 'FF_GUEST'],
      stored(:title, :task_id, :position, :release_slice_id, :decoupling_strategy, :decoupling_label)
    assert_equal [{ 'title' => 'Guest checkout', 'task_id' => @pay.id, 'release_slice_id' => nil,
                    'decoupling_strategy' => nil, 'decoupling_label' => nil }], edits.map(&:before_state)
    assert_equal [{ 'title' => 'Pay as a guest', 'task_id' => @pay.id, 'release_slice_id' => @slice.id,
                    'decoupling_strategy' => 'flag', 'decoupling_label' => 'FF_GUEST' }], edits.map(&:after_state)
  end

  it 'moves a story to another step after the stories still there, recording where it went' do
    edit(task_id: @ship.id)

    assert_equal [@ship.id, 6000], stored(:task_id, :position)
    assert_equal 5000, @already_shipping.refresh.position
    refute edits.last.before_state.key?('position')
    assert_equal 6000, edits.last.after_state['position']
  end

  it 'puts a story moved to an empty step first' do
    edit(task_id: @gift.id)

    assert_equal [@gift.id, 1000], stored(:task_id, :position)
  end

  it 'takes the story out of its release slice when none is given, however the form sends that' do
    edit(release_slice_id: @slice.id)
    edit(release_slice_id: '')
    cleared = stored(:release_slice_id)
    edit(release_slice_id: @slice.id)
    edit(release_slice_id: nil)

    assert_equal [[nil], [nil]], [cleared, stored(:release_slice_id)]
  end

  it 'keeps a label only with a strategy, and at most 50 characters of it' do
    edit(strategy: 'flag', label: 'L' * 60)
    long = stored(:decoupling_label)
    edit(strategy: 'flag', label: '')
    empty = stored(:decoupling_label)
    edit(strategy: 'flag', label: nil)
    missing = stored(:decoupling_label)
    edit(strategy: nil, label: 'FF_GUEST')
    no_strategy = stored(:decoupling_strategy, :decoupling_label)
    edit(strategy: '', label: 'FF_GUEST')

    assert_equal [['L' * 50], [nil], [nil], [nil, nil]], [long, empty, missing, no_strategy]
    assert_equal [nil, nil], stored(:decoupling_strategy, :decoupling_label)
    assert_nil edits.last.after_state['decoupling_label']
  end

  it 'refuses a story with no title, one too long, or no step, saying which, and changes nothing' do
    missing = edit(title: nil, task_id: nil)
    too_long = edit(title: 'T' * 201)

    said = missing.errors + too_long.errors

    assert_equal [false, 2], [missing.success?, missing.errors.size]
    assert_equal [false, 1], [too_long.success?, too_long.errors.size]
    refute_equal missing.errors.first, too_long.errors.first
    assert(said.all? { |error| error.is_a?(String) && !error.empty? })
    assert_includes too_long.errors.first, EditStory::TITLE_LENGTH.to_s
    assert_equal ['Guest checkout', @pay.id], stored(:title, :task_id)
    assert_empty edits
  end

  it 'takes a title of 200 characters' do
    assert_predicate edit(title: 'T' * 200), :success?
  end

  describe 'a released story' do
    before { @story.update(status: 'released', released_at: Time.now) }

    it 'changes only how it was decoupled, recording that alone' do
      result = edit(title: 'Pay as a guest', task_id: @ship.id, strategy: 'bba', label: 'B' * 60)

      assert_equal [true, []], [result.success?, result.errors]
      assert_equal ['Guest checkout', @pay.id, 'bba', 'B' * 50], stored(:title, :task_id, :decoupling_strategy, :decoupling_label)
      assert_equal [{ 'decoupling_strategy' => nil, 'decoupling_label' => nil }], edits.map(&:before_state)
      assert_equal [{ 'decoupling_strategy' => 'bba', 'decoupling_label' => 'B' * 50 }], edits.map(&:after_state)
    end

    it 'clears its decoupling, label and all, when no strategy is given' do
      edit(strategy: 'bba', label: 'BBA_GUEST')
      edit(strategy: '', label: 'BBA_GUEST')

      assert_equal [nil, nil], stored(:decoupling_strategy, :decoupling_label)
    end
  end
end
