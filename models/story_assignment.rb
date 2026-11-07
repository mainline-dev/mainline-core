# models/story_assignment.rb
# frozen_string_literal: true

class StoryAssignment < Sequel::Model(:story_assignments)
  many_to_one :story
  many_to_one :person
end
