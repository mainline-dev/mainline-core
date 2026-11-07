# frozen_string_literal: true

module AssignPerson
  Result = Struct.new(:success?, :errors, keyword_init: true)

  def self.call(story:, person_id:, team:, actor_id:)
    errors = validate(story, person_id, team)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    DB.transaction do
      StoryAssignment.create(story_id: story.id, person_id: person_id, team_id: team.id)
      RecordEvent.call(
        actor_id: actor_id, entity: story,
        action: 'person_assigned', after_state: { person_id: person_id }
      )

      count = StoryAssignment.where(story_id: story.id).count
      if story.status == 'planned'
        maybe_activate(story, team, actor_id, count)
      elsif story.status == 'active'
        record_collaboration_change(story, actor_id, count - 1, count)
      end
    end

    Result.new(success?: true, errors: [])
  rescue Sequel::UniqueConstraintViolation
    Result.new(success?: false, errors: ['Person is already assigned to another active story'])
  end

  def self.validate(story, person_id, team)
    errors = []
    errors << 'Cannot assign people to a released story' if story.status == 'released'
    errors << 'Person is required' if person_id.nil? || person_id.to_s.empty?
    return errors unless errors.empty?

    conflict = assignment_conflict(story, person_id, team)
    conflict ? [conflict] : []
  end
  private_class_method :validate

  def self.assignment_conflict(story, person_id, team)
    unless TeamMembership.where(team_id: team.id, person_id: person_id, left_at: nil, working: true).any?
      return 'Person is not a team member'
    end
    return 'Person is already assigned to this story' if StoryAssignment.where(story_id: story.id, person_id: person_id).any?

    'Person is already assigned to another active story' if assigned_elsewhere?(person_id, team)
  end
  private_class_method :assignment_conflict

  def self.assigned_elsewhere?(person_id, team)
    StoryAssignment
      .join(:stories, id: :story_id)
      .where(Sequel[:story_assignments][:person_id] => person_id,
        Sequel[:story_assignments][:team_id] => team.id)
      .where(Sequel[:stories][:archived_at] => nil)
      .any?
  end
  private_class_method :assigned_elsewhere?

  def self.maybe_activate(story, team, actor_id, count)
    return unless story.status == 'planned'

    working_count = TeamMembership.where(team_id: team.id, working: true).count
    solo_allowed = working_count == 1 ||
                   TeamConstraint.for_team(team.id, 'allow_solo_activation', default: 0) == 1
    return unless count >= 2 || (solo_allowed && count >= 1)

    reason = count >= 2 ? 'paired' : 'solo'
    story.update(status: 'active')
    RecordEvent.call(
      actor_id: actor_id, entity: story,
      action: 'activated', after_state: { reason: reason, assignment_count: count }
    )
    record_collaboration_change(story, actor_id, count - 1, count)
  end
  private_class_method :maybe_activate

  def self.record_collaboration_change(story, actor_id, before_count, after_count)
    before_mode = collaboration_mode(before_count)
    after_mode = collaboration_mode(after_count)
    return if before_mode == after_mode

    after_state = { mode: after_mode, assignment_count: after_count }
    person_ids = StoryAssignment.where(story_id: story.id).select_map(:person_id)
    after_state[:person_ids] = person_ids
    after_state[:solo_person_id] = person_ids.first if after_mode == 'solo'

    RecordEvent.call(
      actor_id: actor_id, entity: story,
      action: 'collaboration_changed',
      before_state: { mode: before_mode, assignment_count: before_count },
      after_state: after_state
    )
  end

  def self.collaboration_mode(count)
    case count
    when 0 then 'planned'
    when 1 then 'solo'
    when 2 then 'paired'
    else 'ensemble'
    end
  end
  private_class_method :collaboration_mode
end
