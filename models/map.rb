# models/map.rb
# frozen_string_literal: true

class Map < Sequel::Model
  many_to_one :team
  one_to_many :personas, order: :position
  one_to_many :activities, order: :position
  one_to_many :tasks
  one_to_many :stories
  one_to_many :release_slices, order: :position

  def validate
    super
    validates_presence [:name, :team_id]
    validates_max_length 100, :name
  end
end
