# models/activity.rb
# frozen_string_literal: true

class Activity < Sequel::Model
  many_to_one :map
  many_to_one :team
  many_to_many :personas, join_table: :activity_personas
  one_to_many :tasks, order: :position

  def validate
    super
    validates_presence [:name, :map_id, :team_id]
    validates_max_length 100, :name
  end
end
