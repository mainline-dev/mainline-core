# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/map_grid'

describe MapGrid do
  cover 'MapGrid*'
  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'User', position: 1000)
    @activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    ActivityPersona.create(activity_id: @activity.id, persona_id: @persona.id, team_id: @team.id)
    @task = Task.create(activity_id: @activity.id, map_id: @map.id, team_id: @team.id, name: 'Search', position: 1000)
  end

  def create_story(title, task: @task, position: nil)
    pos = position || ((Story.where(task_id: task.id).max(:position) || 0) + 1000)
    Story.create(
      task_id: task.id, map_id: @map.id, team_id: @team.id,
      title: title, position: pos, created_by_id: @person.id
    )
  end

  def load_activities
    Activity
      .where(map_id: @map.id, archived_at: nil)
      .order(:position)
      .eager(:personas, tasks: {stories: [:release_slice, {story_assignments: :person}]})
      .all
  end

  def build_grid(active_filter: false, slices_view: false, release_slices: [])
    MapGrid.call(
      activities:     load_activities,
      release_slices: release_slices,
      active_filter:  active_filter,
      slices_view:    slices_view
    )
  end

  describe '.call' do
    it 'returns all activities with non-archived tasks' do
      create_story('Find things')
      grid = build_grid

      assert_equal 1, grid.grid_activities.length
      activity, tasks = grid.grid_activities.first

      assert_equal @activity.id, activity.id
      assert_equal 1, tasks.length
      assert_equal @task.id, tasks.first.id
    end

    it 'excludes archived tasks' do
      @task.update(archived_at: Time.now)
      task2 = Task.create(activity_id: @activity.id, map_id: @map.id, team_id: @team.id, name: 'Filter', position: 2000)
      create_story('Filter things', task: task2)
      grid = build_grid

      assert_equal 1, grid.grid_activities.length
      _, tasks = grid.grid_activities.first

      assert_equal [task2.id], tasks.map(&:id)
    end

    it 'active filter removes tasks with no active stories' do
      create_story('Planned only')

      grid = build_grid(active_filter: true)

      assert_equal 0, grid.grid_activities.length
    end

    it 'active filter keeps tasks that have active stories' do
      story = create_story('Active one')
      StoryAssignment.create(story_id: story.id, person_id: @person.id, team_id: @team.id)
      bob = Person.create(name: 'Bob', email: 'bob@test.mainline')
      StoryAssignment.create(story_id: story.id, person_id: bob.id, team_id: @team.id)
      story.update(status: 'active')

      grid = build_grid(active_filter: true)

      assert_equal 1, grid.grid_activities.length
    end

    it 'active filter removes activities that become empty' do
      activity2 = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Checkout', position: 2000)
      ActivityPersona.create(activity_id: activity2.id, persona_id: @persona.id, team_id: @team.id)
      task2 = Task.create(activity_id: activity2.id, map_id: @map.id, team_id: @team.id, name: 'Pay', position: 1000)
      create_story('Planned', task: task2)

      story = create_story('Active one')
      StoryAssignment.create(story_id: story.id, person_id: @person.id, team_id: @team.id)
      bob = Person.create(name: 'Bob', email: 'bob@test.mainline')
      StoryAssignment.create(story_id: story.id, person_id: bob.id, team_id: @team.id)
      story.update(status: 'active')

      grid = build_grid(active_filter: true)

      assert_equal 1, grid.grid_activities.length
      assert_equal @activity.id, grid.grid_activities.first.first.id
    end

    it 'computes total_cols as sum of task spans' do
      task2 = Task.create(activity_id: @activity.id, map_id: @map.id, team_id: @team.id, name: 'Filter', position: 2000)
      create_story('S1')
      create_story('S2', task: task2)

      grid = build_grid

      assert_equal 2, grid.total_cols
    end

    it 'total_cols counts at least 1 per activity with no tasks' do
      @task.update(archived_at: Time.now)
      grid = build_grid

      assert_equal 1, grid.total_cols
    end

    it 'sliced mode sets slice_groups with nil first then slices' do
      s1 = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'MVP', position: 1000)
      s2 = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'Beta', position: 2000)

      grid = build_grid(slices_view: true, release_slices: [s1, s2])

      assert grid.sliced
      assert_equal 3, grid.slice_groups.length
      assert_nil grid.slice_groups[0]
      assert_equal s1.id, grid.slice_groups[1].id
      assert_equal s2.id, grid.slice_groups[2].id
    end

    it 'non-sliced mode returns single nil group' do
      grid = build_grid(slices_view: false)

      refute grid.sliced
      assert_equal [nil], grid.slice_groups
    end

    it 'builds slice_sort lookup from release slices' do
      s1 = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'MVP', position: 1000)
      s2 = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'Beta', position: 2000)

      grid = build_grid(release_slices: [s1, s2])

      assert_equal 1000, grid.slice_sort[s1.id]
      assert_equal 2000, grid.slice_sort[s2.id]
    end
  end

  describe '.visible_stories' do
    it 'excludes archived stories' do
      s1 = create_story('Visible')
      s2 = create_story('Archived')
      s2.update(archived_at: Time.now)

      visible = MapGrid.visible_stories(@task.refresh, nil,
        sliced: false, active_filter: false, slice_sort: {})

      assert_equal [s1.id], visible.map(&:id)
    end

    it 'filters by slice when sliced' do
      slice = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'MVP', position: 1000)
      s1 = create_story('In slice')
      s1.update(release_slice_id: slice.id)
      create_story('Unsliced')

      visible = MapGrid.visible_stories(@task.refresh, slice,
        sliced: true, active_filter: false, slice_sort: {slice.id => 1000})

      assert_equal [s1.id], visible.map(&:id)
    end

    it 'returns unsliced stories when slice is nil in sliced mode' do
      slice = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'MVP', position: 1000)
      s1 = create_story('In slice')
      s1.update(release_slice_id: slice.id)
      s2 = create_story('Unsliced')

      visible = MapGrid.visible_stories(@task.refresh, nil,
        sliced: true, active_filter: false, slice_sort: {slice.id => 1000})

      assert_equal [s2.id], visible.map(&:id)
    end

    it 'filters by active when active_filter' do
      s1 = create_story('Active one')
      s1.update(status: 'active')
      create_story('Planned')

      visible = MapGrid.visible_stories(@task.refresh, nil,
        sliced: false, active_filter: true, slice_sort: {})

      assert_equal [s1.id], visible.map(&:id)
    end

    it 'includes released stories by default' do
      s1 = create_story('Active')
      s1.update(status: 'active')
      s2 = create_story('Released')
      s2.update(status: 'released', released_at: Time.now)

      visible = MapGrid.visible_stories(@task.refresh, nil,
        sliced: false, active_filter: false, slice_sort: {})

      assert_includes visible.map(&:id), s2.id
    end

    it 'excludes released stories when hide_released is true' do
      s1 = create_story('Active')
      s1.update(status: 'active')
      s2 = create_story('Released')
      s2.update(status: 'released', released_at: Time.now)

      visible = MapGrid.visible_stories(@task.refresh, nil,
        sliced: false, active_filter: false, slice_sort: {}, hide_released: true)

      assert_equal [s1.id], visible.map(&:id)
    end

    it 'sorts unsliced first then by slice position then story position' do
      slice_a = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'Alpha', position: 1000)
      slice_b = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'Beta', position: 2000)
      s_beta = create_story('In Beta', position: 1000)
      s_beta.update(release_slice_id: slice_b.id)
      s_alpha = create_story('In Alpha', position: 2000)
      s_alpha.update(release_slice_id: slice_a.id)
      s_unsliced = create_story('Unsliced', position: 3000)

      slice_sort = { slice_a.id => 1000, slice_b.id => 2000 }
      visible = MapGrid.visible_stories(@task.refresh, nil,
        sliced: false, active_filter: false, slice_sort: slice_sort)

      assert_equal [s_unsliced.id, s_alpha.id, s_beta.id], visible.map(&:id)
    end
  end
end
