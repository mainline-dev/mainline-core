# frozen_string_literal: true

# One upload of a Jira CSV to the Ticket Museum: staged until someone imports
# or cancels it, then a record of what it did.
class MuseumImport < Sequel::Model
  many_to_one :actor

  def validate
    super
    validates_presence %i[team_id actor_id file_name status]
    validates_max_length 255, :file_name
    validates_includes %w[staged imported cancelled undone], :status
  end
end
