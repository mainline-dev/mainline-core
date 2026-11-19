# frozen_string_literal: true

# How much of a team's backlog was never pulled onto the map: of the tickets
# that came into the museum 90 or more days ago, the share never promoted, as
# a whole percentage. Nothing until the first import is that old. Epics and
# sub-tasks are never promoted in their own right, and stories proposed from a
# specification were never anyone's backlog, so they are left out.
module NeverPulled
  AFTER_DAYS = 90
  WAIT = AFTER_DAYS * 86_400
  # MuseumItem#epic? and #sub_task?, said so the database can find the oldest
  # ticket without every ticket being read.
  NEVER_PROMOTED_ALONE = %w[epic sub-task subtask].freeze

  # When the percentage is first given: 90 days after the oldest ticket it
  # counts came in. Never, for a team with no such ticket.
  def self.due(team_id)
    oldest = MuseumItem.where(team_id: team_id).exclude(source: 'mainline')
      .exclude(Sequel.function(:lower, :issue_type) => NEVER_PROMOTED_ALONE).min(:created_at)
    oldest && (oldest + WAIT)
  end

  def self.percent(team_id, now: Time.now)
    cutoff = now - WAIT
    tickets = MuseumItem.where(team_id: team_id).exclude(source: 'mainline').where { created_at <= cutoff }
      .all.reject { |item| item.epic? || item.sub_task? }
    return if tickets.empty?

    (tickets.count { |item| item.promoted_at.nil? } * 100.0 / tickets.size).round
  end
end
