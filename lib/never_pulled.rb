# frozen_string_literal: true

# How much of a team's backlog was never pulled onto the map: of the tickets
# that came into the museum 90 or more days ago, the share never promoted, as
# a whole percentage. Nothing until the first import is that old. Epics and
# sub-tasks are never promoted in their own right, and stories proposed from a
# specification were never anyone's backlog, so they are left out.
module NeverPulled
  AFTER_DAYS = 90

  def self.percent(team_id, now: Time.now)
    cutoff = now - (AFTER_DAYS * 86_400)
    tickets = MuseumItem.where(team_id: team_id).exclude(source: 'mainline').where { created_at <= cutoff }
      .all.reject { |item| item.epic? || item.sub_task? }
    return if tickets.empty?

    (tickets.count { |item| item.promoted_at.nil? } * 100.0 / tickets.size).round
  end
end
