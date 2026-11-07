# models/team_membership.rb
# frozen_string_literal: true

class TeamMembership < Sequel::Model
  many_to_one :team
  many_to_one :person
end
