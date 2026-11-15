# frozen_string_literal: true

require_relative 'two_person_rule'
require_relative 'kickoff'

# What the Walkthroughs page shows.
module Walkthroughs
  # A story waiting for a walkthrough: the people on it, who show it, the
  # working members who are not, any of whom could attend, how many
  # scenarios there are to walk through, and where its kickoff stands.
  Needed = Struct.new(:story, :on_it, :could_attend, :scenario_count, :kickoff, keyword_init: true)

  def self.needed(team)
    stories = TwoPersonRule.awaiting(team)
    working = working_members(team)
    on_story = StoryAssignment.where(story_id: stories.map(&:id)).all.group_by(&:story_id)
    people = Person.where(id: on_story.values.flatten.map(&:person_id)).to_hash(:id)
    scenarios = Scenario.where(story_id: stories.map(&:id)).group_and_count(:story_id).to_hash(:story_id, :count)
    stories.map { |story|
      ids = on_story.fetch(story.id, []).map(&:person_id)
      Needed.new(story: story, on_it: people.values_at(*ids).compact,
        could_attend: working.reject { |person| ids.include?(person.id) },
        scenario_count: scenarios.fetch(story.id, 0), kickoff: Kickoff.for(story).kind)
    }
  end

  def self.working_members(team)
    Person.where(id: TeamMembership.where(team_id: team.id, working: true, left_at: nil).select(:person_id))
      .order(:name).all
  end
  private_class_method :working_members
end
