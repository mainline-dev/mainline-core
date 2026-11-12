# frozen_string_literal: true

# Puts a person on a story, up to the team's WIP limit: one active story per
# person unless the team has raised it. The limit is checked under a lock on
# the person, in the transaction that assigns, so two assignments at once
# can't both pass. Lowering a limit leaves stories in flight alone; the person
# just can't start another until they are under it.
module AssignPerson
  Result = Struct.new(:success?, :errors, keyword_init: true)

  WIP_KEY = 'max_active_stories'
  DEFAULT_WIP_LIMIT = 1
  WIP_CEILING = 5

  def self.wip_limit(team)
    TeamConstraint.for_team(team.id, WIP_KEY, default: DEFAULT_WIP_LIMIT)
  end

  # The people on the team who can't take another story.
  def self.people_at_limit(team)
    active_assignments(team)
      .group_and_count(Sequel[:story_assignments][:person_id])
      .having { count(Sequel.lit('*')) >= AssignPerson.wip_limit(team) }
      .select_map(Sequel[:story_assignments][:person_id])
      .to_set
  end

  def self.call(story:, person_id:, team:, actor_id:)
    errors = validate(story, person_id, team)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    DB.transaction do
      lock_person(person_id, team)
      next Result.new(success?: false, errors: [limit_message(team)]) if at_limit?(person_id, team)

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
      Result.new(success?: true, errors: [])
    end
  rescue Sequel::UniqueConstraintViolation
    Result.new(success?: false, errors: ['Person is already assigned to this story'])
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

    'Person is already assigned to this story' if StoryAssignment.where(story_id: story.id, person_id: person_id).any?
  end
  private_class_method :assignment_conflict

  def self.active_assignments(team)
    StoryAssignment
      .join(:stories, id: :story_id)
      .where(Sequel[:story_assignments][:team_id] => team.id)
      .where(Sequel[:stories][:archived_at] => nil)
  end
  private_class_method :active_assignments

  def self.lock_person(person_id, team)
    DB.get(Sequel.function(:pg_advisory_xact_lock, Sequel.function(:hashtext, "wip:#{team.id}:#{person_id}")))
  end
  private_class_method :lock_person

  def self.at_limit?(person_id, team)
    active_assignments(team).where(Sequel[:story_assignments][:person_id] => person_id).count >= wip_limit(team)
  end
  private_class_method :at_limit?

  def self.limit_message(team)
    limit = wip_limit(team)
    "Person is at the team's limit of #{limit} active #{limit == 1 ? 'story' : 'stories'}"
  end
  private_class_method :limit_message

  def self.maybe_activate(story, team, actor_id, count)
    return unless story.status == 'planned'

    working_count = TeamMembership.where(team_id: team.id, left_at: nil, working: true).count
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
