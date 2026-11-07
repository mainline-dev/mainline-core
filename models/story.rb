# models/story.rb
# frozen_string_literal: true

class Story < Sequel::Model
  many_to_one :task
  many_to_one :map
  many_to_one :team
  many_to_one :created_by, class: :Person, key: :created_by_id
  many_to_one :split_from, class: :Story, key: :split_from_id
  many_to_one :release_slice
  one_to_many :story_assignments
  one_to_many :scenarios, order: :position
  many_to_many :people, join_table: :story_assignments

  def validate
    super
    validates_presence [:title, :task_id, :map_id, :team_id, :created_by_id]
  end
end
