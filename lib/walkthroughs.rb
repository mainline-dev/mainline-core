# frozen_string_literal: true

require_relative 'two_person_rule'

# What the Walkthroughs page shows.
module Walkthroughs
  # A story waiting for a walkthrough: the people on it, who show it, and the
  # working members who are not, any of whom could attend.
  Needed = Struct.new(:story, :on_it, :could_attend, keyword_init: true)

  def self.needed(team)
    stories = TwoPersonRule.awaiting(team)
    working = working_members(team)
    on_story = StoryAssignment.where(story_id: stories.map(&:id)).all.group_by(&:story_id)
    people = Person.where(id: on_story.values.flatten.map(&:person_id)).to_hash(:id)
    stories.map { |story|
      ids = on_story.fetch(story.id, []).map(&:person_id)
      Needed.new(story: story, on_it: people.values_at(*ids).compact,
        could_attend: working.reject { |person| ids.include?(person.id) })
    }
  end

  def self.working_members(team)
    Person.where(id: TeamMembership.where(team_id: team.id, working: true, left_at: nil).select(:person_id))
      .order(:name).all
  end
  private_class_method :working_members
end
