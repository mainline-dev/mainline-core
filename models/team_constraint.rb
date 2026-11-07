# frozen_string_literal: true

class TeamConstraint < Sequel::Model
  many_to_one :team

  def self.for_team(team_id, key, default:)
    val = where(team_id: team_id, constraint_key: key).first&.value
    val.nil? ? default : val
  end
end
