# frozen_string_literal: true

module MapGrid
  Result = Struct.new(:grid_activities, :total_cols, :sliced, :slice_groups, :slice_sort, keyword_init: true)

  def self.call(activities:, release_slices:, active_filter:, slices_view:, slice_filter: nil, hide_released: false)
    grid_activities = grid_activities(activities, active_filter, slice_filter, hide_released)
    sliced = slices_view && release_slices.any?

    Result.new(
      grid_activities: grid_activities,
      total_cols:      grid_activities.sum { |_, tasks| [tasks.length, 1].max },
      sliced:          sliced,
      slice_groups:    sliced ? [nil] + visible_slices(release_slices, slice_filter) : [nil],
      slice_sort:      release_slices.to_h { |s| [s.id, s.position] }
    )
  end

  def self.grid_activities(activities, active_filter, slice_filter, hide_released)
    filtering = active_filter || slice_filter
    activities.filter_map { |activity|
      tasks = activity.tasks.select { |t| t.archived_at.nil? }.sort_by(&:position)
      next [activity, tasks] unless filtering

      tasks = tasks.select { |t| t.stories.any? { |s| story_visible?(s, active_filter, slice_filter, hide_released) } }
      [activity, tasks] unless tasks.empty?
    }
  end

  def self.visible_slices(release_slices, slice_filter)
    slice_filter ? release_slices.select { |s| s.id == slice_filter } : release_slices.to_a
  end

  def self.story_visible?(story, active_filter, slice_filter, hide_released)
    story.archived_at.nil? &&
      (!active_filter || story.status == 'active') &&
      (slice_filter.nil? || story.release_slice_id == slice_filter) &&
      (!hide_released || active_filter || story.status != 'released')
  end

  def self.visible_stories(task, slice, sliced:, active_filter:, slice_sort:, hide_released: false, slice_filter: nil)
    task.stories
      .select { |s| story_visible?(s, active_filter, slice_filter, hide_released) }
      .select { |s| !sliced || s.release_slice_id == slice&.id }
      .sort_by { |s| [slice_sort.fetch(s.release_slice_id, -1), s.position] }
  end

  private_class_method :grid_activities, :visible_slices
end
