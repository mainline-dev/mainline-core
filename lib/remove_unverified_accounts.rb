# frozen_string_literal: true

require_relative 'delete_person'

# Removes email signups whose address was never verified, created before the
# given time, that never joined a team: the shape of a bot signup. Anyone who
# joined a team by invite, or also signed in through Google, GitHub or GitLab,
# is kept. Returns how many it removed.
module RemoveUnverifiedAccounts
  def self.call(before:)
    people = Person.where(email_verified_at: nil)
      .where(id: PersonIdentity.where(provider: 'email').select(:person_id))
      .exclude(id: PersonIdentity.exclude(provider: 'email').select(:person_id))
      .exclude(id: TeamMembership.select(:person_id))
      .where { created_at < before }.all
    people.each { |person| DeletePerson.call(person: person) }
    people.size
  end
end
