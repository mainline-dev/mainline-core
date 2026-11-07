# frozen_string_literal: true

require_relative 'rebalance_positions'
require_relative 'record_event'

module SplitStory
  def self.call(story:, actor:, person:, title:, scenario_ids:, scenario_edits: {})
    return :released if story.status == 'released'
    return :archived if story.archived_at

    title = title.to_s.strip
    return :title_required if title.empty?
    return :title_too_long if title.length > 200

    scenarios = Scenario.where(id: Array(scenario_ids), story_id: story.id).order(:position).all
    return :scenarios_required if scenarios.empty?
    return :scenario_invalid unless edits_valid?(scenarios, scenario_edits)

    child = nil
    DB.transaction do
      child = create_child(story, title, person)
      place_after(story, child.id)
      move_scenarios(scenarios, child, scenario_edits)
      record_events(story, child, actor, scenarios.length)
    end
    child
  end

  def self.edits_valid?(scenarios, edits)
    scenarios.all? do |sc|
      edit = edits[sc.id] || {}
      %i[given when then].all? do |key|
        value = edit[key]
        next true if value.nil?

        stripped = value.to_s.strip
        !stripped.empty? && stripped.length <= 100
      end
    end
  end
  private_class_method :edits_valid?

  def self.create_child(story, title, person)
    temp_pos = (Story.where(task_id: story.task_id).max(:position) || 0) + RebalancePositions::GAP
    Story.create(
      title: title, description: '', task_id: story.task_id, map_id: story.map_id,
      team_id: story.team_id, position: temp_pos, status: 'planned',
      split_from_id: story.id, created_by_id: person.id
    )
  end
  private_class_method :create_child

  def self.place_after(original, child_id)
    all = Story.where(task_id: original.task_id, archived_at: nil).order(:position).all
    ordered = []
    all.each do |s|
      next if s.id == child_id

      ordered << s.id
      ordered << child_id if s.id == original.id
    end
    RebalancePositions.assign(:stories, all.map(&:id), ordered)
  end
  private_class_method :place_after

  def self.move_scenarios(scenarios, child, edits)
    scenarios.each do |sc|
      fields = { story_id: child.id }
      edit = edits[sc.id] || {}
      %i[given when then].each do |key|
        text = edit[key]&.strip
        fields[:"#{key}_text"] = text if text && !text.empty?
      end
      DB[:scenarios].where(id: sc.id).update(fields)
    end
  end
  private_class_method :move_scenarios

  def self.record_events(story, child, actor, count)
    RecordEvent.call(
      actor_id:    actor.id,
      entity:      story,
      action:      'split_out',
      after_state: { split_to_id: child.id, scenario_count: count }
    )
    RecordEvent.call(
      actor_id:    actor.id,
      entity:      child,
      action:      'created',
      after_state: { title: child.title, split_from_id: story.id }
    )
  end
  private_class_method :record_events
end
