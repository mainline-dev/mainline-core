# frozen_string_literal: true

# A story as people and coding agents write its ID: the start of it, at least
# the 8 characters shown on its card, up to the whole UUID, in any case.
# Anything else, such as a placeholder left in a prompt, matches nothing and
# never reaches the database as a UUID.
module StoryId
  START = /\A[0-9a-f-]{8,}\z/

  # The stories, among those in the dataset given, that the ID names.
  def self.matching(stories, given)
    id = given.to_s.downcase
    return stories.where(false) unless id.match?(START)

    stories.where(Sequel.like(Sequel.cast(Sequel.qualify(stories.first_source_alias, :id), String), "#{id}%"))
  end
end
