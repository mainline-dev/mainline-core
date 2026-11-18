# frozen_string_literal: true

require_relative 'record_event'

# Changes a team's numbered settings, such as its limit on active stories or
# its inventory thresholds, and records each one that changed: what it was,
# what it became, and why when a reason is given. Several settings are saved
# together, with anything else that has to happen along with them, in one
# transaction, so a setting never changes without its record.
module ChangeTeamConstraint
  def self.call(team:, actor:, settings:, reason:)
    DB.transaction do
      settings.each { |setting| change(team, actor, reason, **setting) }
      yield if block_given?
    end
  end

  def self.change(team, actor, reason, key:, value:, min:, max:, default:)
    was = TeamConstraint.for_team(team.id, key, default: default)
    save(team, key, value, min: min, max: max, default: default)
    return if was == value

    RecordEvent.call(
      actor_id: actor.id, entity: TeamConstraint.where(team_id: team.id, constraint_key: key).first, action: 'updated',
      before_state: { constraint_key: key, value: was }, after_state: { constraint_key: key, value: value, reason: reason }.compact
    )
  end

  def self.save(team, key, value, min:, max:, default:)
    DB[:team_constraints].insert_conflict(
      target: %i[team_id constraint_key], update: { value: value, updated_at: Sequel.lit('now()') }
    ).insert(
      id: Sequel.lit('gen_random_uuid()'), team_id: team.id, constraint_key: key, value: value,
      min_value: min, max_value: max, default_value: default, updated_at: Sequel.lit('now()')
    )
  end
  private_class_method :change, :save
end
