# frozen_string_literal: true

require_relative 'two_person_rule'
require_relative 'kickoff'
require_relative 'record_walkthrough'

# What the Walkthroughs page shows.
module Walkthroughs
  # A story waiting for a walkthrough: the people on it, who show it, the
  # working members who are not, any of whom could attend, how many
  # scenarios there are to walk through, and where its kickoff stands.
  Needed = Struct.new(:story, :on_it, :could_attend, :scenario_count, :kickoff, keyword_init: true)
  # A story walked through and not yet released: who attended its
  # walkthroughs, each once, and whether it has been deployed again since the
  # latest of them.
  Walked = Struct.new(:story, :attended, :deployed_since, keyword_init: true)

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

  def self.walked(team)
    walks = Event.where(team_id: team.id, entity_type: RecordEvent.entity_type_for(Story), action: RecordWalkthrough::ACTION)
      .all.group_by(&:entity_id)
    people = Person.where(id: walks.values.flat_map { |story_walks| attendees(story_walks) }).order(:name).all
    Story.where(id: walks.keys, status: 'active', archived_at: nil).order(:last_deployed_at).all.map { |story|
      attending = attendees(walks[story.id])
      Walked.new(story: story, attended: people.select { |person| attending.include?(person.id) },
        deployed_since: deployed_since?(story, walks[story.id]))
    }
  end

  # A deploy after the latest walkthrough, which recorded how many there had
  # been. A walkthrough that did not record it says nothing either way.
  def self.deployed_since?(story, story_walks)
    recorded = story_walks.max_by(&:event_no).after_state['deploy_count']
    !recorded.nil? && story.deploy_count > recorded
  end

  # Everyone who attended any of these walkthroughs.
  def self.attendees(walks)
    walks.flat_map { |walk| walk.after_state['attendee_ids'].to_a }
  end

  def self.working_members(team)
    Person.where(id: TeamMembership.where(team_id: team.id, working: true, left_at: nil).select(:person_id))
      .order(:name).all
  end
  private_class_method :working_members, :attendees, :deployed_since?
end
