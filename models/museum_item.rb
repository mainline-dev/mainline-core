# frozen_string_literal: true

# An issue imported into the Ticket Museum, frozen until promoted to a story on a map.
class MuseumItem < Sequel::Model
  many_to_one :story

  # Known by Jira's default type names.
  def epic?
    issue_type.casecmp?('epic')
  end

  def sub_task?
    issue_type.match?(/\Asub-?task\z/i)
  end

  # On display and a ticket in its own right.
  def promotable?
    !promoted_at && !discarded_at && !epic? && !sub_task?
  end

  def validate
    super
    validates_presence %i[team_id source_key issue_type summary]
    validates_max_length 50, %i[source_key issue_type]
    validates_max_length 255, :summary
  end
end
