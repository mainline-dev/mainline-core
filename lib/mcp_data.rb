# frozen_string_literal: true

# What the MCP tools say about a map and a story, as JSON-ready hashes: the
# map's whole hierarchy, and a story with its scenarios. The tools choose
# which map or story; this only describes it.
module McpData
  def self.map(map)
    activities = Activity.where(map_id: map.id, archived_at: nil).order(:position).all
    slices = ReleaseSlice.where(map_id: map.id, archived_at: nil).order(:position).all
    personas = Persona.where(map_id: map.id, archived_at: nil).order(:position).all

    {
      id:             map.id,
      name:           map.name,
      activities:     activities.map { |act| activity(act) },
      release_slices: slices.map { |s| { id: s.id, name: s.name, position: s.position } },
      personas:       personas.map { |p| { id: p.id, name: p.name, description: p.description } }
    }
  end

  def self.activity(activity)
    tasks = Task.where(activity_id: activity.id, archived_at: nil).order(:position).all
    {
      id:       activity.id,
      name:     activity.name,
      position: activity.position,
      steps:    tasks.map { |t| task(t) }
    }
  end

  def self.task(task)
    stories = Story.where(task_id: task.id, archived_at: nil).order(:position).all
    {
      id:       task.id,
      name:     task.name,
      position: task.position,
      stories:  stories.map { |s| story_summary(s) }
    }
  end

  def self.story_summary(story)
    {
      id:               story.id,
      short_id:         story.id[0, 8].upcase,
      title:            story.title,
      status:           story.status,
      position:         story.position,
      release_slice_id: story.release_slice_id,
      deploy_count:     story.deploy_count
    }
  end

  def self.story(story)
    {
      id:                  story.id,
      short_id:            story.id[0, 8].upcase,
      title:               story.title,
      description:         story.description,
      status:              story.status,
      position:            story.position,
      release_slice_id:    story.release_slice_id,
      deploy_count:        story.deploy_count,
      first_deployed_at:   story.first_deployed_at&.iso8601,
      last_deployed_at:    story.last_deployed_at&.iso8601,
      decoupling_strategy: story.decoupling_strategy,
      decoupling_label:    story.decoupling_label,
      scenarios:           scenarios(story),
      assigned_count:      StoryAssignment.where(story_id: story.id).count
    }
  end

  def self.scenarios(story)
    Scenario.where(story_id: story.id).order(:position).all.map { |s|
      { name: s.display_name, given: s.given_text, when: s.when_text, then: s.then_text, done: !s.done_at.nil? }
    }
  end
end
