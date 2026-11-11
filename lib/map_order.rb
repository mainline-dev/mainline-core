# frozen_string_literal: true

# A team's stories in the order its maps give them: map by map, release slice
# by release slice, and within a slice left to right across the map (activity,
# then step) and down each step. Stories with no release slice come first, as
# the map shows them. Archived maps, activities, steps and stories are left
# out. Call it with the team's context set.
module MapOrder
  Placed = Struct.new(:story_map, :slice, :story, keyword_init: true)

  def self.for(team_id)
    Map.where(team_id: team_id, archived_at: nil).order(:position).all.flat_map { |map| on(map) }
  end

  def self.on(map)
    slices = ReleaseSlice.where(map_id: map.id, archived_at: nil).order(:position).all
    across = left_to_right(map)
    stories = Story.where(map_id: map.id, archived_at: nil).all.select { |story| across.key?(story.task_id) }
    stories
      .sort_by { |story| [slices.index { |slice| slice.id == story.release_slice_id } || -1, across[story.task_id], story.position] }
      .map { |story| Placed.new(story_map: map, story: story, slice: slices.find { |slice| slice.id == story.release_slice_id }) }
  end

  # Each open step's place reading the map left to right: { step id => place }.
  def self.left_to_right(map)
    activities = Activity.where(map_id: map.id, archived_at: nil).order(:position).select_map(:id)
    Task.where(map_id: map.id, archived_at: nil, activity_id: activities).all
      .sort_by { |task| [activities.index(task.activity_id), task.position] }
      .each_with_index.to_h { |task, place| [task.id, place] }
  end
  private_class_method :on, :left_to_right
end
