# frozen_string_literal: true

require_relative 'ci_monitor'
require_relative 'core_events'

module DeleteTeam
  def self.call(team:)
    team_id = team.id

    person_ids = TeamMembership.where(team_id: team_id).select_map(:person_id)
    webhook_actor_id = team.webhook_actor_id
    mcp_actor_id = team.mcp_actor_id

    DB.transaction do
      # set_config(..., is_local: true) is a no-op outside a transaction,
      # so the context must be set inside this block.
      SetTeamContext.call(team_id)
      DB.run("SELECT delete_team_data(#{DB.literal(team_id)})")
      CIMonitor.delete_team_data(team_id)
      CoreEvents.publish(:team_deleted, team_id: team_id)

      Invitation.where(team_id: team_id).delete
      TeamMembership.where(team_id: team_id).delete
      Team.where(id: team_id).delete

      person_ids.each { |pid| delete_orphaned_person(pid) }
      Actor.where(id: webhook_actor_id).delete if webhook_actor_id
      Actor.where(id: mcp_actor_id).delete if mcp_actor_id
    end
  end

  def self.delete_orphaned_person(pid)
    return if TeamMembership.where(person_id: pid).any?
    return if Team.where(creator_id: pid).any?
    return if PersonIdentity.where(person_id: pid).any?

    person = Person[pid]
    return unless person

    CoreEvents.publish(:person_deleted, person_id: pid)

    aid = person.actor_id
    Person.where(id: pid).delete
    Actor.where(id: aid).delete if aid
  end

  private_class_method :delete_orphaned_person
end
