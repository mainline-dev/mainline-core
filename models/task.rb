# models/tasks.rb
# frozen_string_literal: true

class Task < Sequel::Model
  many_to_one :activity
  many_to_one :map
  many_to_one :team
  one_to_many :stories, order: :position

  def validate
    super
    validates_presence [:name, :activity_id, :map_id, :team_id]
    validates_max_length 100, :name
  end
end
