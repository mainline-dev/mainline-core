# frozen_string_literal: true

# What a driver sets up and looks up for someone creating their first team:
# the person, who has an account and no team, and the team their form made.
module FirstTeamRecords
  def person_without_a_team(name:, email:)
    Person.create(name: name, email: email)
  end

  def team_named(name)
    Team.where(name: name).first
  end
end
