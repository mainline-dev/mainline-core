# frozen_string_literal: true

module ResourceCap
  STORIES_PER_MAP    = { soft: 1000, hard: 2000 }.freeze
  MAPS_PER_TEAM      = { soft: 40,   hard: 80 }.freeze
  TEAMS_PER_PERSON   = { soft: 10,   hard: 20 }.freeze

  def self.check(count:, soft:, hard:)
    if count >= hard
      :blocked
    elsif count >= soft
      :warning
    else
      :ok
    end
  end

  def self.stories_per_map(count)
    check(count: count, **STORIES_PER_MAP)
  end

  def self.maps_per_team(count)
    check(count: count, **MAPS_PER_TEAM)
  end

  def self.teams_per_person(count)
    check(count: count, **TEAMS_PER_PERSON)
  end
end
