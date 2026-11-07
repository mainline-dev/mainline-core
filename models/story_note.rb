# frozen_string_literal: true

class StoryNote < Sequel::Model
  many_to_one :story
  many_to_one :dismisser, class: :Person, key: :dismissed_by
end
