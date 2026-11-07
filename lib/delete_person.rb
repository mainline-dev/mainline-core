# frozen_string_literal: true

require_relative 'core_events'

module DeletePerson
  # Rows owned by the person are deleted.
  OWNED_ROWS = {
    team_memberships:  :person_id,
    map_view_prefs:    :person_id,
    story_assignments: :person_id,
    person_identities: :person_id
  }.freeze

  # Shared records keep their history; only the reference to the person is cleared.
  REFERENCES = {
    teams:       :creator_id,
    stories:     :created_by_id,
    story_notes: :dismissed_by,
    invitations: :invited_by
  }.freeze

  def self.call(person:)
    pid = person.id

    BypassRLS.call do
      CoreEvents.publish(:person_deleted, person_id: pid)
      OWNED_ROWS.each { |table, column| DB[table].where(column => pid).delete }
      REFERENCES.each { |table, column| DB[table].where(column => pid).update(column => nil) }
      Person.where(id: pid).delete
    end
  end
end
